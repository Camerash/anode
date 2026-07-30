import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../model/optical_profile.dart';
import '../vfd/vfd_widgets.dart';
import 'mechanical_feedback.dart';

/// Cable-driven automotive slider: a fixed recessed faceplate and one moving
/// smoked thumb. The thumb alone starts a drag; tapping the track cannot
/// teleport a physical control.
class MechanicalLever extends StatefulWidget {
  const MechanicalLever({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.palette,
    required this.prismStyle,
    required this.onChanged,
    this.precision = 2,
    this.tickCount = 21,
    this.referenceValue,
    this.offAtMinimum = false,
    this.leading,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  }) : assert(max > min),
       assert(tickCount >= 2);

  final String label;
  final double value;
  final double min;
  final double max;
  final int precision;
  final int tickCount;
  final double? referenceValue;
  final bool offAtMinimum;
  final Widget? leading;
  final VfdPalette palette;
  final PrismStyle prismStyle;
  final ValueChanged<double>? onChanged;
  final bool soundEnabled;
  final bool hapticsEnabled;

  @override
  State<MechanicalLever> createState() => _MechanicalLeverState();
}

class _MechanicalLeverState extends State<MechanicalLever> {
  static const double _height = 94;
  static const double _thumbVisualWidth = 28;
  static const double _thumbVisualHeight = 34;
  static const double _thumbHitExtent = 44;

  bool _dragging = false;
  bool _focused = false;
  double _grabOffsetX = 0;
  int? _feedbackDetent;

