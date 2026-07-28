import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../vfd/vfd_widgets.dart';

class VfdEditableField extends StatefulWidget {
  const VfdEditableField({
    super.key,
    required this.label,
    required this.value,
    required this.palette,
    required this.onChanged,
    this.onSubmitted,
    this.keyboardType = TextInputType.text,
  });

  final String label;
  final String value;
  final VfdPalette palette;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType keyboardType;

  @override
  State<VfdEditableField> createState() => _VfdEditableFieldState();
}

class _VfdEditableFieldState extends State<VfdEditableField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focusNode = FocusNode()..addListener(_focusChanged);

  @override
  void didUpdateWidget(covariant VfdEditableField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_focusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    textField: true,
    label: widget.label,
    value: _controller.text,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF020403),
        border: Border.all(
          color: widget.palette
              .state(_focusNode.hasFocus)
              .withValues(alpha: _focusNode.hasFocus ? 0.9 : 0.34),
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0xFF000000),
            blurRadius: 3,
            offset: Offset(0, 2),
            blurStyle: BlurStyle.inner,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            VfdLegend(widget.label, palette: widget.palette, size: 9),
            const SizedBox(height: 4),
            EditableText(
              controller: _controller,
              focusNode: _focusNode,
              style: TextStyle(
                color: widget.palette.lit,
                fontFamily: 'Barlow Condensed',
                fontSize: 14,
                letterSpacing: 1,
              ),
              cursorColor: widget.palette.lit,
              backgroundCursorColor: widget.palette.unlit,
              keyboardType: widget.keyboardType,
              inputFormatters: widget.keyboardType == TextInputType.number
                  ? <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[-+0-9.]')),
                    ]
                  : null,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
            ),
          ],
        ),
      ),
    ),
  );

  void _focusChanged() => setState(() {});
}
