import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../model/component_type.dart';
import '../model/dashboard.dart';
import '../model/placement.dart';
import 'component_data.dart';
import 'vfd_layers.dart';

class SegmentBank {
  SegmentBank({this.digits = 3})
      : _target = Float32List(digits * 8),
        brightness = Float32List(digits * 8);

  static const List<int> _sevenSeg = <int>[
    0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F,
  ];

  static const double attackTau = 0.012;
  static const double decayTau = 0.075;

  final int digits;
  final Float32List _target;
  final Float32List brightness;
  int _lastValue = -1;

  void setValue(int value, {bool blankLeadingZeros = true}) {
    final ceiling = math.pow(10, digits).toInt() - 1;
    final clamped = value.clamp(0, ceiling);
    if (clamped == _lastValue) return;
    _lastValue = clamped;
    final text = clamped.toString().padLeft(digits, blankLeadingZeros ? ' ' : '0');
    for (var j = 0; j < digits; j++) {
      final ch = text[j];
      final mask = ch == ' ' ? 0 : _sevenSeg[int.parse(ch)];
      for (var i = 0; i < 7; i++) {
        _target[j * 8 + i] = ((mask >> i) & 1).toDouble();
      }
      _target[j * 8 + 7] = 0.0;
    }
  }

  void tick(double dt, {required bool decay}) {
    if (!decay) {
      brightness.setAll(0, _target);
      return;
    }
    for (var i = 0; i < brightness.length; i++) {
      final tau = _target[i] > brightness[i] ? attackTau : decayTau;
      final k = 1.0 - math.exp(-dt / tau);
      brightness[i] += (_target[i] - brightness[i]) * k;
    }
  }
}

class VfdController extends ChangeNotifier {
  VfdController({
    required TickerProvider vsync,
    required Dashboard dashboard,
    this.orientation = DesignOrientation.landscape,
    this.aspect = 2.6,
  }) : _dashboard = dashboard {
    _ticker = vsync.createTicker(_onTick)..start();
  }

  final DesignOrientation orientation;

  /// Aspect of the authored frame. A design declares this; it is not the
  /// device's aspect.
  final double aspect;

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  double time = 0;
  double speedKph = 0;
  double tilt = 0;
  double _tiltTarget = 0;
  VfdLayers layers = const VfdLayers();
  Phosphor phosphor = Phosphor.cyanGreen;

  Dashboard _dashboard;
  Dashboard get dashboard => _dashboard;
  set dashboard(Dashboard value) {
    _dashboard = value;
    _banks.clear();
  }

  /// One segment bank per digit component, so two digit gauges decay
  /// independently.
  final Map<String, SegmentBank> _banks = <String, SegmentBank>{};

  ui.Image? _dataImage;
  Float32List? _packed;
  int componentCount = 0;

  ui.Image? get dataImage => _dataImage;

  /// The unit the first speed readout is bound to. Per-component, not global —
  /// this reads it back off the data rather than holding a second copy.
  SpeedUnit get unit {
    for (final c in _dashboard.componentsIn(orientation)) {
      if (c.typeId == ComponentTypes.speedDigits) {
        return c.effectiveParams['unit'] == 'mph' ? SpeedUnit.mph : SpeedUnit.kph;
      }
    }
    return SpeedUnit.kph;
  }

  set unit(SpeedUnit value) {
    var next = _dashboard;
    for (final c in _dashboard.components) {
      if (c.typeId == ComponentTypes.speedDigits) {
        next = next.withComponent(c.withParam('unit', value.name));
      }
    }
    dashboard = next;
  }

  double get displaySpeed => unit.convert(speedKph);

  set tiltTarget(double v) => _tiltTarget = v.clamp(-1.0, 1.0);

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    time = elapsed.inMicroseconds / 1e6;

    final target = layers.tiltParallax ? _tiltTarget : 0.0;
    tilt += (target - tilt) * (1.0 - math.exp(-dt / 0.18));

