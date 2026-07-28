import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../model/component_instance.dart';
import '../model/component_type.dart';
import '../model/dashboard.dart';
import '../model/placement.dart';
import '../model/vfd_module.dart';
import '../vfd/vfd_cluster.dart';
import '../vfd/vfd_render_assets.dart';
import '../vfd/vfd_widgets.dart';
import 'placement_transform.dart';

class EditorCanvas extends StatelessWidget {
  const EditorCanvas({
    super.key,
    required this.dashboard,
    required this.orientation,
    required this.selectedId,
    required this.onSelect,
    required this.onPlacementChanged,
    this.selectedModuleId,
    this.onModulePlacementChanged,
    this.renderAssets,
  });

  final Dashboard dashboard;
  final DesignOrientation orientation;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final void Function(String componentId, Placement placement)
  onPlacementChanged;
  final String? selectedModuleId;
  final void Function(String moduleId, Placement placement)?
  onModulePlacementChanged;
  final VfdRenderAssets? renderAssets;

  @override
  Widget build(BuildContext context) {
    final aspect = dashboard.frameAspect(orientation);
    final palette = VfdPalette.of(dashboard.settings.opticalProfile.phosphor);
    return ColoredBox(
      color: const Color(0xFF161917),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: AspectRatio(
            key: const ValueKey('editor-canvas'),
            aspectRatio: aspect,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: <Widget>[
                DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0xFF000000)),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(null),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        if (renderAssets != null)
                          _LiveVfdPreview(
                            renderAssets: renderAssets!,
                            dashboard: dashboard,
                            orientation: orientation,
                          ),
                        _ComponentStack(
                          dashboard: dashboard,
                          orientation: orientation,
                          selectedId: selectedId,
                          livePreview: renderAssets != null,
                          onSelect: onSelect,
                          onPlacementChanged: onPlacementChanged,
                        ),
                        if (selectedModuleId != null &&
                            onModulePlacementChanged != null)
                          _ModuleOverlay(
                            dashboard: dashboard,
                            orientation: orientation,
                            selectedModuleId: selectedModuleId!,
                            onPlacementChanged: onModulePlacementChanged!,
                          ),
                      ],
                    ),
                  ),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _AuthoredFramePainter(palette: palette),
                  ),
                ),
                Positioned(
                  left: 7,
                  top: 7,
                  child: IgnorePointer(
                    child: VfdLegend(
                      '${orientation.name} · ${aspect.toStringAsFixed(3)}:1',
                      palette: palette,
                      lit: true,
                      size: 9,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComponentStack extends StatelessWidget {
  const _ComponentStack({
    required this.dashboard,
    required this.orientation,
    required this.selectedId,
    required this.livePreview,
    required this.onSelect,
    required this.onPlacementChanged,
  });

  final Dashboard dashboard;
  final DesignOrientation orientation;
  final String? selectedId;
  final bool livePreview;
  final ValueChanged<String?> onSelect;
  final void Function(String componentId, Placement placement)
  onPlacementChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = constraints.maxHeight;
      final aspect = dashboard.frameAspect(orientation);
      final visible = dashboard.componentsIn(orientation);
      final ordered = <ComponentInstance>[
        ...visible.where((component) => component.id != selectedId),
        ...visible.where((component) => component.id == selectedId),
      ];
      return Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (final component in ordered)
            _positionedComponent(component, aspect, scale),
        ],
      );
    },
  );

  Widget _positionedComponent(
    ComponentInstance component,
    double aspect,
    double scale,
  ) {
    final type = ComponentTypes.byId(component.typeId);
    final placement = component.placements[orientation]!;
    final center = placement.resolve(aspect);
    final size = placement.resolveSize(
      type,
      variant: component.effectiveVariant,
    );
    return Positioned(
      key: ValueKey('canvas-${component.id}'),
      left: (aspect / 2 + center.dx - size.width / 2) * scale,
      top: (0.5 - center.dy - size.height / 2) * scale,
      width: size.width * scale,
      height: size.height * scale,
      child: _ComponentBox(
        label:
            ComponentTypes.byId(component.typeId)?.displayName ??
            component.typeId,
        placement: placement,
        defaultSize: size,
        scale: scale,
        selected: component.id == selectedId,
        livePreview: livePreview,
        onSelect: () => onSelect(component.id),
        onChanged: (value) => onPlacementChanged(component.id, value),
      ),
    );
  }
}

