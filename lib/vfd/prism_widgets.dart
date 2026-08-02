import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/optical_profile.dart';
import 'prism_glyphs.dart';
import 'vfd_widgets.dart';

part 'prism_painters.dart';

enum PrismRole { compact, standard, primary }

enum PrismSpan { one, two, three }

enum PrismSymbol { undo, redo }

/// Normalized stamped geometry shared by every Prism symbol renderer.
abstract final class PrismSymbolGeometry {
  static Path path(PrismSymbol symbol, Size size) {
    double x(double value) =>
        size.width * (symbol == PrismSymbol.undo ? value : 1 - value);
    double y(double value) => size.height * value;

    return Path()
      ..moveTo(x(0.08), y(0.45))
      ..lineTo(x(0.37), y(0.08))
      ..lineTo(x(0.37), y(0.29))
      ..lineTo(x(0.61), y(0.29))
      ..lineTo(x(0.86), y(0.51))
      ..lineTo(x(0.86), y(0.91))
      ..lineTo(x(0.69), y(0.91))
      ..lineTo(x(0.69), y(0.58))
      ..lineTo(x(0.57), y(0.48))
      ..lineTo(x(0.37), y(0.48))
      ..lineTo(x(0.37), y(0.68))
      ..close();
  }
}

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
    this.face,
    this.symbol,
    this.lit = false,
    this.selected = false,
    this.enabled = true,
    this.role = PrismRole.standard,
    this.span = PrismSpan.one,
    this.style = const PrismStyle(),
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  }) : assert(face == null || symbol == null);

  final String label;
  final String? value;
  final Widget? face;
  final PrismSymbol? symbol;
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
                  TweenAnimationBuilder<double>(
                    key: const ValueKey('prism-cap'),
                    tween: Tween<double>(begin: 0, end: _pressed ? 1 : 0),
                    duration: pressDuration,
                    curve: Curves.linear,
                    builder: (context, pressProgress, _) => Transform.scale(
                      key: const ValueKey('prism-cap-transform'),
                      scale: 1 - pressProgress * 0.035,
                      alignment: Alignment.center,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _PrismCapPainter(
                            palette: widget.palette,
                            style: widget.style,
                            lit: widget.lit,
                            enabled: enabled,
                            pressProgress: pressProgress,
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              widget.role == PrismRole.compact ? 8 : 10,
                              9,
                              widget.role == PrismRole.compact ? 8 : 10,
                              12,
                            ),
                            child: _face(enabled),
                          ),
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

  Widget _face(bool enabled) {
    if (widget.face case final face?) return face;
    if (widget.symbol case final symbol?) {
      return PrismSymbolFace(
        symbol: symbol,
        palette: widget.palette,
        lit: widget.lit,
        enabled: enabled,
        role: widget.role,
        inactiveLuminosity: widget.style.inactiveLuminosity,
        activeLuminosity: widget.style.activeLuminosity,
      );
    }
    return _label(enabled);
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

class PrismSymbolFace extends StatelessWidget {
  const PrismSymbolFace({
    super.key,
    required this.symbol,
    required this.palette,
    required this.lit,
    required this.enabled,
    required this.role,
    required this.inactiveLuminosity,
    required this.activeLuminosity,
  });

  final PrismSymbol symbol;
  final VfdPalette palette;
  final bool lit;
  final bool enabled;
  final PrismRole role;
  final double inactiveLuminosity;
  final double activeLuminosity;

  @override
  Widget build(BuildContext context) {
    final size = switch (role) {
      PrismRole.compact => const Size(21, 16),
      PrismRole.standard => const Size(24, 18),
      PrismRole.primary => const Size(28, 21),
    };
    return Center(
      child: CustomPaint(
        key: ValueKey('prism-symbol-${symbol.name}'),
        size: size,
        painter: _PrismSymbolPainter(
          symbol: symbol,
          color: _prismFaceColor(
            palette: palette,
            lit: lit,
            enabled: enabled,
            inactiveLuminosity: inactiveLuminosity,
          ),
          glowColor: palette.lit,
          glow: lit ? activeLuminosity : 0,
        ),
      ),
    );
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
    final color = _prismFaceColor(
      palette: palette,
      lit: lit,
      enabled: enabled,
      inactiveLuminosity: inactiveLuminosity,
    );

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

Color _prismFaceColor({
  required VfdPalette palette,
  required bool lit,
  required bool enabled,
  required double inactiveLuminosity,
}) {
  final neutral = Color.lerp(const Color(0xFFAEB6B1), palette.unlit, 0.12)!;
  final inactiveAlpha = (0.24 + inactiveLuminosity * 0.9).clamp(0.18, 0.68);
  return lit
      ? palette.lit.withValues(alpha: enabled ? 1 : 0.48)
      : neutral.withValues(alpha: enabled ? inactiveAlpha : 0.24);
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
