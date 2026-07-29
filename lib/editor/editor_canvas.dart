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

class EditorCanvas extends StatefulWidget {
  const EditorCanvas({
    super.key,
    required this.dashboard,
    required this.orientation,
    required this.selectedId,
    required this.onSelect,
    required this.onPlacementChanged,
    required this.deviceSafeSize,
    this.selectedModuleId,
    this.onModulePlacementChanged,
    this.renderAssets,
    this.previewOrientation,
    this.editable = true,
    this.frameInset = const EdgeInsets.all(24),
    this.fullScreen = false,
    this.onToggleFullScreen,
    this.snapEnabled = true,
    this.onToggleSnap,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  });

  final Dashboard dashboard;
  final DesignOrientation orientation;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final void Function(String componentId, Placement placement)
  onPlacementChanged;

  /// The device's own safe rect, measured above the editor's `SafeArea`. The
  /// read-only preview of an unauthored orientation shows the envelope this
  /// would produce, which is the same one `CREATE` bakes.
  final Size deviceSafeSize;
  final String? selectedModuleId;
  final void Function(String moduleId, Placement placement)?
  onModulePlacementChanged;
  final VfdRenderAssets? renderAssets;
  final DesignOrientation? previewOrientation;
  final bool editable;
  final EdgeInsets frameInset;
  final bool fullScreen;
  final VoidCallback? onToggleFullScreen;
  final bool snapEnabled;
  final VoidCallback? onToggleSnap;
  final bool soundEnabled;
  final bool hapticsEnabled;

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

/// What a pointer landed on, resolved once at pointer-down against screen-space
/// rects rather than left to the gesture arena.
enum _GrabKind { none, body, resizeWidth, resizeHeight, resizeBoth }

class _Grab {
  const _Grab(this.item, this.kind);
  final _CanvasItem? item;
  final _GrabKind kind;

  static const _Grab none = _Grab(null, _GrabKind.none);
  bool get isResize =>
      kind == _GrabKind.resizeWidth ||
      kind == _GrabKind.resizeHeight ||
      kind == _GrabKind.resizeBoth;
}

class _EditorCanvasState extends State<EditorCanvas> {
  static const double _handleExtent = 44;
  static const double _minCameraScale = 1;
  static const double _maxCameraScale = 4;

  double _cameraScale = 1;
  Offset _cameraOrigin = Offset.zero;

  /// Live pointers, so a second finger can promote an element drag to a camera
  /// gesture mid-stroke.
  final Map<int, Offset> _pointers = <int, Offset>{};

  List<_CanvasItem> _items = const <_CanvasItem>[];
  double _designScale = 1;
  Size _layoutExtent = const Size(1, 1);

  _Grab _grab = _Grab.none;
  Offset _grabOrigin = Offset.zero;
  bool _dragging = false;
  bool _cameraGesture = false;
  Placement? _initialPlacement;
  double _initialDesignScale = 1;

  double _cameraScaleAtStart = 1;
  Offset _cameraOriginAtStart = Offset.zero;
  Offset _gestureAnchor = Offset.zero;
  double _gestureSpread = 1;