class _ComponentBox extends StatefulWidget {
  const _ComponentBox({
    required this.label,
    required this.placement,
    required this.defaultSize,
    required this.scale,
    required this.selected,
    required this.livePreview,
    required this.onSelect,
    required this.onChanged,
  });

  final String label;
  final Placement placement;
  final Size defaultSize;
  final double scale;
  final bool selected;
  final bool livePreview;
  final VoidCallback onSelect;
  final ValueChanged<Placement> onChanged;

  @override
  State<_ComponentBox> createState() => _ComponentBoxState();
}

class _ComponentBoxState extends State<_ComponentBox> {
  static const double _handleExtent = 44;

  Offset? _pointerOrigin;
  late Placement _initialPlacement = widget.placement;

  @override
  Widget build(BuildContext context) {
    const selectedColor = Color(0xFF5DFFC2);
    const idleColor = Color(0xFF7C8681);
    final color = widget.selected ? selectedColor : idleColor;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(child: _body(color)),
        if (widget.selected) ..._resizeHandles(color),
      ],
    );
  }

  Widget _body(Color color) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    dragStartBehavior: DragStartBehavior.down,
    onTap: widget.onSelect,
    onPanStart: (details) => _startInteraction(details, select: true),
    onPanUpdate: _move,
    onPanEnd: (_) => _pointerOrigin = null,
    onPanCancel: () => _pointerOrigin = null,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: widget.livePreview ? (widget.selected ? 0.06 : 0.01) : 0.18,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: widget.livePreview && !widget.selected ? 0.22 : 1,
          ),
          width: widget.selected ? 2 : 1,
        ),
      ),
      child: Center(
        child: widget.livePreview && !widget.selected
            ? null
            : Text(
                widget.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 11),
              ),
      ),
    ),
  );

  List<Widget> _resizeHandles(Color color) => <Widget>[
    _handle(
      key: const ValueKey('resize-width'),
      color: color,
      right: 0,
      top: 0,
      bottom: 0,
      cursor: SystemMouseCursors.resizeLeftRight,
      onPan: (delta) => _resize(widthDelta: delta.dx / widget.scale),
    ),
    _handle(
      key: const ValueKey('resize-height'),
      color: color,
      left: 0,
      right: 0,
      bottom: 0,
      cursor: SystemMouseCursors.resizeUpDown,
      onPan: (delta) => _resize(heightDelta: delta.dy / widget.scale),
    ),
    _handle(
      key: const ValueKey('resize-both'),
      color: color,
      right: 0,
      bottom: 0,
      cursor: SystemMouseCursors.resizeDownRight,
      onPan: (delta) => _resize(
        widthDelta: delta.dx / widget.scale,
        heightDelta: delta.dy / widget.scale,
      ),
    ),
  ];

  Widget _handle({
    required Key key,
    required Color color,
    required MouseCursor cursor,
    required ValueChanged<Offset> onPan,
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) => Positioned(
    key: key,
    left: left,
    top: top,
    right: right,
    bottom: bottom,
    width: left == null || right == null ? _handleExtent : null,
    height: top == null || bottom == null ? _handleExtent : null,
    child: MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: _startInteraction,
        onPanUpdate: (details) => onPan(_pointerDelta(details)),
        onPanEnd: (_) => _pointerOrigin = null,
        onPanCancel: () => _pointerOrigin = null,
        child: Center(child: Container(width: 10, height: 10, color: color)),
      ),
    ),
  );

  void _startInteraction(DragStartDetails details, {bool select = false}) {
    _pointerOrigin = details.globalPosition;
    _initialPlacement = widget.placement;
    if (select) widget.onSelect();
  }

  void _move(DragUpdateDetails details) {
    final pointerDelta = _pointerDelta(details);
    final delta = Offset(
      pointerDelta.dx / widget.scale,
      -pointerDelta.dy / widget.scale,
    );
    widget.onChanged(
      _initialPlacement.copyWith(offset: _initialPlacement.offset + delta),
    );
  }

  void _resize({double widthDelta = 0, double heightDelta = 0}) {
    final size = _initialPlacement.size ?? widget.defaultSize;
    widget.onChanged(
      resizePlacementFromEdges(
        placement: _initialPlacement,
        resolvedSize: size,
        frameAspect: 1,
        widthDelta: widthDelta,
        heightDelta: heightDelta,
      ),
    );
  }

  Offset _pointerDelta(DragUpdateDetails details) =>
      details.globalPosition - (_pointerOrigin ?? details.globalPosition);
}

