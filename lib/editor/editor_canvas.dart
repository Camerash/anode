import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../model/component_instance.dart';
import '../model/component_type.dart';
import '../model/dashboard.dart';
import '../model/placement.dart';

class EditorCanvas extends StatelessWidget {
  const EditorCanvas({
    super.key,
    required this.dashboard,
    required this.orientation,
    required this.selectedId,
    required this.onSelect,
    required this.onPlacementChanged,
  });

  final Dashboard dashboard;
  final DesignOrientation orientation;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final void Function(String componentId, Placement placement)
  onPlacementChanged;

  @override
  Widget build(BuildContext context) {
    final aspect = dashboard.frameAspect(orientation);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Center(
        child: AspectRatio(
          key: const ValueKey('editor-canvas'),
          aspectRatio: aspect,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black87,
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
                width: 2,
              ),
            ),
            child: _ComponentStack(
              dashboard: dashboard,
              orientation: orientation,
              selectedId: selectedId,
              onSelect: onSelect,
              onPlacementChanged: onPlacementChanged,
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
    required this.onSelect,
    required this.onPlacementChanged,
  });

  final Dashboard dashboard;
  final DesignOrientation orientation;
  final String? selectedId;
  final ValueChanged<String> onSelect;
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
              // Selection chrome stays reachable without changing model order.
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
    final size = placement.resolveSize(type);
    return Positioned(
      key: ValueKey('canvas-${component.id}'),
      left: (aspect / 2 + center.dx - size.width / 2) * scale,
      top: (0.5 - center.dy - size.height / 2) * scale,
      width: size.width * scale,
      height: size.height * scale,
      child: _ComponentBox(
        component: component,
        placement: placement,
        scale: scale,
        selected: component.id == selectedId,
        onSelect: () => onSelect(component.id),
        onChanged: (value) => onPlacementChanged(component.id, value),
      ),
    );
  }
}

class _ComponentBox extends StatefulWidget {
  const _ComponentBox({
    required this.component,
    required this.placement,
    required this.scale,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
  });

  final ComponentInstance component;
  final Placement placement;
  final double scale;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<Placement> onChanged;

  @override
  State<_ComponentBox> createState() => _ComponentBoxState();
}

class _ComponentBoxState extends State<_ComponentBox> {
  static const double _minimumSize = 0.03;
  static const double _handleExtent = 18;

  Offset? _pointerOrigin;
  late Placement _initialPlacement = widget.placement;

  @override
  Widget build(BuildContext context) {
    final color = widget.selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline;
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
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color, width: widget.selected ? 2 : 1),
      ),
      child: Center(
        child: Text(
          ComponentTypes.byId(widget.component.typeId)?.displayName ??
              widget.component.typeId,
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
      onPan: (delta) => _resize(widthDelta: 2 * delta.dx / widget.scale),
    ),
    _handle(
      key: const ValueKey('resize-height'),
      color: color,
      left: 0,
      right: 0,
      bottom: 0,
      cursor: SystemMouseCursors.resizeUpDown,
      onPan: (delta) => _resize(heightDelta: 2 * delta.dy / widget.scale),
    ),
    _handle(
      key: const ValueKey('resize-both'),
      color: color,
      right: 0,
      bottom: 0,
      cursor: SystemMouseCursors.resizeDownRight,
      onPan: (delta) => _resize(
        widthDelta: 2 * delta.dx / widget.scale,
        heightDelta: 2 * delta.dy / widget.scale,
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
    final type = ComponentTypes.byId(widget.component.typeId);
    final size = _initialPlacement.resolveSize(type);
    widget.onChanged(
      _initialPlacement.copyWith(
        size: Size(
          math.max(_minimumSize, size.width + widthDelta),
          math.max(_minimumSize, size.height + heightDelta),
        ),
      ),
    );
  }

  Offset _pointerDelta(DragUpdateDetails details) =>
      details.globalPosition - (_pointerOrigin ?? details.globalPosition);
}