  @override
  void didUpdateWidget(covariant EditorCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orientation != widget.orientation ||
        oldWidget.previewOrientation != widget.previewOrientation ||
        oldWidget.dashboard.id != widget.dashboard.id) {
      _fit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = VfdPalette.of(
      widget.dashboard.settings.opticalProfile.phosphor,
    );
    return ColoredBox(
      color: const Color(0xFF161917),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sceneSize = Size(
            math.max(1, constraints.maxWidth),
            math.max(1, constraints.maxHeight),
          );
          final layoutExtent = widget.dashboard.frameExtent(widget.orientation);

          // An unauthored orientation is previewed as the device envelope it
          // would be given, with the inherited layout contained inside it —
          // which is what the runtime actually shows, and what CREATE bakes.
          final boundaryExtent = widget.editable
              ? layoutExtent
              : viewportFrameExtent(
                  widget.previewOrientation ?? widget.orientation,
                  widget.deviceSafeSize,
                  widget.dashboard.frameSpec(widget.orientation),
                );

          final bounds = widget.frameInset.deflateRect(Offset.zero & sceneSize);
          final boundary = _containRect(
            Rect.fromLTWH(
              bounds.left,
              bounds.top,
              math.max(1, bounds.width),
              math.max(1, bounds.height),
            ),
            boundaryExtent,
          );
          final content = widget.editable
              ? boundary
              : _containRect(boundary, layoutExtent);

          _layoutExtent = layoutExtent;
          _designScale = content.height / layoutExtent.height;
          _items = _buildItems(content);

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ClipRect(
                key: const ValueKey('editor-camera'),
                child: Transform(
                  transform: _cameraTransform(),
                  alignment: Alignment.topLeft,
                  child: _buildScene(
                    sceneSize: sceneSize,
                    boundary: boundary,
                    content: content,
                    palette: palette,
                  ),
                ),
              ),
              // Selection chrome lives in screen space so handles stay a
              // constant 44px at any zoom, and so the hit test never has to
              // undo the camera transform.
              _overlay(),
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: (event) => _endPointer(event.pointer, tap: true),
                onPointerCancel: (event) =>
                    _endPointer(event.pointer, tap: false),
                onPointerSignal: _onPointerSignal,
              ),
              _controls(palette),
            ],
          );
        },
      ),
    );
  }

  Matrix4 _cameraTransform() => Matrix4.identity()
    ..translateByDouble(_cameraOrigin.dx, _cameraOrigin.dy, 0, 1)
    ..scaleByDouble(_cameraScale, _cameraScale, 1, 1);

  Widget _buildScene({
    required Size sceneSize,
    required Rect boundary,
    required Rect content,
    required VfdPalette palette,
  }) => SizedBox.fromSize(
    size: sceneSize,
    child: Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: <Widget>[
        if (widget.renderAssets != null)
          _LiveVfdPreview(
            renderAssets: widget.renderAssets!,
            dashboard: widget.dashboard,
            orientation: widget.orientation,
            // The boundary, not the content rect: the shader performs the same
            // contain fit the runtime does, so the pixels inside the border are
            // exactly the runtime render.
            safeInsets: EdgeInsets.fromLTRB(
              boundary.left,
              boundary.top,
              sceneSize.width - boundary.right,
              sceneSize.height - boundary.bottom,
            ),
          ),
        CustomPaint(
          painter: _OutsideFramePainter(
            frame: boundary,
            palette: palette,
            // Dimming, not opacity: an Opacity layer over the shader forces a
            // saveLayer above the render pass.
            insideScrim: widget.editable ? null : const Color(0x99111512),
          ),
        ),
        CustomPaint(
          painter: _AuthoredFramePainter(
            palette: palette,
            frame: boundary,
            innerFrame: widget.editable ? null : content,
          ),
        ),
        Positioned.fromRect(
          rect: boundary,
          child: const SizedBox(key: ValueKey('editor-canvas')),
        ),
        Positioned(
          left: boundary.left + 7,
          top: boundary.top + 7,
          child: VfdLegend(_frameLabel(), palette: palette, lit: true, size: 9),
        ),
      ],
    ),
  );

  Widget _overlay() => Stack(
    fit: StackFit.expand,
    clipBehavior: Clip.none,
    children: <Widget>[
      for (final item in _items)
        Positioned.fromRect(
          key: ValueKey('${item.isModule ? 'module' : 'canvas'}-${item.id}'),
          rect: _screenRect(item.sceneRect),
          child: Semantics(
            button: true,
            selected: item.selected,
            label: item.label,
            onTap: item.isModule ? null : () => widget.onSelect(item.id),
            child: _SelectionBox(
              label: item.label,
              selected: item.selected,
              livePreview: widget.renderAssets != null,
              showHandles: item.selected && widget.editable,
              dimmed: !widget.editable,
              handleExtent: _handleExtent,
            ),
          ),
        ),
    ],
  );

  Widget _controls(VfdPalette palette) => Positioned(
    right: 8,
    bottom: 8,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PrismButton(
          key: const ValueKey('canvas-snap'),
          label: 'Snap',
          palette: palette,
          lit: widget.snapEnabled,
          selected: widget.snapEnabled,
          role: PrismRole.compact,
          style: widget.dashboard.settings.prismStyle,
          soundEnabled: widget.soundEnabled,
          hapticsEnabled: widget.hapticsEnabled,
          onPressed: widget.onToggleSnap,
        ),
        const SizedBox(width: 5),
        PrismButton(
          key: const ValueKey('canvas-fit'),
          label: 'Fit',
          palette: palette,
          role: PrismRole.compact,
          style: widget.dashboard.settings.prismStyle,
          soundEnabled: widget.soundEnabled,
          hapticsEnabled: widget.hapticsEnabled,
          onPressed: _fit,
        ),
        if (widget.onToggleFullScreen != null) ...<Widget>[
          const SizedBox(width: 5),
          PrismButton(
            key: const ValueKey('canvas-full'),
            label: widget.fullScreen ? 'Exit' : 'Full',
            palette: palette,
            lit: widget.fullScreen,
            role: PrismRole.compact,
            style: widget.dashboard.settings.prismStyle,
            soundEnabled: widget.soundEnabled,
            hapticsEnabled: widget.hapticsEnabled,
            onPressed: widget.onToggleFullScreen,
          ),
        ],
      ],
    ),
  );

  String _frameLabel() {
    if (!widget.editable) return 'Inherited · read only';
    final aspect = widget.dashboard.frameAspect(widget.orientation);
    return '${widget.orientation.name} · ${aspect.toStringAsFixed(3)}:1';
  }

  // --- geometry -------------------------------------------------------------

  List<_CanvasItem> _buildItems(Rect content) {
    final items = <_CanvasItem>[];
    final visible = widget.dashboard.componentsIn(widget.orientation);
    final ordered = <ComponentInstance>[
      ...visible.where((component) => component.id != widget.selectedId),
      ...visible.where((component) => component.id == widget.selectedId),
    ];
    for (final component in ordered) {
      final placement = component.placements[widget.orientation];
      if (placement == null) continue;
      final type = ComponentTypes.byId(component.typeId);
      final size = placement.size;
      items.add(
        _CanvasItem(
          id: component.id,
          isModule: false,
          label: type?.displayName ?? component.typeId,
          placement: placement,
          resolvedSize: size,
          selected: component.id == widget.selectedId,
          sceneRect: _sceneRect(content, placement.center, size),
        ),
      );
    }

    final moduleId = widget.selectedModuleId;
    if (moduleId != null &&
        moduleId != kMainVfdModuleId &&
        widget.onModulePlacementChanged != null) {
      for (final module in widget.dashboard.modules) {
        if (module.id != moduleId) continue;
        final placement = module.regionIn(widget.orientation);
        if (placement == null) continue;
        final size = placement.size;
        items.add(
          _CanvasItem(
            id: module.id,
            isModule: true,
            label: module.name,
            placement: placement,
            resolvedSize: size,
            selected: true,
            sceneRect: _sceneRect(content, placement.center, size),
          ),
        );
      }
    }
    return items;
  }

  Rect _sceneRect(Rect content, Offset center, Size size) => Rect.fromLTWH(
    content.left +
        (_layoutExtent.width / 2 + center.dx - size.width / 2) * _designScale,
    content.top +
        (_layoutExtent.height / 2 - center.dy - size.height / 2) * _designScale,
    size.width * _designScale,
    size.height * _designScale,
  );

  Rect _screenRect(Rect scene) => Rect.fromLTWH(
    scene.left * _cameraScale + _cameraOrigin.dx,
    scene.top * _cameraScale + _cameraOrigin.dy,
    scene.width * _cameraScale,
    scene.height * _cameraScale,
  );

  static Rect _containRect(Rect bounds, Size extent) {
    final scale = math.min(
      bounds.width / extent.width,
      bounds.height / extent.height,
    );
    final width = extent.width * scale;
    final height = extent.height * scale;
    return Rect.fromLTWH(
      bounds.left + (bounds.width - width) / 2,
      bounds.top + (bounds.height - height) / 2,
      width,
      height,
    );
  }

  // --- interaction ----------------------------------------------------------

  /// Resolved at pointer-down, topmost item first, corner before edges. The
  /// alternative — a gesture arena between a camera recogniser and per-component
  /// pan recognisers — cannot express "drag an unselected component to pan"
  /// at all, because the child must reject before the parent has seen movement.
  _Grab _hitTest(Offset position) {
    if (!widget.editable) return _Grab.none;
    for (final item in _items.reversed) {
      final rect = _screenRect(item.sceneRect);
      if (item.selected) {
        final half = _handleExtent / 2;
        final corner = Rect.fromCenter(
          center: rect.bottomRight,
          width: _handleExtent,
          height: _handleExtent,
        );
        if (corner.contains(position)) return _Grab(item, _GrabKind.resizeBoth);
        final right = Rect.fromLTRB(
          rect.right - half,
          rect.top,
          rect.right + half,
          rect.bottom,
        );
        if (right.contains(position)) return _Grab(item, _GrabKind.resizeWidth);
        final bottom = Rect.fromLTRB(
          rect.left,
          rect.bottom - half,
          rect.right,
          rect.bottom + half,
        );
        if (bottom.contains(position)) {
          return _Grab(item, _GrabKind.resizeHeight);
        }
      }
      if (rect.contains(position)) return _Grab(item, _GrabKind.body);
    }
    return _Grab.none;
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length >= 2) {
      _promoteToCamera();
      return;
    }
    _grab = _hitTest(event.localPosition);
    _grabOrigin = event.localPosition;
    _dragging = false;
    _cameraGesture = false;
    _cameraScaleAtStart = _cameraScale;
    _cameraOriginAtStart = _cameraOrigin;
    _initialPlacement = _grab.item?.placement;
    _initialDesignScale = _designScale * _cameraScale;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;

    // Two or more pointers always drive the camera, including a promotion
    // part-way through an element drag.
    if (_pointers.length >= 2) {
      _pinchCamera();
      return;
    }
    final delta = event.localPosition - _grabOrigin;
    if (!_dragging) {
      if (delta.distance < kTouchSlop) return;
      _dragging = true;
      // Tap-to-select-first: only an already-selected element responds to a
      // drag. Everything else drives the camera, so a stray drag over a crowded
      // face pans instead of nudging geometry.
      if (!_grab.isResize &&
          !(_grab.kind == _GrabKind.body && _grab.item!.selected)) {
        _cameraGesture = true;
        _grab = _Grab.none;
      }
    }
    if (_cameraGesture) {
      setState(() => _cameraOrigin = _cameraOriginAtStart + delta);
      return;
    }
    _applyElementDrag(delta);
  }

  void _endPointer(int pointer, {required bool tap}) {
    _pointers.remove(pointer);
    if (_pointers.isNotEmpty) {
      // A promoted camera gesture never falls back to moving an element.
      if (_cameraGesture) _rebaseCameraGesture();
      return;
    }
    if (tap && !_dragging && !_cameraGesture && widget.editable) {
      final item = _grab.item;
      if (item == null) {
        widget.onSelect(null);
      } else if (!item.isModule) {
        widget.onSelect(item.id);
      }
    }
    _grab = _Grab.none;
    _dragging = false;
    _cameraGesture = false;
    _initialPlacement = null;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final next = (_cameraScale * math.exp(-event.scrollDelta.dy / 260)).clamp(
      _minCameraScale,
      _maxCameraScale,
    );
    _zoomAbout(event.localPosition, next);
  }

  void _promoteToCamera() {
    _cameraGesture = true;
    _dragging = true;
    _grab = _Grab.none;
    _initialPlacement = null;
    _rebaseCameraGesture();
  }

  void _rebaseCameraGesture() {
    _cameraScaleAtStart = _cameraScale;
    _cameraOriginAtStart = _cameraOrigin;
    _gestureAnchor = _pointerCentroid();
    _gestureSpread = math.max(1, _pointerSpread());
    _grabOrigin = _gestureAnchor;
  }

  void _pinchCamera() {
    final centroid = _pointerCentroid();
    final scale = (_cameraScaleAtStart * _pointerSpread() / _gestureSpread)
        .clamp(_minCameraScale, _maxCameraScale);
    // Keep the scene point that was under the starting centroid pinned to the
    // current one, so the content does not slide out from under the fingers.
    final anchored =
        (_gestureAnchor - _cameraOriginAtStart) / _cameraScaleAtStart;
    setState(() {
      _cameraScale = scale;
      _cameraOrigin = centroid - anchored * scale;
    });
  }

  void _zoomAbout(Offset focus, double scale) {
    if (scale == _cameraScale) return;
    final anchored = (focus - _cameraOrigin) / _cameraScale;
    setState(() {
      _cameraScale = scale;
      _cameraOrigin = focus - anchored * scale;
    });
  }

  Offset _pointerCentroid() {
    if (_pointers.isEmpty) return _gestureAnchor;
    var sum = Offset.zero;
    for (final position in _pointers.values) {
      sum += position;
    }
    return sum / _pointers.length.toDouble();
  }

  double _pointerSpread() {
    if (_pointers.length < 2) return _gestureSpread;
    final centroid = _pointerCentroid();
    var total = 0.0;
    for (final position in _pointers.values) {
      total += (position - centroid).distance;
    }
    return total / _pointers.length;
  }

  void _applyElementDrag(Offset delta) {
    final item = _grab.item;
    final initial = _initialPlacement;
    if (item == null || initial == null) return;
    final scale = _initialDesignScale;
    final Placement next;
    switch (_grab.kind) {
      case _GrabKind.body:
        next = movePlacementBy(
          initial,
          dx: delta.dx / scale,
          dy: -delta.dy / scale,
          snapStep: widget.snapEnabled ? editorSnapStep : null,
        );
      case _GrabKind.resizeWidth:
        next = _resized(initial, widthDelta: delta.dx / scale);
      case _GrabKind.resizeHeight:
        next = _resized(initial, heightDelta: delta.dy / scale);
      case _GrabKind.resizeBoth:
        next = _resized(
          initial,
          widthDelta: delta.dx / scale,
          heightDelta: delta.dy / scale,
        );
      case _GrabKind.none:
        return;
    }
    if (item.isModule) {
      widget.onModulePlacementChanged!(item.id, next);
    } else {
      widget.onPlacementChanged(item.id, next);
    }
  }

  Placement _resized(
    Placement initial, {
    double widthDelta = 0,
    double heightDelta = 0,
  }) => resizePlacementFromEdges(
    placement: initial,
    widthDelta: widthDelta,
    heightDelta: heightDelta,
    snapStep: widget.snapEnabled ? editorSnapStep : null,
  );

  void _fit() {
    if (!mounted) return;
    setState(() {
      _cameraScale = 1;
      _cameraOrigin = Offset.zero;
    });
  }
}

