import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/optical_profile.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_widgets.dart';
import 'mechanical_pager.dart';

@immutable
class PrismSelectorChoice<T> {
  const PrismSelectorChoice({
    required this.value,
    required this.label,
    this.controlKey,
    this.face,
    this.lit = false,
    this.enabled = true,
  });

  final T value;
  final String label;
  final Key? controlKey;
  final Widget? face;
  final bool lit;
  final bool enabled;
}

/// Responsive fixed-slot bank. Overflow becomes indexed pages, never scrolling.
class PrismSelectorBank<T> extends StatelessWidget {
  const PrismSelectorBank({
    super.key,
    required this.choices,
    required this.selected,
    required this.palette,
    required this.prismStyle,
    required this.onSelected,
    this.controller,
    this.rows = 2,
    this.columns,
    this.role = PrismRole.compact,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.semanticLabel = 'Choices',
  });

  final List<PrismSelectorChoice<T>> choices;
  final T? selected;
  final VfdPalette palette;
  final PrismStyle prismStyle;
  final ValueChanged<T> onSelected;
  final MechanicalPagerController? controller;
  final int rows;
  final int? columns;
  final PrismRole role;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 6.0;
      final resolvedColumns = columns ?? (constraints.maxWidth >= 360 ? 3 : 2);
      final pages = paginateCompleteRows(
        choices,
        columns: resolvedColumns,
        rows: rows,
      );
      final rowHeight = PrismMetrics.height(role);
      final bankHeight = rows * rowHeight + math.max(0, rows - 1) * gap;
      return SizedBox(
        height: bankHeight,
        child: MechanicalPager(
          pages: <Widget>[
            for (final page in pages)
              _ChoicePage<T>(
                choices: page,
                selected: selected,
                columns: resolvedColumns,
                rows: rows,
                gap: gap,
                palette: palette,
                prismStyle: prismStyle,
                role: role,
                soundEnabled: soundEnabled,
                hapticsEnabled: hapticsEnabled,
                onSelected: onSelected,
              ),
          ],
          palette: palette,
          prismStyle: prismStyle,
          controller: controller,
          soundEnabled: soundEnabled,
          hapticsEnabled: hapticsEnabled,
          semanticLabel: semanticLabel,
        ),
      );
    },
  );
}

class _ChoicePage<T> extends StatelessWidget {
  const _ChoicePage({
    required this.choices,
    required this.selected,
    required this.columns,
    required this.rows,
    required this.gap,
    required this.palette,
    required this.prismStyle,
    required this.role,
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.onSelected,
  });

  final List<PrismSelectorChoice<T>> choices;
  final T? selected;
  final int columns;
  final int rows;
  final double gap;
  final VfdPalette palette;
  final PrismStyle prismStyle;
  final PrismRole role;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      for (var row = 0; row < rows; row++) ...<Widget>[
        if (row > 0) SizedBox(height: gap),
        Expanded(
          child: Row(
            children: <Widget>[
              for (var column = 0; column < columns; column++) ...<Widget>[
                if (column > 0) SizedBox(width: gap),
                Expanded(child: _slot(row * columns + column)),
              ],
            ],
          ),
        ),
      ],
    ],
  );

  Widget _slot(int index) {
    if (index >= choices.length) return const SizedBox.expand();
    final choice = choices[index];
    final isSelected = choice.value == selected;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: PrismButton(
          key: choice.controlKey ?? ValueKey<T>(choice.value),
          label: choice.label,
          face: choice.face,
          palette: palette,
          lit: choice.lit,
          selected: isSelected,
          enabled: choice.enabled,
          role: role,
          span: PrismSpan.two,
          style: prismStyle,
          onPressed: choice.enabled ? () => onSelected(choice.value) : null,
        ),
      ),
    );
  }
}
