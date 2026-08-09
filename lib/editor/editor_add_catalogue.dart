import 'package:flutter/widgets.dart';

import '../mechanical/mechanical_feedback.dart';
import '../mechanical/mechanical_pager.dart';
import '../mechanical/prism_selector_bank.dart';
import '../model/component_instance.dart';
import '../model/component_type.dart';
import '../model/dashboard.dart';
import '../model/optical_profile.dart';
import '../model/placement.dart';
import '../model/vfd_module.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_render_assets.dart';
import '../vfd/vfd_widgets.dart';
import 'editor_live_preview.dart';

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

Size editorAddDropSize(EditorAddRequest request) =>
    request.componentType?.legacyVariantSpec.recommendedSize ??
    const Size(1, 0.5);

class EditorAddCatalogue extends StatefulWidget {
  const EditorAddCatalogue({
    super.key,
    required this.palette,
    required this.prismStyle,
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.onClose,
    required this.dashboard,
    this.safeInsets = EdgeInsets.zero,
    this.renderAssets,
    this.onDragEnded,
    this.onDragUpdated,
  });

  final VfdPalette palette;
  final PrismStyle prismStyle;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final VoidCallback onClose;
  final Dashboard dashboard;
  final EdgeInsets safeInsets;
  final VfdRenderAssets? renderAssets;
  final VoidCallback? onDragEnded;
  final void Function(EditorAddRequest request, Offset globalPosition)?
  onDragUpdated;

  @override
  State<EditorAddCatalogue> createState() => _EditorAddCatalogueState();
}

class _EditorAddCatalogueState extends State<EditorAddCatalogue> {
  EditorAddKind _kind = EditorAddKind.parts;
  EditorAddRequest? _selected;

  List<EditorAddRequest> get _items => switch (_kind) {
    EditorAddKind.parts => <EditorAddRequest>[
      for (final type in ComponentTypes.all) EditorAddRequest.component(type),
    ],
    EditorAddKind.modules => const <EditorAddRequest>[
      EditorAddRequest.module(),
    ],
  };

  EditorAddRequest get _currentSelection {
    final items = _items;
    final selected = _selected;
    if (selected != null &&
        items.any(
          (item) =>
              item.kind == selected.kind &&
              item.componentType?.id == selected.componentType?.id,
        )) {
      return selected;
    }
    return items.first;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(8, 8, 8, widget.safeInsets.bottom),
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
                onSelected: (value) => setState(() {
                  _kind = value;
                  _selected = null;
                }),
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
        SizedBox(
          height: 92,
          child: _CataloguePreview(
            request: _currentSelection,
            dashboard: widget.dashboard,
            renderAssets: widget.renderAssets,
            palette: widget.palette,
          ),
        ),
        const SizedBox(height: 6),
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
                  selected:
                      items[index].kind == _currentSelection.kind &&
                      items[index].componentType?.id ==
                          _currentSelection.componentType?.id,
                  onSelected: () => setState(() => _selected = items[index]),
                  onDragStarted: () => setState(() => _selected = items[index]),
                  onDragEnded: () {
                    widget.onDragEnded?.call();
                  },
                  onDragUpdated: (request, globalPosition) =>
                      widget.onDragUpdated?.call(request, globalPosition),
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
    required this.selected,
    required this.onSelected,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onDragUpdated,
  });

  final EditorAddRequest request;
  final VfdPalette palette;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final void Function(EditorAddRequest request, Offset globalPosition)
  onDragUpdated;

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
      selected: selected,
      hint: 'Tap to select or drag onto the design',
      child: Draggable<EditorAddRequest>(
        key: ValueKey('add-${request.componentType?.id ?? 'module'}'),
        data: request,
        rootOverlay: true,
        // DragTargetDetails.offset is the drag avatar position. The default
        // child anchor subtracts the source-row touch offset, while the ghost
        // follows DragUpdateDetails.globalPosition. Anchor at the pointer so
        // the committed design centre and visible ghost use the same point.
        dragAnchorStrategy: pointerDragAnchorStrategy,
        onDragStarted: () {
          onDragStarted();
          actuateMechanicalFeedback(
            soundEnabled: soundEnabled,
            hapticsEnabled: hapticsEnabled,
          );
        },
        onDragUpdate: (details) =>
            onDragUpdated(request, details.globalPosition),
        onDragEnd: (_) => onDragEnded(),
        feedback: const SizedBox.shrink(),
        childWhenDragging: Opacity(opacity: 0.24, child: face),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelected,
          child: _CatalogueFace(
            request: request,
            description: description,
            palette: palette,
            selected: selected,
          ),
        ),
      ),
    );
  }
}

