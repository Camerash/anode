import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../model/component_type.dart';
import '../model/component_instance.dart';
import '../model/design.dart';
import '../model/optical_profile.dart';
import '../model/placement.dart';
import '../model/vfd_module.dart';
import 'component_data.dart';
import 'prism_glyphs.dart';
import 'vfd_render_assets.dart';
import 'vfd_types.dart';

class SegmentBank {
  SegmentBank({this.digits = 3})
    : _target = Float32List(digits * 8),
      brightness = Float32List(digits * 8);

  static const List<int> _sevenSeg = <int>[
    0x3F,
    0x06,
    0x5B,
    0x4F,
    0x66,
    0x6D,
    0x7D,
    0x07,
    0x7F,
    0x6F,
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
    final text = clamped.toString().padLeft(
      digits,
      blankLeadingZeros ? ' ' : '0',
    );
    for (var j = 0; j < digits; j++) {
      final ch = text[j];
      final mask = ch == ' ' ? 0 : _sevenSeg[int.parse(ch)];
      for (var i = 0; i < 7; i++) {
        _target[j * 8 + i] = ((mask >> i) & 1).toDouble();
      }
      _target[j * 8 + 7] = 0.0;
    }
  }

  void tick(double dt, {required double decayStrength}) {
    if (decayStrength <= 0) {
      brightness.setAll(0, _target);
      return;
    }
    for (var i = 0; i < brightness.length; i++) {
      final tau = _target[i] > brightness[i]
          ? attackTau
          : decayTau * decayStrength;
      final k = 1.0 - math.exp(-dt / tau);
      brightness[i] += (_target[i] - brightness[i]) * k;
    }
  }
}

class VfdController extends ChangeNotifier {
  VfdController({
    required TickerProvider vsync,
    required Design design,
    DesignOrientation orientation = DesignOrientation.landscape,
  }) : _design = design,
       _orientation = design.supports(orientation)
           ? orientation
           : design.supportedOrientations.first {
    _ticker = vsync.createTicker(_onTick)..start();
  }

  DesignOrientation _orientation;
  DesignOrientation get orientation => _orientation;
  set orientation(DesignOrientation value) {
    if (!_design.supports(value) || value == _orientation) return;
    _orientation = value;
    _banks.clear();
  }

  /// Aspect of the authored frame. A design declares this; it is not the
  /// device's aspect.
  double get aspect => _design.frameAspect(_orientation);

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  double time = 0;
  double speedKph = 0;
  double tilt = 0;
  double _tiltTarget = 0;
  bool reduceMotion = false;

  OpticalProfile get opticalProfile => _design.renderSettings.opticalProfile;
  Phosphor get phosphor => opticalProfile.phosphor;

  Design _design;
  Design get design => _design;
  set design(Design value) {
    if (identical(value, _design)) return;
    _design = value;
    if (!value.supports(_orientation)) {
      _orientation = value.supportedOrientations.first;
    }
    _banks.clear();
  }

  /// One segment bank per digit component, so two digit gauges decay
  /// independently.
  final Map<String, SegmentBank> _banks = <String, SegmentBank>{};
  final Set<String> _pressedComponents = <String>{};

  ui.Image? _dataImage;
  Float32List? _packed;
  int componentCount = 0;

  ui.Image? get dataImage => _dataImage;

  /// The unit the first speed readout is bound to. Per-component, not global —
  /// this reads it back off the data rather than holding a second copy.
  SpeedUnit get unit {
    for (final c in _design.componentsIn(orientation)) {
      if (c.typeId == ComponentTypes.speedDigits) {
        return c.effectiveParams['unit'] == 'mph'
            ? SpeedUnit.mph
            : SpeedUnit.kph;
      }
    }
    return SpeedUnit.kph;
  }

  double get displaySpeed => unit.convert(speedKph);

  set tiltTarget(double v) => _tiltTarget = v.clamp(-1.0, 1.0);

  void setComponentPressed(String componentId, bool pressed) {
    if (pressed) {
      _pressedComponents.add(componentId);
    } else {
      _pressedComponents.remove(componentId);
    }
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    time = elapsed.inMicroseconds / 1e6;

    final tiltStrength = opticalProfile.effect(EffectIds.tiltParallax).strength;
    final target = reduceMotion ? 0.0 : _tiltTarget * tiltStrength;
    tilt += (target - tilt) * (1.0 - math.exp(-dt / 0.18));

    _rebuild(dt);
    notifyListeners();
  }

