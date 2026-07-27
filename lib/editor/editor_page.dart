import 'package:flutter/material.dart';

import '../model/component_instance.dart';
import '../model/component_type.dart';
import '../model/dashboard.dart';
import '../model/placement.dart';
import 'editor_canvas.dart';
import 'param_editor.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.dashboard,
    required this.onChanged,
    this.forkedFrom,
  });

  final Dashboard dashboard;
  final ValueChanged<Dashboard> onChanged;
  final String? forkedFrom;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late Dashboard _dashboard = widget.dashboard;
  late DesignOrientation _orientation = _dashboard.supportedOrientations.first;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    final visible = _dashboard.componentsIn(_orientation);
    _selectedId = visible.isEmpty ? null : visible.first.id;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Edit ${_dashboard.name}')),
    body: SafeArea(
      top: false,
      child: Column(
        children: <Widget>[
          if (widget.forkedFrom != null) _forkBanner(),
          _toolbar(),
          Expanded(child: _responsiveWorkspace()),
        ],
      ),
    ),
  );

  Widget _forkBanner() => MaterialBanner(
    content: Text(
      'Forked from ${widget.forkedFrom}. '
      'Editing user dashboard "${_dashboard.name}".',
    ),
    actions: <Widget>[const Text('USER COPY')],
  );

  Widget _toolbar() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: Row(
      children: <Widget>[
        SegmentedButton<DesignOrientation>(
          segments: <ButtonSegment<DesignOrientation>>[
            for (final value in _dashboard.supportedOrientations)
              ButtonSegment(value: value, label: Text(value.name)),
          ],
          selected: <DesignOrientation>{_orientation},
          onSelectionChanged: (values) =>
              setState(() => _orientation = values.single),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 150,
          child: _AspectField(
            orientation: _orientation,
            value: _dashboard.frameAspect(_orientation),
            onChanged: _setFrameAspect,
          ),
        ),
      ],
    ),
  );

  Widget _responsiveWorkspace() => LayoutBuilder(
    builder: (context, constraints) {
      final canvas = _canvas();
      final inspector = _sidebar();
        if (constraints.maxWidth >= 700) {
        return Row(
          children: <Widget>[
            Expanded(child: canvas),
            SizedBox(width: 380, child: inspector),
          ],
        );
      }
      return Column(
        children: <Widget>[
          Expanded(flex: 3, child: canvas),
          Expanded(flex: 2, child: inspector),
        ],
      );
    },
  );

  Widget _canvas() => Padding(
    padding: const EdgeInsets.all(12),
    child: EditorCanvas(
      dashboard: _dashboard,
      orientation: _orientation,
      selectedId: _selectedId,
      onSelect: (id) => setState(() => _selectedId = id),
      onPlacementChanged: _setPlacement,
    ),
  );

  Widget _sidebar() => _EditorSidebar(
    dashboard: _dashboard,
    orientation: _orientation,
    selectedId: _selectedId,
    onSelected: (id) => setState(() => _selectedId = id),
    onAdd: _addComponent,
    onRemove: _removeComponent,
    onReorder: _reorderComponent,
    onVisibilityChanged: _setVisibility,
    onComponentChanged: _replaceComponent,
  );

  void _setFrameAspect(double value) {
    final aspects = <DesignOrientation, double>{..._dashboard.frameAspects};
    aspects[_orientation] = value;
    _replaceDashboard(_dashboard.copyWith(frameAspects: aspects));
  }

  void _setPlacement(String componentId, Placement placement) {
    final component = _component(componentId);
    if (component == null) return;
    _replaceComponent(component.withPlacement(_orientation, placement));
  }

  void _setVisibility(ComponentInstance component, bool visible) {
    final placement = visible ? const Placement() : null;
    _replaceComponent(component.withPlacement(_orientation, placement));
  }

  void _addComponent(ComponentTypeSpec type) {
    final component = ComponentInstance(
      id: _nextComponentId(type.id),
      typeId: type.id,
      params: type.defaults,
      placements: <DesignOrientation, Placement>{
        _orientation: const Placement(),
      },
    );
    _selectedId = component.id;
    _replaceDashboard(_dashboard.withComponent(component));
  }

  void _removeComponent(ComponentInstance component) {
    final next = _dashboard.withoutComponent(component.id);
    _selectedId = next.components.isEmpty ? null : next.components.first.id;
    _replaceDashboard(next);
  }

  void _reorderComponent(int oldIndex, int newIndex) {
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    _replaceDashboard(_dashboard.reorderComponent(oldIndex, target));
  }

  void _replaceComponent(ComponentInstance component) =>
      _replaceDashboard(_dashboard.withComponent(component));

  void _replaceDashboard(Dashboard next) {
    setState(() => _dashboard = next);
    widget.onChanged(next);
  }

  ComponentInstance? _component(String id) {
    for (final component in _dashboard.components) {
      if (component.id == id) return component;
    }
    return null;
  }

  String _nextComponentId(String typeId) {
    var index = 1;
    var candidate = '$typeId-$index';
    final ids = _dashboard.components.map((component) => component.id).toSet();
    while (ids.contains(candidate)) {
      candidate = '$typeId-${++index}';
    }
    return candidate;
  }
}

class _EditorSidebar extends StatelessWidget {
  const _EditorSidebar({
    required this.dashboard,
    required this.orientation,
    required this.selectedId,
    required this.onSelected,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
    required this.onVisibilityChanged,
    required this.onComponentChanged,
  });