    _rebuild(dt);
    notifyListeners();
  }

  void _rebuild(double dt) {
    final frames = <ComponentFrame>[];
    final litUnit = unit;

    for (final c in _dashboard.componentsIn(orientation)) {
      if (frames.length >= ComponentData.maxComponents) break;
      final type = ComponentTypes.byId(c.typeId);
      final placement = c.placements[orientation];
      if (type == null || placement == null) continue;

      final center = placement.resolve(aspect);
      final size = placement.resolveSize(type);
      final params = c.effectiveParams;

      switch (c.typeId) {
        case ComponentTypes.speedDigits:
          final digits = (params['digits'] as num?)?.toInt() ?? 3;
          final componentUnit =
              params['unit'] == 'mph' ? SpeedUnit.mph : SpeedUnit.kph;
          final bank = _banks.putIfAbsent(
            c.id,
            () => SegmentBank(digits: digits),
          );
          bank.setValue(
            componentUnit.convert(speedKph).round(),
            blankLeadingZeros: params['blankLeadingZeros'] as bool? ?? true,
          );
          bank.tick(dt, decay: layers.phosphorDecay);
          frames.add(ComponentFrame(
            type: ShaderType.digits,
            centerX: center.dx,
            centerY: center.dy,
            width: size.width,
            height: size.height,
            paramA: digits.toDouble(),
            segments: bank.brightness,
          ));

        case ComponentTypes.speedBar:
          final cells = (params['cells'] as num?)?.toDouble() ?? 20;
          final full = (params['maxKph'] as num?)?.toDouble() ?? 260;
          frames.add(ComponentFrame(
            type: ShaderType.bar,
            centerX: center.dx,
            centerY: center.dy,
            width: size.width,
            height: size.height,
            paramA: cells,
            paramB: (speedKph / full).clamp(0.0, 1.0),
          ));

        case ComponentTypes.unitLegend:
          frames.add(ComponentFrame(
            type: ShaderType.legend,
            centerX: center.dx,
            centerY: center.dy,
            width: size.width,
            height: size.height,
            paramA: litUnit == SpeedUnit.mph ? 1.0 : 0.0,
          ));

        default:
          // A declared type the renderer cannot draw yet is skipped, not faked.
          continue;
      }
    }

    componentCount = frames.length;

    // Only re-upload when something actually moved. Digits change once or twice
    // a second; the decay ramp dirties this for a few frames after each change
    // and nothing in between.
    final packed = ComponentData.pack(frames);
    if (_packed != null && _sameAs(packed)) return;
    _packed = packed;
    _dataImage?.dispose();
    _dataImage = ComponentData.encode(frames);
  }

  bool _sameAs(Float32List candidate) {
    final previous = _packed!;
    if (previous.length != candidate.length) return false;
    for (var i = 0; i < previous.length; i++) {
      if (previous[i] != candidate[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _dataImage?.dispose();
    super.dispose();
  }
}

class VfdPainter extends CustomPainter {
  VfdPainter({
    required this.shader,
    required this.controller,
    required this.safeRect,
  }) : super(repaint: controller);

  final ui.FragmentShader shader;
  final VfdController controller;

  /// Where content is laid out, in Flutter's y-down logical pixels. The render
  /// still covers the full bounds — this only positions the authored frame.
  final Rect safeRect;

  @override
  void paint(Canvas canvas, Size size) {
    final data = controller.dataImage;
    if (data == null) return;

    final l = controller.layers;
    final p = controller.phosphor;

    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, controller.time)
      ..setFloat(3, controller.tilt)
      ..setFloat(4, p.r)
      ..setFloat(5, p.g)
      ..setFloat(6, p.b)
      ..setFloat(7, l.bloom ? 1.0 : 0.0)
      ..setFloat(8, l.unlitSegments ? 1.0 : 0.0)
      ..setFloat(9, l.gridMesh ? 1.0 : 0.0)
      ..setFloat(10, l.filamentWires ? 1.0 : 0.0)
      ..setFloat(11, l.grain ? 1.0 : 0.0)
      // Shader space is y-up; Rect is y-down.
      ..setFloat(12, safeRect.left)
      ..setFloat(13, size.height - safeRect.bottom)
      ..setFloat(14, safeRect.right)
      ..setFloat(15, size.height - safeRect.top)
      ..setFloat(16, controller.aspect)
      ..setFloat(17, controller.componentCount.toDouble())
      ..setFloat(18, ComponentData.texelsPerComponent.toDouble())
      ..setFloat(19, ComponentData.maxComponents.toDouble())
      ..setImageSampler(0, data);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant VfdPainter old) =>
      old.shader != shader ||
      old.controller != controller ||
      old.safeRect != safeRect;
}

class VfdCluster extends StatefulWidget {
  const VfdCluster({
    super.key,
    required this.program,
    required this.controller,
    this.safeInsets,
  });

  final ui.FragmentProgram program;
  final VfdController controller;

  /// Where content may be laid out inside this widget. Defaults to the window
  /// padding, which is only correct when the cluster fills the window — a
  /// parent that shrinks it (the settings dock) must pass its own insets.
  final EdgeInsets? safeInsets;

  @override
  State<VfdCluster> createState() => _VfdClusterState();
}

class _VfdClusterState extends State<VfdCluster> {
  late final ui.FragmentShader _shader = widget.program.fragmentShader();

  @override
  void dispose() {
    _shader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.safeInsets ?? MediaQuery.paddingOf(context);

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final safeRect = Rect.fromLTRB(
            padding.left,
            padding.top,
            math.max(padding.left + 1, size.width - padding.right),
            math.max(padding.top + 1, size.height - padding.bottom),
          );

          return CustomPaint(
            painter: VfdPainter(
              shader: _shader,
              controller: widget.controller,
              safeRect: safeRect,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}