  void _rebuild(double dt) {
    final frames = <ComponentFrame>[];
    final litUnit = unit;

    for (final c in _design.componentsIn(orientation)) {
      if (frames.length >= ComponentData.maxComponents) break;
      final type = ComponentTypes.byId(c.typeId);
      final placement = c.placements[orientation];
      if (type == null || placement == null) continue;

      final center = placement.resolve(aspect);
      final size = placement.resolveSize(type, variant: c.effectiveVariant);
      final params = c.effectiveParams;
      final moduleProfile = opticalProfile.apply(
        _design.moduleFor(c).opticalOverrides,
      );
      final profile = moduleProfile.apply(c.opticalOverrides);

      switch (c.typeId) {
        case ComponentTypes.speedDigits:
          final digits = (params['digits'] as num?)?.toInt() ?? 3;
          final componentUnit = params['unit'] == 'mph'
              ? SpeedUnit.mph
              : SpeedUnit.kph;
          final bank = _banks.putIfAbsent(
            c.id,
            () => SegmentBank(digits: digits),
          );
          bank.setValue(
            componentUnit.convert(speedKph).round(),
            blankLeadingZeros: params['blankLeadingZeros'] as bool? ?? true,
          );
          bank.tick(
            dt,
            decayStrength: profile.effect(EffectIds.phosphorDecay).strength,
          );
          frames.add(
            _frame(
              component: c,
              type: ShaderType.digits,
              center: center,
              size: size,
              profile: profile,
              moduleProfile: moduleProfile,
              paramA: digits.toDouble(),
              segments: bank.brightness,
            ),
          );

        case ComponentTypes.speedBar:
          final cells = (params['cells'] as num?)?.toDouble() ?? 20;
          final full = (params['maxKph'] as num?)?.toDouble() ?? 260;
          frames.add(
            _frame(
              component: c,
              type: ShaderType.bar,
              center: center,
              size: size,
              profile: profile,
              moduleProfile: moduleProfile,
              paramA: cells,
              paramB: (speedKph / full).clamp(0.0, 1.0),
            ),
          );

        case ComponentTypes.unitLegend:
          frames.add(
            _frame(
              component: c,
              type: ShaderType.legend,
              center: center,
              size: size,
              profile: profile,
              moduleProfile: moduleProfile,
              paramA: litUnit == SpeedUnit.mph ? 1.0 : 0.0,
            ),
          );

        case ComponentTypes.prismButton:
          frames.add(
            _frame(
              component: c,
              type: ShaderType.prism,
              center: center,
              size: size,
              profile: profile,
              moduleProfile: moduleProfile,
              prismLit: params['lit'] == true ? 1 : 0,
              prismGlyphs: PrismGlyphs.encode(params['label'] as String? ?? ''),
            ),
          );

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

  ComponentFrame _frame({
    required ComponentInstance component,
    required double type,
    required Offset center,
    required Size size,
    required OpticalProfile profile,
    required OpticalProfile moduleProfile,
    double paramA = 0,
    double paramB = 0,
    double prismLit = 0,
    List<double>? prismGlyphs,
    List<double>? segments,
  }) {
    final module = _moduleGeometry(component);
    final filamentVariant = FilamentVariants.byReference(
      _design.moduleFor(component).filamentVariant,
    );
    final p = profile.phosphor;
    return ComponentFrame(
      type: type,
      centerX: center.dx,
      centerY: center.dy,
      width: size.width,
      height: size.height,
      paramA: paramA,
      paramB: paramB,
      variantCode:
          (component.type?.variant(component.effectiveVariant)?.rendererCode ??
                  0)
              .toDouble(),
      phosphorR: p.r,
      phosphorG: p.g,
      phosphorB: p.b,
      emission: profile.effect(EffectIds.emission).strength,
      bloom: profile.effect(EffectIds.bloom).strength,
      phosphorTexture: profile.effect(EffectIds.phosphorTexture).strength,
      grid: profile.effect(EffectIds.gridMesh).strength,
      unlit: profile.effect(EffectIds.unlitPhosphor).strength,
      decay: profile.effect(EffectIds.phosphorDecay).strength,
      moduleCenterX: module.center.dx,
      moduleCenterY: module.center.dy,
      moduleWidth: module.size.width,
      moduleHeight: module.size.height,
      glassGrain: moduleProfile.effect(EffectIds.glassGrain).strength,
      filament: moduleProfile.effect(EffectIds.filamentWires).strength,
      filamentVariantCode: (filamentVariant?.rendererCode ?? 0).toDouble(),
      prismLit: prismLit * _design.renderSettings.prismStyle.activeLuminosity,
      prismPressed: _pressedComponents.contains(component.id) ? 1 : 0,
      prismBevelDepth: _design.renderSettings.prismStyle.bevelDepth,
      prismFaceOpacity: _design.renderSettings.prismStyle.faceOpacity,
      prismInactiveLuminosity:
          _design.renderSettings.prismStyle.inactiveLuminosity,
      prismGlyphs: prismGlyphs,
      segments: segments,
    );
  }

  ({Offset center, Size size}) _moduleGeometry(ComponentInstance component) {
    final module = _design.moduleFor(component);
    final placement = module.regionIn(orientation);
    if (module.id == kMainVfdModuleId || placement == null) {
      return (center: Offset.zero, size: Size(aspect, 1));
    }
    return (
      center: placement.resolve(aspect),
      size: placement.size ?? Size(aspect, 1),
    );
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
    required this.prismGlyphAtlas,
    required this.controller,
    required this.safeRect,
  }) : super(repaint: controller);

  final ui.FragmentShader shader;
  final ui.Image prismGlyphAtlas;
  final VfdController controller;

  /// Where content is laid out, in Flutter's y-down logical pixels. The render
  /// still covers the full bounds — this only positions the authored frame.
  final Rect safeRect;

  @override
  void paint(Canvas canvas, Size size) {
    final data = controller.dataImage;
    if (data == null) return;

    final p = controller.phosphor;
    final profile = controller.opticalProfile;

    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, controller.time)
      ..setFloat(3, controller.tilt)
      ..setFloat(4, p.r)
      ..setFloat(5, p.g)
      ..setFloat(6, p.b)
      ..setFloat(7, profile.effect(EffectIds.bloom).strength)
      ..setFloat(8, profile.effect(EffectIds.unlitPhosphor).strength)
      ..setFloat(9, profile.effect(EffectIds.gridMesh).strength)
      ..setFloat(10, profile.effect(EffectIds.filamentWires).strength)
      ..setFloat(11, profile.effect(EffectIds.glassGrain).strength)
      // Shader space is y-up; Rect is y-down.
      ..setFloat(12, safeRect.left)
      ..setFloat(13, size.height - safeRect.bottom)
      ..setFloat(14, safeRect.right)
      ..setFloat(15, size.height - safeRect.top)
      ..setFloat(16, controller.aspect)
      ..setFloat(17, controller.componentCount.toDouble())
      ..setFloat(18, ComponentData.texelsPerComponent.toDouble())
      ..setFloat(19, ComponentData.maxComponents.toDouble())
      ..setImageSampler(0, data)
      ..setImageSampler(1, prismGlyphAtlas);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant VfdPainter old) =>
      old.shader != shader ||
      old.prismGlyphAtlas != prismGlyphAtlas ||
      old.controller != controller ||
      old.safeRect != safeRect;
}

class VfdCluster extends StatefulWidget {
  const VfdCluster({
    super.key,
    required this.renderAssets,
    required this.controller,
    this.safeInsets,
  });

  final VfdRenderAssets renderAssets;
  final VfdController controller;

  /// Where content may be laid out inside this widget. Defaults to the window
  /// padding, which is only correct when the cluster fills the window — a
  /// parent that shrinks it (the settings dock) must pass its own insets.
  final EdgeInsets? safeInsets;

  @override
  State<VfdCluster> createState() => _VfdClusterState();
}

class _VfdClusterState extends State<VfdCluster> {
  late final ui.FragmentShader _shader = widget.renderAssets.program
      .fragmentShader();

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
              prismGlyphAtlas: widget.renderAssets.prismGlyphAtlas,
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