class _CanvasItem {
  const _CanvasItem({
    required this.id,
    required this.isModule,
    required this.label,
    required this.placement,
    required this.resolvedSize,
    required this.selected,
    required this.sceneRect,
  });

  final String id;
  final bool isModule;
  final String label;
  final Placement placement;
  final Size resolvedSize;
  final bool selected;
  final Rect sceneRect;
}

/// Purely presentational. All interaction is resolved centrally, so this paints
/// and nothing else — which is also why the grips can straddle the border
/// without their touch regions needing to live in the same widget.
class _SelectionBox extends StatelessWidget {
  const _SelectionBox({
    required this.label,
    required this.selected,
    required this.livePreview,
    required this.showHandles,
    required this.dimmed,
    required this.handleExtent,
  });

  final String label;
  final bool selected;
  final bool livePreview;
  final bool showHandles;
  final bool dimmed;
  final double handleExtent;

  @override
  Widget build(BuildContext context) {
    const selectedColor = Color(0xFF5DFFC2);
    const idleColor = Color(0xFF7C8681);
    final base = selected ? selectedColor : idleColor;
    final color = dimmed ? base.withValues(alpha: 0.42) : base;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(
                alpha: livePreview ? (selected ? 0.06 : 0.01) : 0.18,
              ),
              border: Border.all(
                color: color.withValues(
                  alpha: livePreview && !selected ? 0.22 : 1,
                ),
                width: selected ? 2 : 1,
              ),
            ),
            child: Center(
              child: livePreview && !selected
                  ? null
                  : Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: color, fontSize: 11),
                    ),
            ),
          ),
        ),
        if (showHandles) ...<Widget>[
          _grip(const ValueKey('resize-width'), color, right: true),
          _grip(const ValueKey('resize-height'), color, bottom: true),
          _grip(
            const ValueKey('resize-both'),
            color,
            right: true,
            bottom: true,
          ),
        ],
      ],
    );
  }

  /// Centred ON the border it resizes, not inboard of it. The 44px box is the
  /// touch region the central hit test mirrors; the 10px square is the grip.
  Widget _grip(
    Key key,
    Color color, {
    bool right = false,
    bool bottom = false,
  }) {
    final half = handleExtent / 2;
    return Positioned(
      key: key,
      left: right ? null : 0,
      right: right ? -half : (bottom ? 0 : null),
      top: bottom ? null : 0,
      bottom: bottom ? -half : (right ? 0 : null),
      width: right ? handleExtent : null,
      height: bottom ? handleExtent : null,
      child: Center(child: Container(width: 10, height: 10, color: color)),
    );
  }
}

