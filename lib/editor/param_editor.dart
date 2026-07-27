import 'package:flutter/material.dart';

import '../model/param_spec.dart';

class ParamEditor extends StatelessWidget {
  const ParamEditor({
    super.key,
    required this.specs,
    required this.values,
    required this.onChanged,
  });

  final List<ParamSpec> specs;
  final Map<String, Object?> values;
  final void Function(String key, Object? value) onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      for (final spec in specs)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _control(spec),
        ),
    ],
  );

  Widget _control(ParamSpec spec) {
    final value = spec.coerce(values[spec.key]);
    return switch (spec.type) {
      ParamType.boolean => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(spec.label),
        value: value as bool,
        onChanged: (next) => onChanged(spec.key, next),
      ),
      ParamType.option => DropdownButtonFormField<String>(
        initialValue: value as String,
        decoration: InputDecoration(labelText: spec.label),
        items: <DropdownMenuItem<String>>[
          for (final option in spec.options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: (next) => onChanged(spec.key, next),
      ),
      ParamType.integer || ParamType.number => _NumericParamControl(
        spec: spec,
        value: value as num,
        onChanged: (next) => onChanged(spec.key, next),
      ),
      ParamType.text => _TextParamControl(
        label: spec.label,
        value: value as String,
        onChanged: (next) => onChanged(spec.key, next),
      ),
    };
  }
}

class _NumericParamControl extends StatelessWidget {
  const _NumericParamControl({
    required this.spec,
    required this.value,
    required this.onChanged,
  });

  final ParamSpec spec;
  final num value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (spec.min == null || spec.max == null) {
      return _unboundedField();
    }
    final integer = spec.type == ParamType.integer;
    final divisions = integer ? (spec.max! - spec.min!).round() : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('${spec.label}: ${_formatted(integer)}'),
        Slider(
          value: value.toDouble().clamp(spec.min!, spec.max!),
          min: spec.min!,
          max: spec.max!,
          divisions: divisions == 0 ? null : divisions,
          label: _formatted(integer),
          onChanged: (next) => onChanged(integer ? next.round() : next),
        ),
      ],
    );
  }

  Widget _unboundedField() => TextFormField(
    initialValue: value.toString(),
    decoration: InputDecoration(labelText: spec.label),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (raw) {
      final parsed = num.tryParse(raw);
      if (parsed != null) onChanged(spec.coerce(parsed));
    },
  );

  String _formatted(bool integer) =>
      integer ? value.round().toString() : value.toStringAsFixed(2);
}

class _TextParamControl extends StatefulWidget {
  const _TextParamControl({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_TextParamControl> createState() => _TextParamControlState();
}

class _TextParamControlState extends State<_TextParamControl> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant _TextParamControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    focusNode: _focusNode,
    decoration: InputDecoration(labelText: widget.label),
    onChanged: widget.onChanged,
  );
}
