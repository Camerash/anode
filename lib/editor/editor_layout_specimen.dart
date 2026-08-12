import 'package:flutter/widgets.dart';

import 'editor_chrome_skin.dart';

/// Selects authored layout content without presenting it as a physical command.
///
/// Skin owns visual material. This widget owns input, focus, and semantics.
class EditorLayoutSpecimen extends StatefulWidget {
  const EditorLayoutSpecimen({
    super.key,
    required this.skin,
    required this.aspect,
    required this.ratio,
    required this.semanticLabel,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    this.diagramKey,
  });

  final EditorChromeSkin skin;
  final double aspect;
  final String ratio;
  final String semanticLabel;
  final bool selected;
  final bool enabled;
  final VoidCallback? onSelected;
  final Key? diagramKey;

  @override
  State<EditorLayoutSpecimen> createState() => _EditorLayoutSpecimenState();
}

class _EditorLayoutSpecimenState extends State<EditorLayoutSpecimen> {
  bool _focused = false;
  bool _hovered = false;

  bool get _interactive => widget.enabled && widget.onSelected != null;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: _interactive,
    selected: widget.selected,
    label: widget.semanticLabel,
    child: FocusableActionDetector(
      enabled: _interactive,
      mouseCursor: _interactive
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelected?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _interactive ? widget.onSelected : null,
        child: widget.skin.layoutSpecimen(
          diagramKey: widget.diagramKey,
          aspect: widget.aspect,
          ratio: widget.ratio,
          selected: widget.selected,
          focused: _focused,
          hovered: _hovered,
          enabled: _interactive,
        ),
      ),
    ),
  );
}