class _AuthoredFramePainter extends CustomPainter {
  const _AuthoredFramePainter({
    required this.palette,
    required this.frame,
    this.innerFrame,
  });

  final VfdPalette palette;
  final Rect frame;

  /// The contained inherited layout, drawn only while previewing an orientation
  /// that has no authored layout of its own.
  final Rect? innerFrame;

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
    final inner = innerFrame;
    if (inner != null) canvas.drawRect(inner, dim);
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
      oldDelegate.palette != palette ||
      oldDelegate.frame != frame ||
      oldDelegate.innerFrame != innerFrame;
}

class _OutsideFramePainter extends CustomPainter {
  const _OutsideFramePainter({
    required this.frame,
    required this.palette,
    this.insideScrim,
  });

  final Rect frame;
  final VfdPalette palette;

  /// Drawn across the frame to mark a read-only preview. Same matte language as
  /// the outside region, and — unlike an `Opacity` wrapper — no extra layer
  /// over the shared render pass.
  final Color? insideScrim;

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
    final scrim = insideScrim;
    if (scrim != null) canvas.drawRect(frame, Paint()..color = scrim);
  }

  @override
  bool shouldRepaint(covariant _OutsideFramePainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.palette != palette ||
      oldDelegate.insideScrim != insideScrim;
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
