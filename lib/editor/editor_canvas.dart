import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../model/component_instance.dart';
import '../model/component_type.dart';
import '../model/dashboard.dart';
import '../model/placement.dart';
import '../model/vfd_module.dart';
import '../vfd/vfd_render_assets.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_widgets.dart';
import 'editor_add_catalogue.dart';
import 'editor_live_preview.dart';
import 'placement_transform.dart';

class EditorCanvas extends StatefulWidget {
  const EditorCanvas({
    super.key,
    required this.dashboard,
    required this.orientation,
    required this.selectedId,
    required this.onSelect,
    required this.onPlacementChanged,
    this.onPlacementGestureStarted,
    this.onPlacementGestureEnded,
    required this.deviceViewportSize,
    this.selectedModuleId,
    this.onModulePlacementChanged,
    this.renderAssets,
    this.previewOrientation,
    this.editable = true,
    this.frameInset = EdgeInsets.zero,
    this.chromeSafeInsets = EdgeInsets.zero,
    this.commandBankBottomInset = 0,
    this.onAddRequested,
    this.onAddDropped,
    this.previewController,
    this.canUndo = false,
    this.canRedo = false,
    this.onUndo,
    this.onRedo,
    this.snapEnabled = true,
    this.onToggleSnap,
    this.onPreviewOrientationChanged,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  });

  final Dashboard dashboard;
  final DesignOrientation orientation;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final void Function(String componentId, Placement placement)
  onPlacementChanged;
  final VoidCallback? onPlacementGestureStarted;
  final ValueChanged<bool>? onPlacementGestureEnded;

  /// Full device viewport. Unsafe regions remain authorable.
  final Size deviceViewportSize;
  final String? selectedModuleId;
  final void Function(String moduleId, Placement placement)?
  onModulePlacementChanged;
  final VfdRenderAssets? renderAssets;
  final DesignOrientation? previewOrientation;
  final bool editable;
  final EdgeInsets frameInset;

  /// Insets editor chrome only. Authored content and interaction geometry
  /// remain resolved against the complete device viewport.
  final EdgeInsets chromeSafeInsets;
  final double commandBankBottomInset;
  final VoidCallback? onAddRequested;
  final void Function(EditorAddRequest request, Offset center)? onAddDropped;
  final EditorCanvasPreviewController? previewController;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool snapEnabled;
  final VoidCallback? onToggleSnap;
  final ValueChanged<DesignOrientation>? onPreviewOrientationChanged;
  final bool soundEnabled;
  final bool hapticsEnabled;

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

/// Maps global drag positions to target-scale preview bounds without making the
/// catalogue depend on canvas layout internals.
class EditorCanvasPreviewController {
  _EditorCanvasState? _state;

  Rect? previewRect(EditorAddRequest request, Offset globalPosition) =>
      _state?._unboundedPreviewRect(request, globalPosition);

  void _attach(_EditorCanvasState state) => _state = state;

  void _detach(_EditorCanvasState state) {
    if (_state == state) _state = null;
  }
}

/// Target-scale VFD ghost, rendered in page space so it can cross the service
/// drawer without painting a second substrate over it.
class EditorCanvasDropPreview extends StatelessWidget {
  const EditorCanvasDropPreview({
    super.key,
    required this.dashboard,
    required this.orientation,
    required this.request,
    required this.renderAssets,
  });

  final Dashboard dashboard;
  final DesignOrientation orientation;
  final EditorAddRequest request;
  final VfdRenderAssets? renderAssets;

