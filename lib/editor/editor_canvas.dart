import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../model/component_instance.dart';
import '../model/component_type.dart';
import '../model/dashboard.dart';
import '../model/placement.dart';
import '../model/vfd_module.dart';
import '../vfd/vfd_cluster.dart';
import '../vfd/vfd_render_assets.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_widgets.dart';
import 'placement_transform.dart';

enum CanvasInteractionMode { edit, navigate }

class EditorCanvas extends StatefulWidget {
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
    this.adaptiveAspect,
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
  final double? adaptiveAspect;

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends State<EditorCanvas> {
  final TransformationController _camera = TransformationController();
  CanvasInteractionMode _mode = CanvasInteractionMode.edit;
  double _cameraScale = 1;

  @override
  void didUpdateWidget(covariant EditorCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orientation != widget.orientation ||
        oldWidget.dashboard.id != widget.dashboard.id) {
      _fit();
    }
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aspect = widget.dashboard.frameAspect(
      widget.orientation,
      viewportAspect: widget.adaptiveAspect,
    );
    final palette = VfdPalette.of(
      widget.dashboard.settings.opticalProfile.phosphor,
    );
    return ColoredBox(
      color: const Color(0xFF161917),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = constraints.biggest;
          final sceneSize = Size(
            math.max(1, viewport.width),
            math.max(1, viewport.height),
          );
          final frame = _containRect(
            Rect.fromLTWH(
              24,
              24,
              math.max(1, sceneSize.width - 48),
              math.max(1, sceneSize.height - 48),
            ),
            aspect,
          );
          final frameInsets = EdgeInsets.fromLTRB(
            frame.left,
            frame.top,
            sceneSize.width - frame.right,
            sceneSize.height - frame.bottom,
          );
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (_mode == CanvasInteractionMode.navigate)
                InteractiveViewer(
                  key: const ValueKey('editor-camera'),
                  transformationController: _camera,
                  minScale: 1,
                  maxScale: 4,
                  boundaryMargin: const EdgeInsets.all(240),
                  constrained: false,
                  clipBehavior: Clip.hardEdge,
                  onInteractionUpdate: (_) => setState(() {
                    _cameraScale = _camera.value.getMaxScaleOnAxis();
                  }),
                  child: _buildScene(
                    sceneSize: sceneSize,
                    frame: frame,
                    frameInsets: frameInsets,
                    aspect: aspect,
                    palette: palette,
                  ),
                )
              else
                ClipRect(
                  key: const ValueKey('editor-camera'),
                  child: Transform(
                    transform: _camera.value,
                    alignment: Alignment.topLeft,
                    transformHitTests: true,
                    child: _buildScene(
                      sceneSize: sceneSize,
                      frame: frame,
                      frameInsets: frameInsets,
                      aspect: aspect,
                      palette: palette,
                    ),
                  ),
                ),
              Positioned(
                left: 8,
                bottom: 8,
                child: Row(
                  children: <Widget>[
                    PrismButton(
                      key: const ValueKey('canvas-mode'),
                      label: _mode == CanvasInteractionMode.edit
                          ? 'Edit'
                          : 'Nav',
                      palette: palette,
                      lit: _mode == CanvasInteractionMode.navigate,
                      role: PrismRole.compact,
                      style: widget.dashboard.settings.prismStyle,
                      onPressed: () => setState(() {
                        _mode = _mode == CanvasInteractionMode.edit
                            ? CanvasInteractionMode.navigate
                            : CanvasInteractionMode.edit;
                      }),
                    ),
                    const SizedBox(width: 5),
                    PrismButton(
                      key: const ValueKey('canvas-fit'),
                      label: 'Fit',
                      palette: palette,
                      role: PrismRole.compact,
                      style: widget.dashboard.settings.prismStyle,
                      onPressed: _fit,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScene({
    required Size sceneSize,
    required Rect frame,
    required EdgeInsets frameInsets,
    required double aspect,
    required VfdPalette palette,
  }) => SizedBox.fromSize(
    size: sceneSize,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _mode == CanvasInteractionMode.edit
          ? () => widget.onSelect(null)
          : null,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: <Widget>[
          if (widget.renderAssets != null)
            _LiveVfdPreview(
              renderAssets: widget.renderAssets!,
              dashboard: widget.dashboard,
              orientation: widget.orientation,
              safeInsets: frameInsets,
            ),
          IgnorePointer(
            child: CustomPaint(
              painter: _OutsideFramePainter(frame: frame, palette: palette),
            ),
          ),
          IgnorePointer(
            ignoring: _mode == CanvasInteractionMode.navigate,
            child: _ComponentStack(
              dashboard: widget.dashboard,
              orientation: widget.orientation,
              selectedId: widget.selectedId,
              livePreview: widget.renderAssets != null,
              frame: frame,
              aspect: aspect,
              cameraScale: _cameraScale,
              onSelect: widget.onSelect,
              onPlacementChanged: widget.onPlacementChanged,
            ),
          ),
          if (widget.selectedModuleId != null &&
              widget.onModulePlacementChanged != null)
            IgnorePointer(
              ignoring: _mode == CanvasInteractionMode.navigate,
              child: _ModuleOverlay(
                dashboard: widget.dashboard,
                orientation: widget.orientation,
                selectedModuleId: widget.selectedModuleId!,
                frame: frame,
                aspect: aspect,
                cameraScale: _cameraScale,
                onPlacementChanged: widget.onModulePlacementChanged!,
              ),
            ),
          IgnorePointer(
            child: CustomPaint(
              painter: _AuthoredFramePainter(palette: palette, frame: frame),
            ),
          ),
          Positioned.fromRect(
            rect: frame,
            child: const IgnorePointer(
              child: SizedBox(key: ValueKey('editor-canvas')),
            ),
          ),
          Positioned(
            left: frame.left + 7,
            top: frame.top + 7,
            child: IgnorePointer(
              child: VfdLegend(
                '${widget.orientation.name} · ${aspect.toStringAsFixed(3)}:1',
                palette: palette,
                lit: true,
                size: 9,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _fit() {
    _camera.value = Matrix4.identity();
    if (mounted) {
      setState(() {
        _cameraScale = 1;
        _mode = CanvasInteractionMode.edit;
      });
    }
  }

  static Rect _containRect(Rect bounds, double aspect) {
    if (bounds.width / bounds.height > aspect) {
      final width = bounds.height * aspect;
      return Rect.fromLTWH(
        bounds.left + (bounds.width - width) / 2,
        bounds.top,
        width,
        bounds.height,
      );
    }
    final height = bounds.width / aspect;
    return Rect.fromLTWH(
      bounds.left,
      bounds.top + (bounds.height - height) / 2,
      bounds.width,
      height,
    );
  }
}

class _ComponentStack extends StatelessWidget {
  const _ComponentStack({
    required this.dashboard,
    required this.orientation,
    required this.selectedId,
    required this.livePreview,
    required this.frame,
    required this.aspect,
    required this.cameraScale,
    required this.onSelect,
    required this.onPlacementChanged,
  });

  final Dashboard dashboard;
  final DesignOrientation orientation;
  final String? selectedId;
  final bool livePreview;
  final Rect frame;
  final double aspect;
  final double cameraScale;
  final ValueChanged<String?> onSelect;
  final void Function(String componentId, Placement placement)
  onPlacementChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = frame.height;
      final visible = dashboard.componentsIn(orientation);
      final ordered = <ComponentInstance>[
        ...visible.where((component) => component.id != selectedId),
        ...visible.where((component) => component.id == selectedId),
      ];
      return Stack(
        fit: StackFit.expand,
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
    final size = placement.resolveSizeForAspect(
      aspect,
      type,
      variant: component.effectiveVariant,
    );
    return Positioned(
      key: ValueKey('canvas-${component.id}'),
      left: frame.left + (aspect / 2 + center.dx - size.width / 2) * scale,
      top: frame.top + (0.5 - center.dy - size.height / 2) * scale,
      width: size.width * scale,
      height: size.height * scale,
      child: _ComponentBox(
        label:
            ComponentTypes.byId(component.typeId)?.displayName ??
            component.typeId,
        placement: placement,
        defaultSize: size,
        frameAspect: aspect,
        scale: scale * cameraScale,
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
    required this.frameAspect,
    required this.scale,
    required this.selected,
    required this.livePreview,
    required this.onSelect,
    required this.onChanged,
  });

  final String label;
  final Placement placement;
  final Size defaultSize;
  final double frameAspect;
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
  late Size _initialResolvedSize = widget.defaultSize;
  late double _interactionScale = widget.scale;

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
    _initialResolvedSize = widget.placement.size ?? widget.defaultSize;
    _interactionScale = widget.scale;
    if (select) widget.onSelect();
  }

  void _move(DragUpdateDetails details) {
    final pointerDelta = _pointerDelta(details);
    final delta = Offset(
      pointerDelta.dx / _interactionScale,
      -pointerDelta.dy / _interactionScale,
    );
    widget.onChanged(
      _initialPlacement.copyWith(offset: _initialPlacement.offset + delta),
    );
  }

  void _resize({double widthDelta = 0, double heightDelta = 0}) {
    widget.onChanged(
      resizePlacementFromEdges(
        placement: _initialPlacement,
        resolvedSize: _initialResolvedSize,
        frameAspect: widget.frameAspect,
        widthDelta: widthDelta * widget.scale / _interactionScale,
        heightDelta: heightDelta * widget.scale / _interactionScale,
      ),
    );
  }

  Offset _pointerDelta(DragUpdateDetails details) =>
      details.globalPosition - (_pointerOrigin ?? details.globalPosition);
}

class _AuthoredFramePainter extends CustomPainter {
  const _AuthoredFramePainter({required this.palette, required this.frame});

  final VfdPalette palette;
  final Rect frame;

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
    canvas.drawRect(frame, bright);
    canvas.drawRect(frame.deflate(4), dim);
    const mark = 13.0;
    const gap = 4.0;
    final segments = <(Offset, Offset)>[
      (
        Offset(frame.left - gap - mark, frame.top - gap),
        Offset(frame.left - gap, frame.top - gap),
      ),
      (
        Offset(frame.left - gap, frame.top - gap - mark),
        Offset(frame.left - gap, frame.top - gap),
      ),
      (
        Offset(frame.right + gap, frame.top - gap),
        Offset(frame.right + gap + mark, frame.top - gap),
      ),
      (
        Offset(frame.right + gap, frame.top - gap - mark),
        Offset(frame.right + gap, frame.top - gap),
      ),
      (
        Offset(frame.left - gap - mark, frame.bottom + gap),
        Offset(frame.left - gap, frame.bottom + gap),
      ),
      (
        Offset(frame.left - gap, frame.bottom + gap),
        Offset(frame.left - gap, frame.bottom + gap + mark),
      ),
      (
        Offset(frame.right + gap, frame.bottom + gap),
        Offset(frame.right + gap + mark, frame.bottom + gap),
      ),
      (
        Offset(frame.right + gap, frame.bottom + gap),
        Offset(frame.right + gap, frame.bottom + gap + mark),
      ),
    ];
    for (final segment in segments) {
      canvas.drawLine(segment.$1, segment.$2, bright);
    }
  }

  @override
  bool shouldRepaint(covariant _AuthoredFramePainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.frame != frame;
}

class _OutsideFramePainter extends CustomPainter {
  const _OutsideFramePainter({required this.frame, required this.palette});

  final Rect frame;
  final VfdPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final matte = Paint()..color = const Color(0xCC111512);
    canvas
      ..drawRect(Rect.fromLTRB(0, 0, size.width, frame.top), matte)
      ..drawRect(Rect.fromLTRB(0, frame.bottom, size.width, size.height), matte)
      ..drawRect(Rect.fromLTRB(0, frame.top, frame.left, frame.bottom), matte)
      ..drawRect(
        Rect.fromLTRB(frame.right, frame.top, size.width, frame.bottom),
        matte,
      );
  }

  @override
  bool shouldRepaint(covariant _OutsideFramePainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.palette != palette;
}

class _ModuleOverlay extends StatelessWidget {
  const _ModuleOverlay({
    required this.dashboard,
    required this.orientation,
    required this.selectedModuleId,
    required this.frame,
    required this.aspect,
    required this.cameraScale,
    required this.onPlacementChanged,
  });

  final Dashboard dashboard;
  final DesignOrientation orientation;
  final String selectedModuleId;
  final Rect frame;
  final double aspect;
  final double cameraScale;
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
        final scale = frame.height;
        final center = placement.resolve(aspect);
        final size = placement.resolveSizeForAspect(aspect, null);
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              key: ValueKey('module-${module.id}'),
              left:
                  frame.left +
                  (aspect / 2 + center.dx - size.width / 2) * scale,
              top: frame.top + (0.5 - center.dy - size.height / 2) * scale,
              width: size.width * scale,
              height: size.height * scale,
              child: _ComponentBox(
                label: module.name,
                placement: placement,
                defaultSize: size,
                frameAspect: aspect,
                scale: scale * cameraScale,
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
    required this.safeInsets,
  });

  final VfdRenderAssets renderAssets;
  final Dashboard dashboard;
  final DesignOrientation orientation;
  final EdgeInsets safeInsets;

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
    safeInsets: widget.safeInsets,
  );
}
