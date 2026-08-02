import 'package:flutter/widgets.dart';

import 'vfd_types.dart';

/// Flutter-side colours for chrome drawn on the substrate. The real emission
/// comes from the shader; these approximate it flatly and deliberately do not
/// try to imitate the two-lobe halo, which would look worse beside the real one.
@immutable
class VfdPalette {
  const VfdPalette({required this.lit, required this.unlit});

  factory VfdPalette.of(Phosphor p) {
    final lit = Color.fromRGBO(
      (p.r * 255).round().clamp(0, 255),
      (p.g * 255).round().clamp(0, 255),
      (p.b * 255).round().clamp(0, 255),
      1,
    );
    // Unlit phosphor reads as a pale warm grey carrying a trace of the coating.
    return VfdPalette(
      lit: lit,
      unlit: Color.lerp(const Color(0xFF7C8681), lit, 0.16)!,
    );
  }

  final Color lit;
  final Color unlit;

  Color state(bool isLit) => isLit ? lit : unlit;
}

/// Uppercase, letterspaced legend. A faint glow stands in for emission.
class VfdLegend extends StatelessWidget {
  const VfdLegend(
    this.text, {
    super.key,
    required this.palette,
    this.lit = false,
    this.size = 11,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final VfdPalette palette;
  final bool lit;
  final double size;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final color = palette.state(lit);
    return Text(
      text.toUpperCase(),
      maxLines: maxLines,
      overflow: overflow,
      style: TextStyle(
        color: color,
        fontFamily: 'Barlow Condensed',
        fontStyle: FontStyle.italic,
        fontSize: size,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w600,
        height: 1.1,
        shadows: lit
            ? <Shadow>[
                Shadow(color: color.withValues(alpha: 0.55), blurRadius: 8),
              ]
            : null,
      ),
    );
  }
}

/// Etched rectangular control. No fill, no elevation, no ripple.
class VfdButton extends StatelessWidget {
  const VfdButton({
    super.key,
    required this.label,
    required this.palette,
    required this.onTap,
    this.lit = false,
  });

  final String label;
  final VfdPalette palette;
  final VoidCallback onTap;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final color = palette.state(lit);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: lit ? 0.85 : 0.35)),
          boxShadow: lit
              ? <BoxShadow>[
                  BoxShadow(
                    color: color.withValues(alpha: 0.20),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: VfdLegend(label, palette: palette, lit: lit),
      ),
    );
  }
}

/// Quantity control built from the gauge's own cell rule: cell i is lit when
/// (i + 0.5) / n <= fraction. A continuous Material slider does not belong on
/// this substrate.
class VfdCellBar extends StatelessWidget {
  const VfdCellBar({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.palette,
    this.onChanged,
    this.cells = 24,
    this.height = 16,
    this.step,
    this.precision = 2,
    this.semanticLabel = 'Value',
  });

  final double value;
  final double min;
  final double max;
  final VfdPalette palette;
  final ValueChanged<double>? onChanged;
  final int cells;
  final double height;
  final double? step;
  final int precision;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);

    final enabled = onChanged != null;
    final resolvedStep = step ?? (max - min) / cells;
    double snapped(double raw) {
      final units = ((raw - min) / resolvedStep).round();
      return (min + units * resolvedStep).clamp(min, max);
    }

    void change(double raw) => onChanged?.call(snapped(raw));

    return Semantics(
      slider: true,
      enabled: enabled,
      label: semanticLabel,
      value: value.toStringAsFixed(precision),
      increasedValue: snapped(value + resolvedStep).toStringAsFixed(precision),
      decreasedValue: snapped(value - resolvedStep).toStringAsFixed(precision),
      onIncrease: enabled ? () => change(value + resolvedStep) : null,
      onDecrease: enabled ? () => change(value - resolvedStep) : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          void set(Offset local) {
            final f = (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
            change(min + f * (max - min));
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (d) => set(d.localPosition) : null,
            onHorizontalDragUpdate: enabled
                ? (d) => set(d.localPosition)
                : null,
            child: SizedBox(
              height: height,
              child: Row(
                children: <Widget>[
                  for (var i = 0; i < cells; i++)
                    Expanded(
                      child: _Cell(
                        lit: (i + 0.5) / cells <= fraction,
                        palette: palette,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.lit, required this.palette});

  final bool lit;
  final VfdPalette palette;

  @override
  Widget build(BuildContext context) {
    final color = palette.state(lit);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1.2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: lit ? 0.92 : 0.22),
        boxShadow: lit
            ? <BoxShadow>[
                BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 6),
              ]
            : null,
      ),
    );
  }
}

/// Hairline etched rule, for separating groups of controls.
class VfdRule extends StatelessWidget {
  const VfdRule({super.key, required this.palette, this.height = 20});

  final VfdPalette palette;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: height,
    color: palette.unlit.withValues(alpha: 0.35),
  );
}
