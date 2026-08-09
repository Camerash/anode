import 'package:flutter/widgets.dart';

import '../mechanical/prism_selector_bank.dart';
import '../mechanical/vfd_editable_field.dart';
import '../model/optical_profile.dart';
import '../model/param_spec.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_widgets.dart';

class ParamControlRow extends StatelessWidget {
  const ParamControlRow({
    super.key,
    required this.spec,
    required this.value,
    required this.palette,
    required this.prismStyle,
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.onChanged,
  });

  final ParamSpec spec;
  final Object? value;
  final VfdPalette palette;
  final PrismStyle prismStyle;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: spec.label,
    child: Row(
      children: <Widget>[
        Expanded(
          flex: 4,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: VfdLegend(spec.label, palette: palette, size: 9),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(flex: 7, child: _control()),
      ],
    ),
  );

  Widget _control() => switch (spec.type) {
    ParamType.boolean => _boolean(),
    ParamType.option => _options(),
    ParamType.integer || ParamType.number => _number(),
    ParamType.text => _text(),
  };

  Widget _boolean() {
    final selected = value as bool;
    return Align(
      alignment: Alignment.centerRight,
      child: PrismButton(
        key: ValueKey('param-${spec.key}-toggle'),
        label: 'On',
        palette: palette,
        lit: selected,
        selected: selected,
        role: PrismRole.compact,
        style: prismStyle,
        onPressed: () => onChanged(!selected),
      ),
    );
  }

  Widget _options() => PrismSelectorBank<String>(
    key: ValueKey('param-${spec.key}-options'),
    choices: <PrismSelectorChoice<String>>[
      for (final option in spec.options)
        PrismSelectorChoice<String>(
          value: option,
          label: spec.labelForOption(option),
          lit: value == option,
        ),
    ],
    selected: value as String,
    palette: palette,
    prismStyle: prismStyle,
    rows: 1,
    role: PrismRole.compact,
    soundEnabled: soundEnabled,
    hapticsEnabled: hapticsEnabled,
    semanticLabel: spec.label,
    onSelected: onChanged,
  );

  Widget _number() {
    final numeric = value as num;
    final integer = spec.type == ParamType.integer;
    final step = integer ? 1.0 : (spec.step ?? 0.01);
    final precision = integer ? 0 : (spec.precision ?? 2);
    return Row(
      children: <Widget>[
        _stepButton(
          label: '-',
          keySuffix: 'decrement',
          next: numeric.toDouble() - step,
          integer: integer,
        ),
        const SizedBox(width: 5),
        if (spec.editorHint == ParamEditorHint.cellStrip) ...<Widget>[
          Expanded(
            child: _CellStrip(
              key: ValueKey('param-${spec.key}-cell-strip'),
              value: numeric.toDouble(),
              min: spec.min ?? 0,
              max: spec.max ?? numeric.toDouble(),
              palette: palette,
            ),
          ),
          const SizedBox(width: 5),
        ] else if (!integer &&
            spec.min != null &&
            spec.max != null) ...<Widget>[
          Expanded(
            child: VfdCellBar(
              value: numeric.toDouble(),
              min: spec.min!,
              max: spec.max!,
              palette: palette,
              step: step,
              precision: precision,
              semanticLabel: spec.label,
              onChanged: (next) => onChanged(spec.coerce(next)),
            ),
          ),
          const SizedBox(width: 5),
        ],
        SizedBox(
          width: integer ? 28 : 55,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: VfdLegend(
              _formatted(numeric, precision),
              palette: palette,
              lit: true,
              size: 11,
            ),
          ),
        ),
        const SizedBox(width: 5),
        _stepButton(
          label: '+',
          keySuffix: 'increment',
          next: numeric.toDouble() + step,
          integer: integer,
        ),
      ],
    );
  }

  Widget _stepButton({
    required String label,
    required String keySuffix,
    required double next,
    required bool integer,
  }) => PrismButton(
    key: ValueKey('param-${spec.key}-$keySuffix'),
    label: label,
    palette: palette,
    role: PrismRole.compact,
    style: prismStyle,
    onPressed: () => onChanged(
      integer ? (spec.coerce(next) as num).round() : spec.coerce(next),
    ),
  );

  Widget _text() => VfdEditableField(
    key: ValueKey('param-${spec.key}-text'),
    label: spec.label,
    value: value as String,
    palette: palette,
    showLabel: false,
    onChanged: onChanged,
  );

  String _formatted(num number, int precision) {
    final suffix = spec.unitSuffix == null ? '' : ' ${spec.unitSuffix}';
    return '${number.toDouble().toStringAsFixed(precision)}$suffix';
  }
}

class _CellStrip extends StatelessWidget {
  const _CellStrip({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.palette,
  });

  final double value;
  final double min;
  final double max;
  final VfdPalette palette;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _CellStripPainter(
      fraction: max <= min ? 0 : ((value - min) / (max - min)).clamp(0, 1),
      palette: palette,
    ),
  );
}

class _CellStripPainter extends CustomPainter {
  const _CellStripPainter({required this.fraction, required this.palette});

  static const _cellCount = 12;

  final double fraction;
  final VfdPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 2.0;
    final width = (size.width - gap * (_cellCount - 1)) / _cellCount;
    final litCount = (fraction * _cellCount).round();
    for (var index = 0; index < _cellCount; index++) {
      final rect = Rect.fromLTWH(
        index * (width + gap),
        size.height * 0.28,
        width,
        size.height * 0.44,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = index < litCount
              ? palette.lit.withValues(alpha: 0.86)
              : palette.unlit.withValues(alpha: 0.34),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CellStripPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.palette != palette;
}