class _AuthoredFramePainter extends CustomPainter {
  const _AuthoredFramePainter({required this.palette});

  final VfdPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final bright = Paint()
      ..color = palette.lit.withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final dim = Paint()
      ..color = palette.unlit.withValues(alpha: 0.58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Offset.zero & size, bright);
    canvas.drawRect(Rect.fromLTWH(4, 4, size.width - 8, size.height - 8), dim);
    const mark = 13.0;
    const gap = 4.0;
    final segments = <(Offset, Offset)>[
      (const Offset(-gap - mark, -gap), const Offset(-gap, -gap)),
      (const Offset(-gap, -gap - mark), const Offset(-gap, -gap)),
      (Offset(size.width + gap, -gap), Offset(size.width + gap + mark, -gap)),
      (Offset(size.width + gap, -gap - mark), Offset(size.width + gap, -gap)),
      (Offset(-gap - mark, size.height + gap), Offset(-gap, size.height + gap)),
      (Offset(-gap, size.height + gap), Offset(-gap, size.height + gap + mark)),
      (
        Offset(size.width + gap, size.height + gap),
        Offset(size.width + gap + mark, size.height + gap),
      ),
      (
        Offset(size.width + gap, size.height + gap),
        Offset(size.width + gap, size.height + gap + mark),
      ),
    ];
    for (final segment in segments) {
      canvas.drawLine(segment.$1, segment.$2, bright);
    }
  }

  @override
  bool shouldRepaint(covariant _AuthoredFramePainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class _ModuleOverlay extends StatelessWidget {
  const _ModuleOverlay({
    required this.dashboard,
    required this.orientation,
    required this.selectedModuleId,
    required this.onPlacementChanged,
  });

  final Dashboard dashboard;
  final DesignOrientation orientation;
  final String selectedModuleId;
  final void Function(String moduleId, Placement placement) onPlacementChanged;

  @override
  Widget build(BuildContext context) {
    if (selectedModuleId == kMainVfdModuleId) return const SizedBox.shrink();
    VfdModule? selected;
    for (final module in dashboard.modules) {
      if (module.id == selectedModuleId) selected = module;
    }
    final placement = selected?.regionIn(orientation);
    if (selected == null || placement == null) return const SizedBox.shrink();
    final module = selected;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxHeight;
        final aspect = dashboard.frameAspect(orientation);
        final center = placement.resolve(aspect);
        final size = placement.size ?? Size(aspect, 1);
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              key: ValueKey('module-${module.id}'),
              left: (aspect / 2 + center.dx - size.width / 2) * scale,
              top: (0.5 - center.dy - size.height / 2) * scale,
              width: size.width * scale,
              height: size.height * scale,
              child: _ComponentBox(
                label: module.name,
                placement: placement,
                defaultSize: size,
                scale: scale,
                selected: true,
                livePreview: true,
                onSelect: () {},
                onChanged: (value) => onPlacementChanged(module.id, value),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LiveVfdPreview extends StatefulWidget {
  const _LiveVfdPreview({
    required this.renderAssets,
    required this.dashboard,
    required this.orientation,
  });

  final VfdRenderAssets renderAssets;
  final Dashboard dashboard;
  final DesignOrientation orientation;

  @override
  State<_LiveVfdPreview> createState() => _LiveVfdPreviewState();
}

class _LiveVfdPreviewState extends State<_LiveVfdPreview>
    with SingleTickerProviderStateMixin {
  late final VfdController _controller = VfdController(
    vsync: this,
    design: widget.dashboard,
    orientation: widget.orientation,
  )..speedKph = 95;

  @override
  void didUpdateWidget(covariant _LiveVfdPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller
      ..design = widget.dashboard
      ..orientation = widget.orientation;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VfdCluster(
    renderAssets: widget.renderAssets,
    controller: _controller,
    safeInsets: EdgeInsets.zero,
  );
}
