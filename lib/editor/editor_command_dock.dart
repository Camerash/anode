import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../model/settings.dart';
import 'editor_chrome_skin.dart';

class EditorCommandDock extends StatefulWidget {
  const EditorCommandDock({
    super.key,
    required this.skin,
    required this.placement,
    required this.safeInsets,
    required this.headerExtent,
    required this.canUndo,
    required this.canRedo,
    required this.snapEnabled,
    required this.onUndo,
    required this.onRedo,
    required this.onToggleSnap,
    required this.onCenter,
    required this.onPlacementChanged,
  });

  final EditorChromeSkin skin;
  final EditorDockPlacement placement;
  final EdgeInsets safeInsets;
  final double headerExtent;
  final bool canUndo;
  final bool canRedo;
  final bool snapEnabled;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback onToggleSnap;
  final VoidCallback onCenter;
  final ValueChanged<EditorDockPlacement> onPlacementChanged;

  @override
  State<EditorCommandDock> createState() => _EditorCommandDockState();
}

class _EditorCommandDockState extends State<EditorCommandDock>
    with SingleTickerProviderStateMixin {
  final GlobalKey _hostKey = GlobalKey();
  final GlobalKey _dockKey = GlobalKey();
  late EditorDockPlacement _displayPlacement = widget.placement;
  late final AnimationController _settleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  )..value = 1;

  Offset? _dragTopLeft;
  Offset? _grabOffset;
  Offset? _settleFrom;
  EditorDockEdge? _candidateEdge;

  @override
  void didUpdateWidget(covariant EditorCommandDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_dragTopLeft == null && oldWidget.placement != widget.placement) {
      _displayPlacement = widget.placement;
    }
  }

  @override
  void dispose() {
    _settleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final hostSize = Size(constraints.maxWidth, constraints.maxHeight);
      final vertical = _displayPlacement.edge != EditorDockEdge.bottom;
      final compact = vertical
          ? hostSize.height - widget.headerExtent - widget.safeInsets.bottom <
                300
          : hostSize.width - widget.safeInsets.left - widget.safeInsets.right <
                340;
      final axis = vertical ? Axis.vertical : Axis.horizontal;
      final dock = KeyedSubtree(
        key: _dockKey,
        child: widget.skin.surface(
          key: const ValueKey('editor-command-dock'),
          role: EditorChromeSurfaceRole.dock,
          padding: _surfacePadding(_displayPlacement.edge),
          child: Flex(
            direction: axis,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _handle(axis),
              _gap(axis, compact ? 3 : 5),
              _button(
                key: const ValueKey('canvas-undo'),
                label: 'Undo',
                symbol: EditorChromeSymbol.undo,
                lit: widget.canUndo,
                enabled: widget.canUndo,
                onPressed: widget.canUndo ? widget.onUndo : null,
                compact: compact,
              ),
              _gap(axis, compact ? 3 : 5),
              _button(
                key: const ValueKey('canvas-redo'),
                label: 'Redo',
                symbol: EditorChromeSymbol.redo,
                lit: widget.canRedo,
                enabled: widget.canRedo,
                onPressed: widget.canRedo ? widget.onRedo : null,
                compact: compact,
              ),
              _gap(axis, compact ? 5 : 8),
              widget.skin.divider(axis: axis),
              _gap(axis, compact ? 5 : 8),
              _button(
                key: const ValueKey('canvas-snap'),
                label: 'Snap',
                lit: widget.snapEnabled,
                selected: widget.snapEnabled,
                onPressed: widget.onToggleSnap,
                compact: compact,
              ),
              _gap(axis, compact ? 3 : 5),
              _button(
                key: const ValueKey('canvas-center'),
                label: 'Center',
                onPressed: widget.onCenter,
                compact: compact,
              ),
            ],
          ),
        ),
      );

      return Stack(
        key: _hostKey,
        fit: StackFit.expand,
        children: <Widget>[
          if (_candidateEdge case final edge?)
            IgnorePointer(child: _edgePreview(edge)),
          AnimatedBuilder(
            animation: _settleController,
            child: dock,
            builder: (context, child) => CustomSingleChildLayout(
              delegate: _DockLayoutDelegate(
                placement: _displayPlacement,
                safeInsets: widget.safeInsets,
                headerExtent: widget.headerExtent,
                dragTopLeft: _dragTopLeft,
                settleFrom: _settleFrom,
                settleProgress: _settleController.value,
              ),
              child: child,
            ),
          ),
        ],
      );
    },
  );

  EdgeInsets _surfacePadding(EditorDockEdge edge) => switch (edge) {
    EditorDockEdge.left => EdgeInsets.fromLTRB(
      widget.safeInsets.left + 4,
      4,
      4,
      4,
    ),
    EditorDockEdge.right => EdgeInsets.fromLTRB(
      4,
      4,
      widget.safeInsets.right + 4,
      4,
    ),
    EditorDockEdge.bottom => EdgeInsets.fromLTRB(
      4,
      4,
      4,
      widget.safeInsets.bottom + 4,
    ),
  };

  Widget _handle(Axis axis) => Semantics(
    label: 'Move editor dock',
    button: true,
    child: GestureDetector(
      key: const ValueKey('editor-dock-handle'),
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: _startDrag,
      onPanUpdate: _updateDrag,
      onPanEnd: (_) => _endDrag(),
      onPanCancel: _cancelDrag,
      child: SizedBox.square(
        dimension: 44,
        child: widget.skin.dragHandle(axis: axis, active: _dragTopLeft != null),
      ),
    ),
  );

  Widget _button({
    required Key key,
    required String label,
    required VoidCallback? onPressed,
    required bool compact,
    EditorChromeSymbol? symbol,
    bool lit = false,
    bool selected = false,
    bool enabled = true,
  }) => widget.skin.button(
    key: key,
    label: label,
    symbol: symbol,
    lit: lit,
    selected: selected,
    enabled: enabled,
    compact: compact,
    onPressed: onPressed,
  );

  Widget _gap(Axis axis, double extent) => SizedBox(
    width: axis == Axis.horizontal ? extent : 0,
    height: axis == Axis.vertical ? extent : 0,
  );

  Widget _edgePreview(EditorDockEdge edge) => Align(
    alignment: switch (edge) {
      EditorDockEdge.left => Alignment.centerLeft,
      EditorDockEdge.right => Alignment.centerRight,
      EditorDockEdge.bottom => Alignment.bottomCenter,
    },
    child: widget.skin.dockTargetIndicator(
      axis: edge == EditorDockEdge.bottom ? Axis.horizontal : Axis.vertical,
    ),
  );

  void _startDrag(DragStartDetails details) {
    final host = _hostKey.currentContext?.findRenderObject() as RenderBox?;
    final dock = _dockKey.currentContext?.findRenderObject() as RenderBox?;
    if (host == null || dock == null) return;
    final pointer = host.globalToLocal(details.globalPosition);
    final topLeft = host.globalToLocal(dock.localToGlobal(Offset.zero));
    _settleController.stop();
    setState(() {
      _settleFrom = null;
      _dragTopLeft = topLeft;
      _grabOffset = pointer - topLeft;
      _candidateEdge = _nearestEdge(pointer, host.size);
    });
  }

  void _updateDrag(DragUpdateDetails details) {
    final host = _hostKey.currentContext?.findRenderObject() as RenderBox?;
    final dock = _dockKey.currentContext?.findRenderObject() as RenderBox?;
    if (host == null || dock == null || _grabOffset == null) return;
    final pointer = host.globalToLocal(details.globalPosition);
    final raw = pointer - _grabOffset!;
    final maxX = math.max(0.0, host.size.width - dock.size.width);
    final maxY = math.max(
      widget.headerExtent,
      host.size.height - widget.safeInsets.bottom - dock.size.height,
    );
    setState(() {
      _dragTopLeft = Offset(
        raw.dx.clamp(0.0, maxX),
        raw.dy.clamp(widget.headerExtent, maxY),
      );
      _candidateEdge = _nearestEdge(pointer, host.size);
    });
  }

  void _endDrag() {
    final host = _hostKey.currentContext?.findRenderObject() as RenderBox?;
    final dock = _dockKey.currentContext?.findRenderObject() as RenderBox?;
    final from = _dragTopLeft;
    if (host == null || dock == null || from == null) {
      _cancelDrag();
      return;
    }
    final pointer = from + dock.size.center(Offset.zero);
    final edge = _candidateEdge ?? _nearestEdge(pointer, host.size);
    final placement = EditorDockPlacement(
      edge: edge,
      alignment: _alignmentFor(edge, pointer, host.size),
    );
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    setState(() {
      _displayPlacement = placement;
      _dragTopLeft = null;
      _grabOffset = null;
      _candidateEdge = null;
      _settleFrom = reduced ? null : from;
    });
    widget.onPlacementChanged(placement);
    if (reduced) return;
    _settleController
      ..value = 0
      ..forward().whenComplete(() {
        if (mounted) setState(() => _settleFrom = null);
      });
  }

  void _cancelDrag() => setState(() {
    _dragTopLeft = null;
    _grabOffset = null;
    _candidateEdge = null;
    _settleFrom = null;
  });

  EditorDockEdge _nearestEdge(Offset point, Size size) {
    final distances = <EditorDockEdge, double>{
      EditorDockEdge.left: point.dx,
      EditorDockEdge.right: size.width - point.dx,
      EditorDockEdge.bottom: size.height - point.dy,
    };
    return distances.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }

  double _alignmentFor(EditorDockEdge edge, Offset point, Size size) {
    if (edge == EditorDockEdge.bottom) {
      final span = math.max(
        1.0,
        size.width - widget.safeInsets.left - widget.safeInsets.right,
      );
      return ((point.dx - widget.safeInsets.left) / span).clamp(0.0, 1.0);
    }
    final span = math.max(
      1.0,
      size.height - widget.headerExtent - widget.safeInsets.bottom,
    );
    return ((point.dy - widget.headerExtent) / span).clamp(0.0, 1.0);
  }
}

