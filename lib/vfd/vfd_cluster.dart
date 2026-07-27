import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
    final clamped = value.clamp(0, 999);
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
  VfdController({required TickerProvider vsync, this.maxKph = 260}) {
    _ticker = vsync.createTicker(_onTick)..start();
  }

  final double maxKph;
  final SegmentBank bank = SegmentBank();

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  double time = 0;
  double speedKph = 0;
  double tilt = 0;
  double _tiltTarget = 0;
  VfdLayers layers = const VfdLayers();
  Phosphor phosphor = Phosphor.cyanGreen;
  SpeedUnit unit = SpeedUnit.kph;

  /// The bar always tracks the underlying kph, so switching unit does not move
  /// it. Only the digits and the lit legend change.
  double get barFraction => (speedKph / maxKph).clamp(0.0, 1.0);

  double get displaySpeed => unit.convert(speedKph);

  set tiltTarget(double v) => _tiltTarget = v.clamp(-1.0, 1.0);

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    time = elapsed.inMicroseconds / 1e6;

    final target = layers.tiltParallax ? _tiltTarget : 0.0;
    tilt += (target - tilt) * (1.0 - math.exp(-dt / 0.18));

    bank.setValue(displaySpeed.round());
    bank.tick(dt, decay: layers.phosphorDecay);
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
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
      ..setFloat(12, controller.barFraction);

    final b = controller.bank.brightness;
    for (var i = 0; i < 24; i++) {
      shader.setFloat(13 + i, i < b.length ? b[i] : 0.0);
    }

    // Shader space is y-up; Rect is y-down.
    shader
      ..setFloat(37, safeRect.left)
      ..setFloat(38, size.height - safeRect.bottom)
      ..setFloat(39, safeRect.right)
      ..setFloat(40, size.height - safeRect.top)
      ..setFloat(41, controller.unit == SpeedUnit.mph ? 1.0 : 0.0);

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
  /// parent that shrinks it (the settings panel) must pass its own insets.
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