  final Dashboard dashboard;
  final DesignOrientation orientation;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final ValueChanged<ComponentTypeSpec> onAdd;
  final ValueChanged<ComponentInstance> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(ComponentInstance component, bool visible)
  onVisibilityChanged;
  final ValueChanged<ComponentInstance> onComponentChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Column(
      children: <Widget>[
        _listHeader(),
        Expanded(child: _componentList()),
        const Divider(height: 1),
        Expanded(child: _inspector()),
      ],
    ),
  );

  Widget _listHeader() => ListTile(
    title: const Text('Components'),
    trailing: PopupMenuButton<ComponentTypeSpec>(
      tooltip: 'Add component',
      icon: const Icon(Icons.add),
      onSelected: onAdd,
      itemBuilder: (context) => <PopupMenuEntry<ComponentTypeSpec>>[
        for (final type in ComponentTypes.all)
          PopupMenuItem(value: type, child: Text(type.displayName)),
      ],
    ),
  );

  Widget _componentList() => ReorderableListView.builder(
    buildDefaultDragHandles: false,
    itemCount: dashboard.components.length,
    onReorder: onReorder,
    itemBuilder: (context, index) {
      final component = dashboard.components[index];
      return _componentTile(component, index);
    },
  );

  Widget _componentTile(ComponentInstance component, int index) {
    final visible = component.appearsIn(orientation);
    final name =
        ComponentTypes.byId(component.typeId)?.displayName ?? component.typeId;
    return ListTile(
      key: ValueKey(component.id),
      selected: component.id == selectedId,
      onTap: () => onSelected(component.id),
      leading: ReorderableDragStartListener(
        index: index,
        child: const Icon(Icons.drag_handle),
      ),
      title: Text(name),
      subtitle: Text(component.id),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Checkbox(
            value: visible,
            onChanged: (value) =>
                onVisibilityChanged(component, value ?? false),
          ),
          IconButton(
            tooltip: 'Remove component',
            onPressed: () => onRemove(component),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Widget _inspector() {
    final component = _selectedComponent();
    if (component == null) {
      return const Center(child: Text('Select a component'));
    }
    return _ComponentInspector(
      component: component,
      orientation: orientation,
      aspect: dashboard.frameAspect(orientation),
      onVisibilityChanged: (visible) => onVisibilityChanged(component, visible),
      onChanged: onComponentChanged,
    );
  }

  ComponentInstance? _selectedComponent() {
    for (final component in dashboard.components) {
      if (component.id == selectedId) return component;
    }
    return null;
  }
}

class _ComponentInspector extends StatelessWidget {
  const _ComponentInspector({
    required this.component,
    required this.orientation,
    required this.aspect,
    required this.onVisibilityChanged,
    required this.onChanged,
  });

  final ComponentInstance component;
  final DesignOrientation orientation;
  final double aspect;
  final ValueChanged<bool> onVisibilityChanged;
  final ValueChanged<ComponentInstance> onChanged;

  @override
  Widget build(BuildContext context) {
    final type = ComponentTypes.byId(component.typeId);
    final placement = component.placements[orientation];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            type?.displayName ?? component.typeId,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Visible in ${orientation.name}'),
            value: placement != null,
            onChanged: onVisibilityChanged,
          ),
          if (placement != null) ..._placementControls(placement),
          if (type != null) ...<Widget>[
            const Divider(),
            Text('Parameters', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            ParamEditor(
              specs: type.params,
              values: component.effectiveParams,
              onChanged: (key, value) =>
                  onChanged(component.withParam(key, value)),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _placementControls(Placement placement) => <Widget>[
    DropdownButtonFormField<Anchor>(
      initialValue: placement.anchor,
      decoration: const InputDecoration(labelText: 'Anchor'),
      items: <DropdownMenuItem<Anchor>>[
        for (final anchor in Anchor.values)
          DropdownMenuItem(value: anchor, child: Text(anchor.name)),
      ],
      onChanged: (anchor) {
        if (anchor == null) return;
        onChanged(
          component.withPlacement(
            orientation,
            _changeAnchor(placement, anchor),
          ),
        );
      },
    ),
    const SizedBox(height: 12),
    Text(
      'Offset: ${placement.offset.dx.toStringAsFixed(3)}, '
      '${placement.offset.dy.toStringAsFixed(3)}',
    ),
    const SizedBox(height: 4),
    Text(_sizeLabel(placement)),
  ];

  Placement _changeAnchor(Placement placement, Anchor anchor) {
    final center = placement.resolve(aspect);
    return placement.copyWith(
      anchor: anchor,
      offset: center - anchor.pointIn(aspect),
    );
  }

  String _sizeLabel(Placement placement) {
    final size = placement.resolveSize(ComponentTypes.byId(component.typeId));
    return 'Size: ${size.width.toStringAsFixed(3)} × '
        '${size.height.toStringAsFixed(3)}';
  }
}

class _AspectField extends StatefulWidget {
  const _AspectField({
    required this.orientation,
    required this.value,
    required this.onChanged,
  });

  final DesignOrientation orientation;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_AspectField> createState() => _AspectFieldState();
}

class _AspectFieldState extends State<_AspectField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value.toStringAsFixed(3),
  );

  @override
  void didUpdateWidget(covariant _AspectField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orientation != widget.orientation ||
        oldWidget.value != widget.value) {
      _controller.text = widget.value.toStringAsFixed(3);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    decoration: const InputDecoration(labelText: 'Frame aspect', isDense: true),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onSubmitted: (raw) {
      final value = double.tryParse(raw);
      if (value != null && value.isFinite && value > 0) {
        widget.onChanged(value);
      } else {
        _controller.text = widget.value.toStringAsFixed(3);
      }
    },
  );
}
