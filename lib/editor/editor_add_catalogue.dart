import 'package:flutter/widgets.dart';

import '../mechanical/mechanical_feedback.dart';
import '../mechanical/mechanical_pager.dart';
import '../mechanical/prism_selector_bank.dart';
import '../model/component_type.dart';
import '../model/optical_profile.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_widgets.dart';

enum EditorAddKind { parts, modules }

@immutable
class EditorAddRequest {
  const EditorAddRequest.component(this.componentType)
    : kind = EditorAddKind.parts;

  const EditorAddRequest.module()
    : kind = EditorAddKind.modules,
      componentType = null;

  final EditorAddKind kind;
  final ComponentTypeSpec? componentType;

  String get label => componentType?.displayName ?? 'VFD module';
}

class EditorAddCatalogue extends StatefulWidget {
  const EditorAddCatalogue({
    super.key,
    required this.palette,
    required this.prismStyle,
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.onClose,
  });

  final VfdPalette palette;
  final PrismStyle prismStyle;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final VoidCallback onClose;

  @override
  State<EditorAddCatalogue> createState() => _EditorAddCatalogueState();
}

class _EditorAddCatalogueState extends State<EditorAddCatalogue> {
  EditorAddKind _kind = EditorAddKind.parts;

  List<EditorAddRequest> get _items => switch (_kind) {
    EditorAddKind.parts => <EditorAddRequest>[
      for (final type in ComponentTypes.all) EditorAddRequest.component(type),
    ],
    EditorAddKind.modules => const <EditorAddRequest>[
      EditorAddRequest.module(),
    ],
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: PrismSelectorBank<EditorAddKind>(
                choices: const <PrismSelectorChoice<EditorAddKind>>[
                  PrismSelectorChoice<EditorAddKind>(
                    value: EditorAddKind.parts,
                    label: 'Parts',
                  ),
                  PrismSelectorChoice<EditorAddKind>(
                    value: EditorAddKind.modules,
                    label: 'Modules',
                  ),
                ],
                selected: _kind,
                palette: widget.palette,
                prismStyle: widget.prismStyle,
                rows: 1,
                role: PrismRole.compact,
                soundEnabled: widget.soundEnabled,
                hapticsEnabled: widget.hapticsEnabled,
                semanticLabel: 'Add catalogue type',
                onSelected: (value) => setState(() => _kind = value),
              ),
            ),
            const SizedBox(width: 6),
            PrismButton(
              key: const ValueKey('add-catalogue-close'),
              label: 'Close',
              palette: widget.palette,
              role: PrismRole.compact,
              style: widget.prismStyle,
              soundEnabled: widget.soundEnabled,
              hapticsEnabled: widget.hapticsEnabled,
              onPressed: widget.onClose,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rowsPerPage = (constraints.maxHeight / 62).floor().clamp(
                1,
                4,
              );
              final pages = _pages(_items, rowsPerPage);
              return MechanicalPager(
                key: ValueKey('add-catalogue-${_kind.name}'),
                pages: pages,
                palette: widget.palette,
                prismStyle: widget.prismStyle,
                soundEnabled: widget.soundEnabled,
                hapticsEnabled: widget.hapticsEnabled,
                semanticLabel: '${_kind.name} catalogue',
              );
            },
          ),
        ),
      ],
    ),
  );

  List<Widget> _pages(List<EditorAddRequest> items, int rowsPerPage) {
    final pages = <Widget>[];
    for (var start = 0; start < items.length; start += rowsPerPage) {
      final end = (start + rowsPerPage).clamp(0, items.length);
      pages.add(
        Column(
          children: <Widget>[
            for (var index = start; index < end; index++) ...<Widget>[
              Expanded(
                child: _CatalogueRow(
                  request: items[index],
                  palette: widget.palette,
                  soundEnabled: widget.soundEnabled,
                  hapticsEnabled: widget.hapticsEnabled,
                ),
              ),
              if (index + 1 < end) const SizedBox(height: 4),
            ],
          ],
        ),
      );
    }
    return pages;
  }
}

class _CatalogueRow extends StatelessWidget {
  const _CatalogueRow({
    required this.request,
    required this.palette,
    required this.soundEnabled,
    required this.hapticsEnabled,
  });

  final EditorAddRequest request;
  final VfdPalette palette;
  final bool soundEnabled;
  final bool hapticsEnabled;

  @override
  Widget build(BuildContext context) {
    final description =
        request.componentType?.description ?? 'Independent VFD tube region.';
    final face = _CatalogueFace(
      request: request,
      description: description,
      palette: palette,
    );
    return Semantics(
      label: request.label,
      hint: 'Long press, then drag onto the design',
      child: LongPressDraggable<EditorAddRequest>(
        key: ValueKey('add-${request.componentType?.id ?? 'module'}'),
        data: request,
        hapticFeedbackOnStart: false,
        onDragStarted: () => actuateMechanicalFeedback(
          soundEnabled: soundEnabled,
          hapticsEnabled: hapticsEnabled,
        ),
        feedback: SizedBox(width: 240, height: 58, child: face),
        childWhenDragging: Opacity(opacity: 0.32, child: face),
        child: face,
      ),
    );
  }
}

class _CatalogueFace extends StatelessWidget {
  const _CatalogueFace({
    required this.request,
    required this.description,
    required this.palette,
  });

  final EditorAddRequest request;
  final String description;
  final VfdPalette palette;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF090D0C),
      border: Border.all(color: palette.unlit.withValues(alpha: 0.42)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: <Widget>[
          CustomPaint(
            size: const Size(30, 30),
            painter: _DragGripPainter(palette),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                VfdLegend(request.label, palette: palette, lit: true, size: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: VfdLegend(description, palette: palette, size: 8),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DragGripPainter extends CustomPainter {
  const _DragGripPainter(this.palette);

  final VfdPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = palette.unlit.withValues(alpha: 0.65)
      ..strokeWidth = 1;
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 2; column++) {
        canvas.drawCircle(Offset(9 + column * 10, 8 + row * 7), 1.4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DragGripPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
