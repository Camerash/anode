import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/optical_profile.dart';
import 'vfd_widgets.dart';

enum PrismRole { compact, standard, primary }

class PrismButton extends StatefulWidget {
  const PrismButton({
    super.key,
    required this.label,
    required this.palette,
    required this.onPressed,
    this.value,
    this.lit = false,
    this.selected = false,
    this.enabled = true,
    this.role = PrismRole.standard,
    this.style = const PrismStyle(),
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  });

  final String label;
  final String? value;
  final VfdPalette palette;
  final VoidCallback? onPressed;
  final bool lit;
  final bool selected;
  final bool enabled;
  final PrismRole role;
  final PrismStyle style;
  final bool soundEnabled;
  final bool hapticsEnabled;

  @override
  State<PrismButton> createState() => _PrismButtonState();
}

class _PrismButtonState extends State<PrismButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onPressed != null;
    final height = switch (widget.role) {
      PrismRole.compact => 38.0,
      PrismRole.standard => 54.0,
      PrismRole.primary => 66.0,
    };
    final horizontal = switch (widget.role) {
      PrismRole.compact => 10.0,
      PrismRole.standard => 14.0,
      PrismRole.primary => 18.0,
    };

    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      toggled: widget.lit,
      label: widget.label,
      value: widget.value,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: Listener(
          onPointerDown: enabled ? (_) => _setPressed(true) : null,
          onPointerUp: enabled ? (_) => _setPressed(false) : null,
          onPointerCancel: enabled ? (_) => _setPressed(false) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? _activate : null,
            child: AnimatedScale(
              scale: _pressed ? 0.985 : 1,
              duration: Duration(milliseconds: _pressed ? 55 : 105),
              curve: Curves.easeOutQuart,
              child: AnimatedSlide(
                offset: Offset(0, _pressed ? 0.045 : 0),
                duration: Duration(milliseconds: _pressed ? 55 : 105),
                curve: Curves.easeOutQuart,
                child: SizedBox(
                  height: height,
                  child: CustomPaint(
                    painter: _PrismPainter(
                      palette: widget.palette,
                      style: widget.style,
                      lit: widget.lit,
                      selected: widget.selected,
                      enabled: enabled,
                      pressed: _pressed,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontal,
                        vertical: 8,
                      ),
                      child: _label(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label() => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _StatusLamp(lit: widget.lit, palette: widget.palette),
      const SizedBox(width: 7),
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              VfdLegend(
                widget.label,
                palette: widget.palette,
                lit: widget.lit,
                size: widget.role == PrismRole.compact ? 9 : 10,
              ),
              if (widget.value != null) ...<Widget>[
                const SizedBox(height: 3),
                VfdLegend(
                  widget.value!,
                  palette: widget.palette,
                  lit: widget.lit,
                  size: 9,
                ),
              ],
            ],
          ),
        ),
      ),
    ],
  );

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _activate() {
    _setPressed(false);
    if (widget.soundEnabled) {
      SystemSound.play(SystemSoundType.click);
    }
    if (widget.hapticsEnabled) {
      HapticFeedback.lightImpact();
    }
    widget.onPressed?.call();
  }
}

class _StatusLamp extends StatelessWidget {
  const _StatusLamp({required this.lit, required this.palette});

  final bool lit;
  final VfdPalette palette;

  @override
  Widget build(BuildContext context) {
    final color = palette.state(lit);
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: lit ? 1 : 0.24),
        boxShadow: lit
            ? <BoxShadow>[
                BoxShadow(
                  color: color.withValues(alpha: 0.72),
                  blurRadius: 7,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

class _PrismPainter extends CustomPainter {
  const _PrismPainter({
    required this.palette,
    required this.style,
    required this.lit,
    required this.selected,
    required this.enabled,
    required this.pressed,
  });

  final VfdPalette palette;
  final PrismStyle style;
  final bool lit;
  final bool selected;
  final bool enabled;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final depth = math.max(3.0, size.height * style.bevelDepth);
    final bounds = Offset.zero & size;
    final back = Path()
      ..moveTo(depth, 0)
      ..lineTo(size.width - depth, 0)
      ..lineTo(size.width, size.height - depth)
      ..lineTo(size.width - depth, size.height)
      ..lineTo(depth, size.height)
      ..lineTo(0, size.height - depth)
      ..close();
    canvas.drawPath(
      back,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            const Color(0xFF9BA6A2).withValues(alpha: enabled ? 0.38 : 0.18),
            const Color(0xFF111615).withValues(alpha: 0.96),
            const Color(0xFF6C7672).withValues(alpha: enabled ? 0.42 : 0.16),
          ],
        ).createShader(bounds),
    );

    final face = Rect.fromLTRB(
      depth,
      depth * 0.72,
      size.width - depth,
      size.height - depth,
    );
    final light = palette.lit;
    canvas.drawRect(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.lerp(
              const Color(0xFF202826),
              light,
              lit ? 0.15 * style.activeLuminosity : 0,
            )!.withValues(alpha: style.faceOpacity),
            Color.lerp(
              const Color(0xFF080B0A),
              light,
              lit ? 0.08 * style.activeLuminosity : 0,
            )!.withValues(alpha: 0.98),
          ],
        ).createShader(face),
    );

    final edge = selected ? palette.lit : palette.unlit;
    canvas.drawRect(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 1.6 : 0.8
        ..color = edge.withValues(alpha: selected ? 0.9 : 0.42),
    );

    if (lit) {
      canvas.drawRect(
        face,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
          ..color = light.withValues(alpha: 0.26),
      );
    }

    canvas.drawLine(
      face.topLeft,
      face.topRight,
      Paint()
        ..strokeWidth = pressed ? 0.6 : 1.2
        ..color = const Color(0xFFD9E0DE).withValues(alpha: 0.34),
    );
  }

  @override
  bool shouldRepaint(covariant _PrismPainter oldDelegate) =>
      oldDelegate.lit != lit ||
      oldDelegate.selected != selected ||
      oldDelegate.enabled != enabled ||
      oldDelegate.pressed != pressed ||
      oldDelegate.palette != palette ||
      oldDelegate.style != style;
}

class PrismPanel extends StatelessWidget {
  const PrismPanel({
    super.key,
    required this.palette,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final VfdPalette palette;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF090D0C),
      border: Border.all(color: palette.unlit.withValues(alpha: 0.28)),
    ),
    child: Padding(padding: padding, child: child),
  );
}
