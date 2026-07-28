import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/optical_profile.dart';
import 'prism_glyphs.dart';
import 'vfd_widgets.dart';

part 'prism_painters.dart';

enum PrismRole { compact, standard, primary }

enum PrismSpan { one, two, three }

abstract final class PrismMetrics {
  static double height(PrismRole role) => switch (role) {
    PrismRole.compact => 44,
    PrismRole.standard => 54,
    PrismRole.primary => 66,
  };

  static double width(PrismRole role, PrismSpan span) {
    final height = PrismMetrics.height(role);
    return height * (1.18 + span.index);
  }
}

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
    this.span = PrismSpan.one,
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
  final PrismSpan span;
  final PrismStyle style;
  final bool soundEnabled;
  final bool hapticsEnabled;

  @override
  State<PrismButton> createState() => _PrismButtonState();
}

class _PrismButtonState extends State<PrismButton> {
  bool _pressed = false;
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onPressed != null;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final pressDuration = reduceMotion
        ? Duration.zero
        : Duration(milliseconds: _pressed ? 45 : 95);

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
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
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
            child: SizedBox(
              key: const ValueKey('prism-housing'),
              width: PrismMetrics.width(widget.role, widget.span),
              height: PrismMetrics.height(widget.role),
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: <Widget>[
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _PrismHousingPainter(
                        palette: widget.palette,
                        selected: widget.selected,
                        focused: _focused,
                        hovered: _hovered,
                        enabled: enabled,
                      ),
                    ),
                  ),
                  AnimatedSlide(
                    key: const ValueKey('prism-cap'),
                    offset: Offset(0, _pressed ? 0.07 : 0),
                    duration: pressDuration,
                    curve: Curves.easeOutQuart,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _PrismCapPainter(
                          palette: widget.palette,
                          style: widget.style,
                          lit: widget.lit,
                          enabled: enabled,
                          pressed: _pressed,
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            widget.role == PrismRole.compact ? 8 : 10,
                            9,
                            widget.role == PrismRole.compact ? 8 : 10,
                            12,
                          ),
                          child: _label(enabled),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(bool enabled) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PrismLegend(
          widget.label,
          palette: widget.palette,
          lit: widget.lit,
          enabled: enabled,
          inactiveLuminosity: widget.style.inactiveLuminosity,
          size: switch (widget.role) {
            PrismRole.compact => 12,
            PrismRole.standard => 14,
            PrismRole.primary => 16,
          },
        ),
        if (widget.value != null) ...<Widget>[
          const SizedBox(height: 1),
          PrismLegend(
            widget.value!,
            palette: widget.palette,
            lit: widget.lit,
            enabled: enabled,
            inactiveLuminosity: widget.style.inactiveLuminosity,
            size: switch (widget.role) {
              PrismRole.compact => 9,
              PrismRole.standard => 11,
              PrismRole.primary => 13,
            },
          ),
        ],
      ],
    ),
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

class PrismLegend extends StatelessWidget {
  const PrismLegend(
    this.text, {
    super.key,
    required this.palette,
    required this.lit,
    required this.enabled,
    required this.inactiveLuminosity,
    required this.size,
  });

  final String text;
  final VfdPalette palette;
  final bool lit;
  final bool enabled;
  final double inactiveLuminosity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final active = palette.lit;
    final neutral = Color.lerp(const Color(0xFFAEB6B1), palette.unlit, 0.12)!;
    final inactiveAlpha = (0.24 + inactiveLuminosity * 0.9).clamp(0.18, 0.68);
    final color = lit
        ? active.withValues(alpha: enabled ? 1 : 0.48)
        : neutral.withValues(alpha: enabled ? inactiveAlpha : 0.24);

    return Text(
      PrismGlyphs.displayText(text),
      maxLines: 1,
      overflow: TextOverflow.clip,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontFamily: 'Barlow Condensed',
        fontSize: size,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w500,
        decoration: TextDecoration.none,
        letterSpacing: 1.05,
        height: 0.94,
        shadows: lit
            ? <Shadow>[
                Shadow(color: active.withValues(alpha: 0.72), blurRadius: 7),
                Shadow(color: active.withValues(alpha: 0.24), blurRadius: 14),
              ]
            : null,
      ),
    );
  }
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