  @override
  Widget build(BuildContext context) {
    final palette = VfdPalette.of(dashboard.settings.opticalProfile.phosphor);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (renderAssets != null && request.componentType != null)
          EditorLiveVfdPreview(
            renderAssets: renderAssets!,
            dashboard: _previewDashboard(),
            orientation: orientation,
            transparentBackground: true,
          ),
        DecoratedBox(
          key: const ValueKey('add-drop-ghost'),
          decoration: BoxDecoration(
            color: palette.lit.withValues(alpha: 0.05),
            border: Border.all(color: palette.lit.withValues(alpha: 0.8)),
          ),
        ),
      ],
    );
  }

  Dashboard _previewDashboard() {
    final type = request.componentType!;
    final size = editorAddDropSize(request);
    return Dashboard(
      id: 'editor.add.canvas-preview',
      name: request.label,
      primaryOrientation: orientation,
      frameSpecs: <DesignOrientation, FrameSpec>{
        orientation: FrameSpec(width: size.width, height: size.height),
      },
      settings: dashboard.settings,
      components: <ComponentInstance>[
        ComponentInstance(
          id: 'editor.add.canvas-preview.component',
          typeId: type.id,
          params: type.defaults,
          placements: <DesignOrientation, Placement>{
            orientation: Placement(center: Offset.zero, size: size),
          },
        ),
      ],
    );
  }
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
  static const double _minCameraScale = 0.5;
  static const double _maxCameraScale = 4;
  // Matches the former VFD substrate plus exterior matte composite, so a
  // fitted canvas keeps its existing visual while a panned canvas stays flat.
  static const Color _workspaceMatte = Color(0xFF121613);

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
  bool _placementGestureActive = false;
  Placement? _initialPlacement;
  double _initialDesignScale = 1;
  double _cameraScaleAtStart = 1;
  Offset _cameraOriginAtStart = Offset.zero;
  Offset _gestureAnchor = Offset.zero;
  double _gestureSpread = 1;

  @override
  void initState() {
    super.initState();
    widget.previewController?._attach(this);
  }

  @override
  void didUpdateWidget(covariant EditorCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orientation != widget.orientation ||
        oldWidget.previewOrientation != widget.previewOrientation ||
        oldWidget.dashboard.id != widget.dashboard.id) {
      _fit();
    }
    if (oldWidget.previewController != widget.previewController) {
      oldWidget.previewController?._detach(this);
      widget.previewController?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.previewController?._detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = VfdPalette.of(
      widget.dashboard.settings.opticalProfile.phosphor,
    );
    return ColoredBox(
      key: const ValueKey('editor-canvas-background'),
      color: _workspaceMatte,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sceneSize = Size(
            math.max(1, constraints.maxWidth),
            math.max(1, constraints.maxHeight),
          );
          final layoutExtent = widget.dashboard.frameExtent(widget.orientation);

          // Outer boundary is always the complete runtime viewport. Authored
          // geometry remains inside its fixed contained frame.
          final previewOrientation =
              widget.previewOrientation ?? widget.orientation;
          final boundaryExtent = viewportFrameExtent(
            previewOrientation,
            widget.deviceViewportSize,
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
          final content = _containRect(boundary, layoutExtent);
          _layoutExtent = layoutExtent;
          _designScale = content.height / layoutExtent.height;
          _items = _buildItems(content);

          return DragTarget<EditorAddRequest>(
            onWillAcceptWithDetails: (_) =>
                widget.editable && widget.onAddDropped != null,
            onAcceptWithDetails: (details) =>
                _acceptDrop(context, content, details),
            builder: (context, candidates, rejected) => Stack(
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
                if (candidates.isNotEmpty)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _DropTargetPainter(
                        palette: palette,
                        frame: content,
                      ),
                    ),
                  ),
                _commandBank(palette),
              ],
            ),
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
          EditorLiveVfdPreview(
            renderAssets: widget.renderAssets!,
            dashboard: widget.dashboard,
            orientation: widget.orientation,
            // The boundary, not the content rect: the shader performs the
            // same contain fit the runtime does. Painter-level clipping keeps
            // shader coordinates intact while limiting its opaque substrate
            // to the visible authored frame.
            frameInsets: EdgeInsets.fromLTRB(
              boundary.left,
              boundary.top,
              sceneSize.width - boundary.right,
              sceneSize.height - boundary.bottom,
            ),
            clipRect: content,
          ),
        if (!widget.editable)
          CustomPaint(
            painter: _FrameScrimPainter(
              frame: content,
              // Dimming, not opacity: an Opacity layer over the shader forces
              // a saveLayer above the render pass.
              color: const Color(0x99111512),
            ),
          ),
        CustomPaint(
          painter: _AuthoredFramePainter(palette: palette, frame: content),
        ),
        Positioned.fromRect(
          rect: boundary,
          child: const SizedBox(key: ValueKey('editor-canvas')),
        ),
        Positioned.fromRect(
          rect: content,
          child: const SizedBox(key: ValueKey('editor-authored-frame')),
        ),
        Positioned(
          left: content.left + 7,
          top: content.top + 7,
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

  Widget _commandBank(VfdPalette palette) => Positioned(
    key: const ValueKey('editor-command-bank-position'),
    left: widget.chromeSafeInsets.left + 8,
    right: widget.chromeSafeInsets.right + 8,
    bottom: widget.chromeSafeInsets.bottom + widget.commandBankBottomInset + 8,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: PrismPanel(
          key: const ValueKey('editor-command-bank'),
          palette: palette,
          surfaceOpacity: 0.88,
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _commandBay(
                label: 'History',
                palette: palette,
                controls: <Widget>[
                  _commandButton(
                    key: const ValueKey('canvas-undo'),
                    label: 'Undo',
                    symbol: PrismSymbol.undo,
                    lit: widget.canUndo,
                    enabled: widget.canUndo,
                    onPressed: widget.canUndo ? widget.onUndo : null,
                    palette: palette,
                  ),
                  _commandButton(
                    key: const ValueKey('canvas-redo'),
                    label: 'Redo',
                    symbol: PrismSymbol.redo,
                    lit: widget.canRedo,
                    enabled: widget.canRedo,
                    onPressed: widget.canRedo ? widget.onRedo : null,
                    palette: palette,
                  ),
                ],
              ),
              _bayDivider(palette),
              _commandBay(
                label: 'Build',
                palette: palette,
                controls: <Widget>[
                  if (widget.onAddRequested != null)
                    _commandButton(
                      key: const ValueKey('canvas-add'),
                      label: 'Add',
                      onPressed: widget.editable ? widget.onAddRequested : null,
                      palette: palette,
                    ),
                  _commandButton(
                    key: const ValueKey('canvas-snap'),
                    label: 'Snap',
                    lit: widget.snapEnabled,
                    selected: widget.snapEnabled,
                    onPressed: widget.onToggleSnap,
                    palette: palette,
                  ),
                ],
              ),
              _bayDivider(palette),
              _commandBay(
                label: 'View',
                palette: palette,
                controls: <Widget>[
                  _commandButton(
                    key: const ValueKey('canvas-fit'),
                    label: 'Fit view',
                    symbol: PrismSymbol.fit,
                    onPressed: _fit,
                    palette: palette,
                  ),
                  for (final orientation in DesignOrientation.values)
                    _commandButton(
                      key: ValueKey('orientation-${orientation.name}'),
                      label: orientation.name,
                      lit:
                          orientation ==
                          (widget.previewOrientation ?? widget.orientation),
                      selected:
                          orientation ==
                          (widget.previewOrientation ?? widget.orientation),
                      onPressed: widget.onPreviewOrientationChanged == null
                          ? null
                          : () => widget.onPreviewOrientationChanged!(
                              orientation,
                            ),
                      palette: palette,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _commandBay({
    required String label,
    required VfdPalette palette,
    required List<Widget> controls,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      if (MediaQuery.sizeOf(context).width >= 600) ...<Widget>[
        VfdLegend(label, palette: palette, size: 7),
        const SizedBox(height: 1),
      ],
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var index = 0; index < controls.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(width: 3),
            controls[index],
          ],
        ],
      ),
    ],
  );

  Widget _bayDivider(VfdPalette palette) => SizedBox(
    width: 7,
    height: 34,
    child: Center(
      child: SizedBox(
        width: 1,
        height: 30,
        child: ColoredBox(color: palette.unlit.withValues(alpha: 0.34)),
      ),
    ),
  );

  Widget _commandButton({
    required Key key,
    required String label,
    required VfdPalette palette,
    required VoidCallback? onPressed,
    PrismSymbol? symbol,
    bool lit = false,
    bool selected = false,
    bool enabled = true,
  }) => PrismButton(
    key: key,
    label: label,
    symbol: symbol,
    palette: palette,
    role: PrismRole.compact,
    style: widget.dashboard.settings.prismStyle,
    soundEnabled: widget.soundEnabled,
    hapticsEnabled: widget.hapticsEnabled,
    lit: lit,
    selected: selected,
    enabled: enabled,
    onPressed: onPressed,
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

  void _acceptDrop(
    BuildContext context,
    Rect content,
    DragTargetDetails<EditorAddRequest> details,
  ) {
    final center = _dropCenter(context, content, details.offset);
    widget.onAddDropped?.call(details.data, center);
  }

  Offset _dropCenter(BuildContext context, Rect content, Offset global) {
    final box = context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(global);
    final scene = (local - _cameraOrigin) / _cameraScale;
    final raw = Offset(
      (scene.dx - content.center.dx) / _designScale,
      -(scene.dy - content.center.dy) / _designScale,
    );
    if (!widget.snapEnabled) return raw;
    return Offset(
      (raw.dx / editorSnapStep).round() * editorSnapStep,
      (raw.dy / editorSnapStep).round() * editorSnapStep,
    );
  }

  Rect? _unboundedPreviewRect(EditorAddRequest request, Offset globalPosition) {
    if (!mounted || _designScale <= 0) return null;
    final size = editorAddDropSize(request) * (_designScale * _cameraScale);
    return Rect.fromCenter(
      center: globalPosition,
      width: size.width,
      height: size.height,
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
      } else {
        _placementGestureActive = true;
        widget.onPlacementGestureStarted?.call();
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
    if (_placementGestureActive) {
      widget.onPlacementGestureEnded?.call(tap);
      _placementGestureActive = false;
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
    required this.selected,
    required this.livePreview,
    required this.showHandles,
    required this.dimmed,
    required this.handleExtent,
  });

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

class _DropTargetPainter extends CustomPainter {
  const _DropTargetPainter({required this.palette, required this.frame});

  final VfdPalette palette;
  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      frame,
      Paint()
        ..color = palette.lit.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      frame.deflate(2),
      Paint()
        ..color = palette.lit.withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _DropTargetPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.frame != frame;
}

class _FrameScrimPainter extends CustomPainter {
  const _FrameScrimPainter({required this.frame, required this.color});

  final Rect frame;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(frame, Paint()..color = color);

  @override
  bool shouldRepaint(covariant _FrameScrimPainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.color != color;
}