class _DockLayoutDelegate extends SingleChildLayoutDelegate {
  const _DockLayoutDelegate({
    required this.placement,
    required this.safeInsets,
    required this.headerExtent,
    required this.dragTopLeft,
    required this.settleFrom,
    required this.settleProgress,
  });

  final EditorDockPlacement placement;
  final EdgeInsets safeInsets;
  final double headerExtent;
  final Offset? dragTopLeft;
  final Offset? settleFrom;
  final double settleProgress;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      const BoxConstraints();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    if (dragTopLeft case final drag?) return drag;
    final target = switch (placement.edge) {
      EditorDockEdge.left => Offset(
        0,
        _trackOffset(
          start: headerExtent,
          end: size.height - safeInsets.bottom,
          childExtent: childSize.height,
        ),
      ),
      EditorDockEdge.right => Offset(
        size.width - childSize.width,
        _trackOffset(
          start: headerExtent,
          end: size.height - safeInsets.bottom,
          childExtent: childSize.height,
        ),
      ),
      EditorDockEdge.bottom => Offset(
        _trackOffset(
          start: safeInsets.left,
          end: size.width - safeInsets.right,
          childExtent: childSize.width,
        ),
        size.height - childSize.height,
      ),
    };
    return settleFrom == null
        ? target
        : Offset.lerp(settleFrom, target, settleProgress)!;
  }

  double _trackOffset({
    required double start,
    required double end,
    required double childExtent,
  }) {
    final travel = math.max(0.0, end - start - childExtent);
    return start + travel * placement.alignment;
  }

  @override
  bool shouldRelayout(covariant _DockLayoutDelegate oldDelegate) =>
      oldDelegate.placement != placement ||
      oldDelegate.safeInsets != safeInsets ||
      oldDelegate.headerExtent != headerExtent ||
      oldDelegate.dragTopLeft != dragTopLeft ||
      oldDelegate.settleFrom != settleFrom ||
      oldDelegate.settleProgress != settleProgress;
}