  bool get _enabled => widget.onChanged != null;
  List<double> get _detents => mechanicalLeverDetents(
    min: widget.min,
    max: widget.max,
    count: widget.tickCount,
    referenceValue: widget.referenceValue,
  );
  double get _fraction =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0, 1);

  @override
  void didUpdateWidget(covariant MechanicalLever oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.min != widget.min ||
        oldWidget.max != widget.max ||
        oldWidget.tickCount != widget.tickCount ||
        oldWidget.referenceValue != widget.referenceValue) {
      _feedbackDetent = null;
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    slider: true,
    enabled: _enabled,
    label: widget.label,
    value: _displayValue(widget.value),
    increasedValue: _displayValue(_adjacentValue(1)),
    decreasedValue: _displayValue(_adjacentValue(-1)),
    onIncrease: _enabled ? () => _change(_adjacentValue(1)) : null,
    onDecrease: _enabled ? () => _change(_adjacentValue(-1)) : null,
    child: FocusableActionDetector(
      enabled: _enabled,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: <Type, Action<Intent>>{
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            if (intent.direction == TraversalDirection.left ||
                intent.direction == TraversalDirection.down) {
              _change(_adjacentValue(-1));
            } else if (intent.direction == TraversalDirection.right ||
                intent.direction == TraversalDirection.up) {
              _change(_adjacentValue(1));
            }
            return null;
          },
        ),
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, _height);
          final geometry = _LeverGeometry.from(
            size,
            fraction: _fraction,
            leading: widget.leading != null,
          );
          return Listener(
            key: const ValueKey('mechanical-lever'),
            behavior: HitTestBehavior.opaque,
            onPointerDown: _enabled
                ? (event) => _startDrag(event.localPosition, geometry)
                : null,
            onPointerMove: _enabled
                ? (event) => _drag(event.localPosition, geometry)
                : null,
            onPointerUp: _enabled ? (_) => _endDrag() : null,
            onPointerCancel: _enabled ? (_) => _endDrag() : null,
            onPointerSignal: _enabled
                ? (event) {
                    if (event is PointerScrollEvent) {
                      _change(
                        _adjacentValue(event.scrollDelta.dy > 0 ? -1 : 1),
                      );
                    }
                  }
                : null,
            child: SizedBox(
              height: _height,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _LeverFacePainter(
                        palette: widget.palette,
                        geometry: geometry,
                        detentFractions: _detents
                            .map(
                              (value) =>
                                  (value - widget.min) /
                                  (widget.max - widget.min),
                            )
                            .toList(growable: false),
                        currentDetent: _detentFor(widget.value),
                        referenceDetent: widget.referenceValue == null
                            ? null
                            : _detentFor(widget.referenceValue!),
                        enabled: _enabled,
                        focused: _focused,
                      ),
                    ),
                  ),
                  if (widget.leading case final leading?)
                    Positioned(
                      left: 9,
                      top: 23,
                      width: 34,
                      height: 34,
                      child: leading,
                    ),
                  Positioned(
                    right: 10,
                    top: 7,
                    child: VfdLegend(
                      _displayValue(widget.value),
                      palette: widget.palette,
                      lit: _enabled,
                      size: 11,
                    ),
                  ),
                  Positioned.fromRect(
                    rect: geometry.thumbHitRect,
                    child: Center(
                      child: CustomPaint(
                        key: const ValueKey('mechanical-lever-thumb'),
                        size: const Size(_thumbVisualWidth, _thumbVisualHeight),
                        painter: _LeverThumbPainter(
                          style: widget.prismStyle,
                          enabled: _enabled,
                          dragging: _dragging,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: geometry.trackLeft - 10,
                    right: size.width - geometry.trackRight - 10,
                    bottom: 5,
                    child: IgnorePointer(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          VfdLegend(
                            widget.offAtMinimum ? 'OFF' : 'MIN',
                            palette: widget.palette,
                            size: 7,
                          ),
                          if (widget.referenceValue != null)
                            VfdLegend('REF', palette: widget.palette, size: 7),
                          VfdLegend('MAX', palette: widget.palette, size: 7),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  void _startDrag(Offset local, _LeverGeometry geometry) {
    if (!geometry.thumbHitRect.contains(local)) return;
    _dragging = true;
    _grabOffsetX = local.dx - geometry.thumbCenter.dx;
    _feedbackDetent = _detentFor(widget.value);
    setState(() {});
  }

  void _drag(Offset local, _LeverGeometry geometry) {
    if (!_dragging) return;
    final x = local.dx - _grabOffsetX;
    final fraction = ((x - geometry.trackLeft) / geometry.trackWidth).clamp(
      0.0,
      1.0,
    );
    _change(widget.min + fraction * (widget.max - widget.min));
  }

  void _endDrag() {
    if (!_dragging) return;
    setState(() => _dragging = false);
  }

  void _change(double raw) {
    if (!_enabled) return;
    final detent = _detentFor(raw);
    final next = _detents[detent];
    if (next == widget.value) return;
    if (_feedbackDetent != detent) {
      _feedbackDetent = detent;
      actuateMechanicalFeedback(
        soundEnabled: widget.soundEnabled,
        hapticsEnabled: widget.hapticsEnabled,
      );
    }
    widget.onChanged?.call(next);
  }

  double _adjacentValue(int direction) {
    final detents = _detents;
    const epsilon = 1e-9;
    if (direction > 0) {
      return detents.firstWhere(
        (value) => value > widget.value + epsilon,
        orElse: () => detents.last,
      );
    }
    return detents.lastWhere(
      (value) => value < widget.value - epsilon,
      orElse: () => detents.first,
    );
  }

  int _detentFor(double value) {
    final detents = _detents;
    var nearest = 0;
    var distance = double.infinity;
    for (var index = 0; index < detents.length; index++) {
      final candidateDistance = (detents[index] - value).abs();
      if (candidateDistance < distance) {
        nearest = index;
        distance = candidateDistance;
      }
    }
    return nearest;
  }

  String _displayValue(double value) {
    if (widget.offAtMinimum && value <= widget.min) return 'OFF · 0.00';
    return value.toStringAsFixed(widget.precision);
  }
}

class _LeverGeometry {
  const _LeverGeometry({
    required this.trackLeft,
    required this.trackRight,
    required this.thumbCenter,
  });

  factory _LeverGeometry.from(
    Size size, {
    required double fraction,
    required bool leading,
  }) {
    final left = leading ? 59.0 : 22.0;
    final right = math.max(left + 1, size.width - 22);
    return _LeverGeometry(
      trackLeft: left,
      trackRight: right,
      thumbCenter: Offset(left + (right - left) * fraction, 61),
    );
  }

  final double trackLeft;
  final double trackRight;
  final Offset thumbCenter;

  double get trackWidth => trackRight - trackLeft;
  Rect get thumbHitRect => Rect.fromCenter(
    center: thumbCenter,
    width: _MechanicalLeverState._thumbHitExtent,
    height: _MechanicalLeverState._thumbHitExtent,
  );
}

class _LeverFacePainter extends CustomPainter {
  const _LeverFacePainter({
    required this.palette,
    required this.geometry,
    required this.detentFractions,
    required this.currentDetent,
    required this.referenceDetent,
    required this.enabled,
    required this.focused,
  });

  final VfdPalette palette;
  final _LeverGeometry geometry;
  final List<double> detentFractions;
  final int currentDetent;
  final int? referenceDetent;
  final bool enabled;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final face = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      face,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF202522),
            Color(0xFF090C0B),
            Color(0xFF121614),
          ],
        ).createShader(face.outerRect),
    );
    canvas.drawRRect(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = focused ? 1.5 : 1
        ..color = (focused ? palette.lit : const Color(0xFF7A827E)).withValues(
          alpha: enabled ? 0.68 : 0.25,
        ),
    );

    final slot = RRect.fromRectAndRadius(
      Rect.fromLTRB(geometry.trackLeft - 8, 55, geometry.trackRight + 8, 67),
      const Radius.circular(1),
    );
    canvas.drawRRect(slot, Paint()..color = const Color(0xFF010202));
    canvas.drawLine(
      Offset(slot.left + 1, slot.top + 1),
      Offset(slot.right - 1, slot.top + 1),
      Paint()
        ..strokeWidth = 1
        ..color = const Color(0xFF000000),
    );
    canvas.drawLine(
      Offset(slot.left + 1, slot.bottom - 1),
      Offset(slot.right - 1, slot.bottom - 1),
      Paint()
        ..strokeWidth = 1
        ..color = const Color(0xFF626B66).withValues(alpha: 0.35),
    );

    final inactive = Paint()
      ..strokeWidth = 1
      ..color = palette.unlit.withValues(alpha: enabled ? 0.34 : 0.16);
    final active = Paint()
      ..strokeWidth = 2
      ..color = palette.lit.withValues(alpha: enabled ? 0.95 : 0.32)
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2);
    for (var i = 0; i < detentFractions.length; i++) {
      final x = geometry.trackLeft + geometry.trackWidth * detentFractions[i];
      final isReference = i == referenceDetent;
      canvas.drawLine(
        Offset(x, isReference ? 22 : 25),
        Offset(x, 34),
        i == currentDetent ? active : inactive,
      );
      if (isReference) {
        canvas.drawLine(
          Offset(x + 3, 22),
          Offset(x + 3, 34),
          i == currentDetent ? active : inactive,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LeverFacePainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.geometry != geometry ||
      !listEquals(oldDelegate.detentFractions, detentFractions) ||
      oldDelegate.currentDetent != currentDetent ||
      oldDelegate.referenceDetent != referenceDetent ||
      oldDelegate.enabled != enabled ||
      oldDelegate.focused != focused;
}

/// Returns physical stop positions for a mechanical lever.
///
/// Uniform controls keep evenly spaced stops. A non-uniform tuned reference
/// replaces its nearest interior stop so thumb, value, indicator, and feedback
/// all share one physical state.
List<double> mechanicalLeverDetents({
  required double min,
  required double max,
  required int count,
  double? referenceValue,
}) {
  assert(max > min);
  assert(count >= 2);
  final interval = (max - min) / (count - 1);
  final detents = List<double>.generate(
    count,
    (index) => min + interval * index,
  );
  final reference = referenceValue;
  if (reference != null && reference > min && reference < max) {
    const epsilon = 1e-9;
    final alreadyPresent = detents.any(
      (value) => (value - reference).abs() <= epsilon,
    );
    if (!alreadyPresent && count > 2) {
      var nearest = 1;
      var distance = (detents[nearest] - reference).abs();
      for (var index = 2; index < count - 1; index++) {
        final candidateDistance = (detents[index] - reference).abs();
        if (candidateDistance < distance) {
          nearest = index;
          distance = candidateDistance;
        }
      }
      detents[nearest] = reference;
      detents.sort();
    }
  }
  return List<double>.unmodifiable(detents);
}

class _LeverThumbPainter extends CustomPainter {
  const _LeverThumbPainter({
    required this.style,
    required this.enabled,
    required this.dragging,
  });

  final PrismStyle style;
  final bool enabled;
  final bool dragging;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, dragging ? 3 : 1, size.width - 2, size.height - 5),
      const Radius.circular(1.5),
    );
    final opacity = enabled ? 1.0 : 0.45;
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            const Color(0xFFE2E6E4).withValues(alpha: 0.88 * opacity),
            const Color(0xFF929B96).withValues(alpha: 0.92 * opacity),
            Color.lerp(
              const Color(0xFF4A514D),
              const Color(0xFF080A09),
              style.faceOpacity,
            )!.withValues(alpha: opacity),
            const Color(0xFF111412).withValues(alpha: opacity),
          ],
          stops: const <double>[0, 0.18, 0.52, 1],
        ).createShader(rect.outerRect),
    );
    canvas.drawRRect(
      rect.deflate(4.5),
      Paint()
        ..color = const Color(
          0xFF070908,
        ).withValues(alpha: (0.28 + style.faceOpacity * 0.42) * opacity),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFD9DFDC).withValues(alpha: 0.58 * opacity),
    );
    canvas.drawLine(
      Offset(4, rect.top + 2),
      Offset(size.width - 4, rect.top + 2),
      Paint()
        ..strokeWidth = 0.8
        ..color = const Color(0xFFE8ECEA).withValues(alpha: 0.48 * opacity),
    );
    canvas.drawLine(
      Offset(3, rect.top + 4),
      Offset(3, rect.bottom - 3),
      Paint()
        ..strokeWidth = 0.8
        ..color = const Color(0xFFBBC3BF).withValues(alpha: 0.4 * opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _LeverThumbPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.enabled != enabled ||
      oldDelegate.dragging != dragging;
}
