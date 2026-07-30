import 'package:flutter/widgets.dart';

import '../mechanical/mechanical_pager.dart';
import '../mechanical/prism_selector_bank.dart';
import '../mechanical/vfd_editable_field.dart';
import '../model/optical_profile.dart';
import '../model/param_spec.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_widgets.dart';

class ParamEditor extends StatelessWidget {
  const ParamEditor({
    super.key,
    required this.specs,
    required this.values,
    required this.palette,
    required this.prismStyle,
    required this.onChanged,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  });

  final List<ParamSpec> specs;
  final Map<String, Object?> values;
  final VfdPalette palette;
  final PrismStyle prismStyle;
  final void Function(String key, Object? value) onChanged;
  final bool soundEnabled;
  final bool hapticsEnabled;

  @override
  Widget build(BuildContext context) {
    if (specs.isEmpty) {
      return VfdLegend('No parameters', palette: palette, size: 10);
    }
    return SizedBox(
      height: 164,
      child: MechanicalPager(
        pages: <Widget>[
          for (final spec in specs)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _ParamControl(
                spec: spec,
                value: spec.coerce(values[spec.key]),
                palette: palette,
                prismStyle: prismStyle,
                soundEnabled: soundEnabled,
                hapticsEnabled: hapticsEnabled,
                onChanged: (value) => onChanged(spec.key, value),
              ),
            ),
        ],
        palette: palette,
        prismStyle: prismStyle,
        soundEnabled: soundEnabled,
        hapticsEnabled: hapticsEnabled,
        semanticLabel: 'Parameter',
      ),
    );
  }
}

class _ParamControl extends StatelessWidget {
  const _ParamControl({
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
  Widget build(BuildContext context) => switch (spec.type) {
    ParamType.boolean => _boolean(),
    ParamType.option => _options(),
    ParamType.integer || ParamType.number => _number(),
    ParamType.text => _text(),
  };

  Widget _boolean() => PrismButton(
    label: spec.label,
    palette: palette,
    lit: value as bool,
    selected: value as bool,
    span: PrismSpan.two,
    style: prismStyle,
    soundEnabled: soundEnabled,
    hapticsEnabled: hapticsEnabled,
    onPressed: () => onChanged(!(value as bool)),
  );

  Widget _options() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      VfdLegend(spec.label, palette: palette, lit: true, size: 11),
      const SizedBox(height: 8),
      PrismSelectorBank<String>(
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
        rows: 2,
        soundEnabled: soundEnabled,
        hapticsEnabled: hapticsEnabled,
        semanticLabel: spec.label,
        onSelected: onChanged,
      ),
    ],
  );

  Widget _number() {
    final numeric = value as num;
    if (spec.min == null || spec.max == null) {
      return VfdEditableField(
        label: spec.label,
        value: numeric.toString(),
        palette: palette,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        onChanged: (raw) {
          final parsed = num.tryParse(raw);
          if (parsed != null) onChanged(spec.coerce(parsed));
        },
      );
    }
    final integer = spec.type == ParamType.integer;
    final step = integer ? 1.0 : (spec.step ?? 0.01);
    final precision = integer ? 0 : (spec.precision ?? 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        VfdLegend(spec.label, palette: palette, lit: true, size: 11),
        const SizedBox(height: 7),
        Row(
          children: <Widget>[
            Expanded(
              child: VfdCellBar(
                value: numeric.toDouble(),
                min: spec.min!,
                max: spec.max!,
                palette: palette,
                step: step,
                precision: precision,
                semanticLabel: spec.label,
                onChanged: (next) =>
                    onChanged(integer ? next.round() : spec.coerce(next)),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              child: VfdLegend(
                _formatted(numeric, precision),
                palette: palette,
                lit: true,
                size: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            _step('-', numeric.toDouble() - step, integer),
            const SizedBox(width: 6),
            _step('+', numeric.toDouble() + step, integer),
          ],
        ),
      ],
    );
  }

  Widget _step(String label, double next, bool integer) => PrismButton(
    label: label,
    palette: palette,
    role: PrismRole.compact,
    style: prismStyle,
    soundEnabled: soundEnabled,
    hapticsEnabled: hapticsEnabled,
    onPressed: () => onChanged(
      integer ? (spec.coerce(next) as num).round() : spec.coerce(next),
    ),
  );

  Widget _text() => VfdEditableField(
    label: spec.label,
    value: value as String,
    palette: palette,
    onChanged: onChanged,
  );

  String _formatted(num number, int precision) {
    final suffix = spec.unitSuffix == null ? '' : ' ${spec.unitSuffix}';
    return '${number.toDouble().toStringAsFixed(precision)}$suffix';
  }
}