class _CatalogueFace extends StatelessWidget {
  const _CatalogueFace({
    required this.request,
    required this.description,
    required this.palette,
    this.selected = false,
  });

  final EditorAddRequest request;
  final String description;
  final VfdPalette palette;
  final bool selected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF090D0C),
      border: Border.all(
        color: (selected ? palette.lit : palette.unlit).withValues(
          alpha: selected ? 0.9 : 0.42,
        ),
      ),
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

class _CataloguePreview extends StatelessWidget {
  const _CataloguePreview({
    required this.request,
    required this.dashboard,
    required this.renderAssets,
    required this.palette,
  });

  final EditorAddRequest request;
  final Dashboard dashboard;
  final VfdRenderAssets? renderAssets;
  final VfdPalette palette;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF020403),
      border: Border.all(color: palette.unlit.withValues(alpha: 0.5)),
    ),
    child: Stack(
      children: <Widget>[
        Positioned.fill(
          child: renderAssets == null
              ? CustomPaint(painter: _PreviewStandbyPainter(palette))
              : EditorLiveVfdPreview(
                  renderAssets: renderAssets!,
                  dashboard: _previewDashboard(),
                  orientation: DesignOrientation.landscape,
                ),
        ),
        Positioned(
          left: 7,
          top: 5,
          child: VfdLegend(
            'Preview · ${request.label}',
            palette: palette,
            lit: true,
            size: 8,
          ),
        ),
      ],
    ),
  );

  Dashboard _previewDashboard() {
    const orientation = DesignOrientation.landscape;
    const frame = FrameSpec(width: 2.6, height: 1);
    final type =
        request.componentType ??
        ComponentTypes.byId(ComponentTypes.speedDigits)!;
    final size = _previewSize(type);
    const previewModuleId = 'catalogue.preview.module';
    final moduleRequest = request.kind == EditorAddKind.modules;
    return Dashboard(
      id: 'catalogue.preview',
      name: request.label,
      primaryOrientation: orientation,
      frameSpecs: const <DesignOrientation, FrameSpec>{orientation: frame},
      settings: dashboard.settings,
      modules: moduleRequest
          ? <VfdModule>[
              VfdModule(id: kMainVfdModuleId, name: 'Main tube'),
              VfdModule(
                id: previewModuleId,
                name: 'Preview module',
                regions: const <DesignOrientation, Placement>{
                  orientation: Placement(
                    center: Offset.zero,
                    size: Size(1.9, 0.72),
                  ),
                },
              ),
            ]
          : dashboard.modules,
      components: <ComponentInstance>[
        ComponentInstance(
          id: 'catalogue.preview.part',
          typeId: type.id,
          moduleId: moduleRequest ? previewModuleId : kMainVfdModuleId,
          placements: <DesignOrientation, Placement>{
            orientation: Placement(center: Offset.zero, size: size),
          },
        ),
      ],
    );
  }

  Size _previewSize(ComponentTypeSpec type) {
    final recommended = type.legacyVariantSpec.recommendedSize;
    final scale = (1.7 / recommended.width)
        .clamp(0.0, 1.0)
        .clamp(0.0, (0.62 / recommended.height).clamp(0.0, 1.0));
    return Size(recommended.width * scale, recommended.height * scale);
  }
}

class _PreviewStandbyPainter extends CustomPainter {
  const _PreviewStandbyPainter(this.palette);

  final VfdPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = palette.unlit.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke;
    canvas.drawRect(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: size.width * 0.45,
        height: size.height * 0.36,
      ),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.74),
      Offset(size.width * 0.82, size.height * 0.74),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PreviewStandbyPainter oldDelegate) =>
      oldDelegate.palette != palette;
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
