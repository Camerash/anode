import 'package:flutter/material.dart';

import '../actions/action_registry.dart';
import '../model/action_binding.dart';
import '../model/component_instance.dart';
import '../model/component_type.dart';
import '../model/dashboard.dart';
import '../model/optical_profile.dart';
import '../model/placement.dart';
import '../model/variant.dart';
import '../model/vfd_module.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_render_assets.dart';
import '../vfd/vfd_widgets.dart';
import 'editor_canvas.dart';
import 'effect_panel.dart';
import 'param_editor.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.dashboard,
    required this.onChanged,
    this.forkedFrom,
    this.renderAssets,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.actionRegistry,
  });

  final Dashboard dashboard;
  final ValueChanged<Dashboard> onChanged;
  final String? forkedFrom;
  final VfdRenderAssets? renderAssets;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final ActionRegistry? actionRegistry;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late Dashboard _dashboard = widget.dashboard;
  late DesignOrientation _orientation = _dashboard.supportedOrientations.first;
  String? _selectedId;
  String? _selectedModuleId;

  VfdPalette get _palette =>
      VfdPalette.of(_dashboard.settings.opticalProfile.phosphor);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF050807),
    appBar: AppBar(
      backgroundColor: const Color(0xFF050807),
      foregroundColor: _palette.unlit,
      title: VfdLegend(
        'Edit ${_dashboard.name}',
        palette: _palette,
        lit: true,
        size: 15,
      ),
    ),
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

  Widget _toolbar() => PrismPanel(
    palette: _palette,
    padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
    child: Row(
      children: <Widget>[
        for (final value in _dashboard.supportedOrientations) ...<Widget>[
          PrismButton(
            label: value.name,
            palette: _palette,
            lit: value == _orientation,
            selected: value == _orientation,
            role: PrismRole.compact,
            span: PrismSpan.two,
            style: _dashboard.settings.prismStyle,
            soundEnabled: widget.soundEnabled,
            hapticsEnabled: widget.hapticsEnabled,
            onPressed: () => setState(() => _orientation = value),
          ),
          const SizedBox(width: 7),
        ],
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
      selectedModuleId: _selectedModuleId,
      onSelect: (id) => setState(() {
        _selectedId = id;
        _selectedModuleId = null;
      }),
      onPlacementChanged: _setPlacement,
      onModulePlacementChanged: _setModulePlacement,
      renderAssets: widget.renderAssets,
    ),
  );

  Widget _sidebar() => _EditorSidebar(
    dashboard: _dashboard,
    orientation: _orientation,
    selectedId: _selectedId,
    selectedModuleId: _selectedModuleId,
    onSelected: (id) => setState(() {
      _selectedId = id;
      _selectedModuleId = null;
    }),
    onModuleSelected: (id) => setState(() {
      _selectedId = null;
      _selectedModuleId = id;
    }),
    onAdd: _addComponent,
    onRemove: _removeComponent,
    onReorder: _reorderComponent,
    onVisibilityChanged: _setVisibility,
    onComponentChanged: _replaceComponent,
    onDashboardChanged: _replaceDashboard,
    soundEnabled: widget.soundEnabled,
    hapticsEnabled: widget.hapticsEnabled,
    actionRegistry: widget.actionRegistry ?? ActionRegistry.forAuthoring(),
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

  void _setModulePlacement(String moduleId, Placement placement) {
    final module = _dashboard.modules
        .where((candidate) => candidate.id == moduleId)
        .firstOrNull;
    if (module == null || module.id == kMainVfdModuleId) return;
    _replaceDashboard(
      _dashboard.withModule(
        module.copyWith(
          regions: <DesignOrientation, Placement>{
            ...module.regions,
            _orientation: placement,
          },
        ),
      ),
    );
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
    required this.selectedModuleId,
    required this.onSelected,
    required this.onModuleSelected,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
    required this.onVisibilityChanged,
    required this.onComponentChanged,
    required this.onDashboardChanged,
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.actionRegistry,
  });

  final Dashboard dashboard;
  final DesignOrientation orientation;
  final String? selectedId;
  final String? selectedModuleId;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onModuleSelected;
  final ValueChanged<ComponentTypeSpec> onAdd;
  final ValueChanged<ComponentInstance> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(ComponentInstance component, bool visible)
  onVisibilityChanged;
  final ValueChanged<ComponentInstance> onComponentChanged;
  final ValueChanged<Dashboard> onDashboardChanged;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final ActionRegistry actionRegistry;

  VfdPalette get _palette =>
      VfdPalette.of(dashboard.settings.opticalProfile.phosphor);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF050807),
        border: Border(
          left: BorderSide(color: _palette.unlit.withValues(alpha: 0.28)),
        ),
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
  }

  Widget _listHeader() => Padding(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        VfdLegend('Components', palette: _palette, lit: true, size: 12),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            PopupMenuButton<ComponentTypeSpec>(
              tooltip: 'Add component',
              onSelected: onAdd,
              itemBuilder: (context) => <PopupMenuEntry<ComponentTypeSpec>>[
                for (final type in ComponentTypes.all)
                  PopupMenuItem(value: type, child: Text(type.displayName)),
              ],
              child: IgnorePointer(
                child: PrismButton(
                  label: 'Add component',
                  palette: _palette,
                  role: PrismRole.compact,
                  span: PrismSpan.two,
                  style: dashboard.settings.prismStyle,
                  onPressed: () {},
                ),
              ),
            ),
            const SizedBox(width: 8),
            PrismButton(
              label: 'Add module',
              palette: _palette,
              role: PrismRole.compact,
              span: PrismSpan.two,
              style: dashboard.settings.prismStyle,
              soundEnabled: soundEnabled,
              hapticsEnabled: hapticsEnabled,
              onPressed: _addModule,
            ),
          ],
        ),
        if (dashboard.modules.length > 1) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final module in dashboard.modules)
                PrismButton(
                  label: module.name,
                  value: module.id == kMainVfdModuleId ? 'Default' : module.id,
                  palette: _palette,
                  lit: module.id == selectedModuleId,
                  selected: module.id == selectedModuleId,
                  role: PrismRole.compact,
                  span: PrismSpan.two,
                  style: dashboard.settings.prismStyle,
                  soundEnabled: soundEnabled,
                  hapticsEnabled: hapticsEnabled,
                  onPressed: () => onModuleSelected(module.id),
                ),
              for (final module in dashboard.modules.where(
                (value) => value.id != kMainVfdModuleId,
              ))
                PrismButton(
                  label: 'Remove ${module.name}',
                  palette: _palette,
                  role: PrismRole.compact,
                  span: PrismSpan.three,
                  style: dashboard.settings.prismStyle,
                  soundEnabled: soundEnabled,
                  hapticsEnabled: hapticsEnabled,
                  onPressed: () =>
                      onDashboardChanged(dashboard.withoutModule(module.id)),
                ),
            ],
          ),
        ],
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
    return Padding(
      key: ValueKey(component.id),
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      child: Row(
        children: <Widget>[
          ReorderableDragStartListener(
            index: index,
            child: PrismButton(
              label: 'Move',
              palette: _palette,
              role: PrismRole.compact,
              span: PrismSpan.one,
              style: dashboard.settings.prismStyle,
              onPressed: () {},
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: PrismButton(
              label: name,
              value: component.id,
              palette: _palette,
              lit: component.id == selectedId,
              selected: component.id == selectedId,
              role: PrismRole.compact,
              span: PrismSpan.two,
              style: dashboard.settings.prismStyle,
              soundEnabled: soundEnabled,
              hapticsEnabled: hapticsEnabled,
              onPressed: () => onSelected(component.id),
            ),
          ),
          const SizedBox(width: 6),
          PrismButton(
            label: visible ? 'On' : 'Off',
            palette: _palette,
            lit: visible,
            role: PrismRole.compact,
            span: PrismSpan.one,
            style: dashboard.settings.prismStyle,
            soundEnabled: soundEnabled,
            hapticsEnabled: hapticsEnabled,
            onPressed: () => onVisibilityChanged(component, !visible),
          ),
          const SizedBox(width: 6),
          PrismButton(
            label: 'Remove',
            palette: _palette,
            role: PrismRole.compact,
            span: PrismSpan.one,
            style: dashboard.settings.prismStyle,
            soundEnabled: soundEnabled,
            hapticsEnabled: hapticsEnabled,
            onPressed: () => onRemove(component),
          ),
        ],
      ),
    );
  }

  void _addModule() {
    var index = 2;
    var id = 'module-$index';
    final ids = dashboard.modules.map((module) => module.id).toSet();
    while (ids.contains(id)) {
      id = 'module-${++index}';
    }
    onDashboardChanged(
      dashboard.withModule(
        VfdModule(
          id: id,
          name: 'VFD module $index',
          regions: <DesignOrientation, Placement>{
            orientation: const Placement(size: Size(1, 0.5)),
          },
        ),
      ),
    );
    onModuleSelected(id);
  }

  Widget _inspector() {
    final component = _selectedComponent();
    if (component == null) {
      final selectedModule = _selectedModule();
      if (selectedModule != null) {
        final region = selectedModule.regionIn(orientation);
        return ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            if (selectedModule.id != kMainVfdModuleId)
              SwitchListTile(
                title: Text('Module region in ${orientation.name}'),
                subtitle: const Text(
                  'Region owns physical glass grain and filament geometry.',
                ),
                value: region != null,
                onChanged: (visible) {
                  final regions = <DesignOrientation, Placement>{
                    ...selectedModule.regions,
                  };
                  if (visible) {
                    regions[orientation] = const Placement(size: Size(1, 0.5));
                  } else {
                    regions.remove(orientation);
                  }
                  onDashboardChanged(
                    dashboard.withModule(
                      selectedModule.copyWith(regions: regions),
                    ),
                  );
                },
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<VariantReference>(
                initialValue: selectedModule.filamentVariant,
                decoration: const InputDecoration(
                  labelText: 'Filament geometry',
                ),
                items: <DropdownMenuItem<VariantReference>>[
                  if (FilamentVariants.byReference(
                        selectedModule.filamentVariant,
                      ) ==
                      null)
                    DropdownMenuItem(
                      value: selectedModule.filamentVariant,
                      child: Text(
                        'Missing: ${selectedModule.filamentVariant.id} '
                        '· r${selectedModule.filamentVariant.revision}',
                      ),
                    ),
                  for (final variant in FilamentVariants.all)
                    DropdownMenuItem(
                      value: variant.reference,
                      child: Text(
                        '${variant.displayName} '
                        '· r${variant.reference.revision}',
                      ),
                    ),
                ],
                onChanged: (reference) {
                  if (reference == null) return;
                  onDashboardChanged(
                    dashboard.withModule(
                      selectedModule.copyWith(filamentVariant: reference),
                    ),
                  );
                },
              ),
            ),
            EffectPanel(
              title: '${selectedModule.name} · Module effects',
              dashboardProfile: dashboard.settings.opticalProfile,
              baseProfile: dashboard.settings.opticalProfile,
              overrides: selectedModule.opticalOverrides,
              scope: EffectScope.module,
              prismStyle: dashboard.settings.prismStyle,
              soundEnabled: soundEnabled,
              hapticsEnabled: hapticsEnabled,
              onOverridesChanged: (overrides) => onDashboardChanged(
                dashboard.withModule(
                  selectedModule.copyWith(opticalOverrides: overrides),
                ),
              ),
            ),
          ],
        );
      }
      return ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          EffectPanel(
            title: 'Design effects',
            dashboardProfile: dashboard.settings.opticalProfile,
            baseProfile: dashboard.settings.opticalProfile,
            scope: EffectScope.dashboard,
            prismStyle: dashboard.settings.prismStyle,
            soundEnabled: soundEnabled,
            hapticsEnabled: hapticsEnabled,
            onProfileChanged: (profile) => onDashboardChanged(
              dashboard.copyWith(
                settings: dashboard.settings.copyWith(opticalProfile: profile),
              ),
            ),
          ),
          PrismStyleEditor(
            profile: dashboard.settings.opticalProfile,
            style: dashboard.settings.prismStyle,
            soundEnabled: soundEnabled,
            hapticsEnabled: hapticsEnabled,
            onChanged: (style) => onDashboardChanged(
              dashboard.copyWith(
                settings: dashboard.settings.copyWith(prismStyle: style),
              ),
            ),
          ),
        ],
      );
    }
    final module = dashboard.moduleFor(component);
    final inherited = dashboard.settings.opticalProfile.apply(
      module.opticalOverrides,
    );
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        _ComponentInspector(
          component: component,
          dashboard: dashboard,
          orientation: orientation,
          aspect: dashboard.frameAspect(orientation),
          onVisibilityChanged: (visible) =>
              onVisibilityChanged(component, visible),
          onChanged: onComponentChanged,
          onDashboardChanged: onDashboardChanged,
          actionRegistry: actionRegistry,
        ),
        EffectPanel(
          title:
              '${ComponentTypes.byId(component.typeId)?.displayName ?? component.typeId} · Local effects',
          dashboardProfile: dashboard.settings.opticalProfile,
          baseProfile: inherited,
          overrides: component.opticalOverrides,
          scope: EffectScope.component,
          prismStyle: dashboard.settings.prismStyle,
          soundEnabled: soundEnabled,
          hapticsEnabled: hapticsEnabled,
          onOverridesChanged: (overrides) =>
              onComponentChanged(component.withOpticalOverrides(overrides)),
        ),
      ],
    );
  }

  ComponentInstance? _selectedComponent() {
    for (final component in dashboard.components) {
      if (component.id == selectedId) return component;
    }
    return null;
  }

  VfdModule? _selectedModule() {
    for (final module in dashboard.modules) {
      if (module.id == selectedModuleId) return module;
    }
    return null;
  }
}

class _ComponentInspector extends StatelessWidget {
  const _ComponentInspector({
    required this.component,
    required this.dashboard,
    required this.orientation,
    required this.aspect,
    required this.onVisibilityChanged,
    required this.onChanged,
    required this.onDashboardChanged,
    required this.actionRegistry,
  });

  final ComponentInstance component;
  final Dashboard dashboard;
  final DesignOrientation orientation;
  final double aspect;
  final ValueChanged<bool> onVisibilityChanged;
  final ValueChanged<ComponentInstance> onChanged;
  final ValueChanged<Dashboard> onDashboardChanged;
  final ActionRegistry actionRegistry;

  @override
  Widget build(BuildContext context) {
    final type = ComponentTypes.byId(component.typeId);
    final placement = component.placements[orientation];
    return Padding(
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
            ..._variantControls(type, placement),
            _moduleControl(),
            if (component.typeId == ComponentTypes.prismButton)
              _actionControl(context),
            const Divider(),
            Text('Parameters', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            ParamEditor(
              specs: type.paramsFor(component.effectiveVariant),
              values: component.effectiveParams,
              onChanged: (key, value) =>
                  onChanged(component.withParam(key, value)),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _variantControls(ComponentTypeSpec type, Placement? placement) {
    final known = type.variant(component.effectiveVariant);
    final variants = <ComponentVariantSpec>[
      ...type.availableVariants,
      if (known != null &&
          known.deprecated &&
          !type.availableVariants.contains(known))
        known,
      if (known == null)
        ComponentVariantSpec(
          reference: component.effectiveVariant,
          displayName: 'Missing: ${component.effectiveVariant.id}',
          recommendedSize: type.defaultSize,
          deprecated: true,
        ),
    ];
    return <Widget>[
      DropdownButtonFormField<VariantReference>(
        initialValue: component.effectiveVariant,
        decoration: const InputDecoration(labelText: 'Design variant'),
        items: <DropdownMenuItem<VariantReference>>[
          for (final variant in variants)
            DropdownMenuItem(
              value: variant.reference,
              child: Text(
                '${variant.displayName} · r${variant.reference.revision}',
              ),
            ),
        ],
        onChanged: (reference) {
          if (reference != null) {
            onChanged(component.copyWith(variant: reference));
          }
        },
      ),
      if (placement != null) ...<Widget>[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () {
              final variant =
                  type.variant(component.effectiveVariant) ??
                  type.legacyVariantSpec;
              onChanged(
                component.withPlacement(
                  orientation,
                  placement.copyWith(size: variant.recommendedSize),
                ),
              );
            },
            child: const Text('RESET TO VARIANT SIZE'),
          ),
        ),
      ],
      const SizedBox(height: 12),
    ];
  }

  Widget _moduleControl() => DropdownButtonFormField<String>(
    initialValue: component.moduleId,
    decoration: const InputDecoration(labelText: 'VFD module'),
    items: <DropdownMenuItem<String>>[
      if (!dashboard.modules.any((module) => module.id == component.moduleId))
        DropdownMenuItem(
          value: component.moduleId,
          child: Text('Missing: ${component.moduleId}'),
        ),
      for (final module in dashboard.modules)
        DropdownMenuItem(value: module.id, child: Text(module.name)),
    ],
    onChanged: (moduleId) {
      if (moduleId != null) {
        onChanged(component.copyWith(moduleId: moduleId));
      }
    },
  );

  Widget _actionControl(BuildContext context) {
    final binding = component.actionBinding;
    final registered = binding == null
        ? null
        : actionRegistry[binding.actionId];
    final unknown = binding != null && registered == null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DropdownButtonFormField<String>(
            initialValue: binding?.actionId ?? '',
            decoration: const InputDecoration(labelText: 'Action'),
            items: <DropdownMenuItem<String>>[
              const DropdownMenuItem(value: '', child: Text('No action')),
              if (unknown)
                DropdownMenuItem(
                  value: binding.actionId,
                  child: Text('Unavailable: ${binding.actionId}'),
                ),
              for (final action in actionRegistry.actions)
                DropdownMenuItem(
                  value: action.spec.id,
                  child: Text(
                    action.available
                        ? action.spec.label
                        : '${action.spec.label} · unavailable',
                  ),
                ),
            ],
            onChanged: (actionId) {
              onChanged(
                component.withAction(
                  actionId == null || actionId.isEmpty
                      ? null
                      : ActionBinding(actionId: actionId),
                ),
              );
            },
          ),
          if (registered?.unavailableReason case final reason?) ...<Widget>[
            const SizedBox(height: 8),
            Text(reason, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (registered != null && registered.spec.params.isNotEmpty) ...[
            const SizedBox(height: 12),
            ParamEditor(
              specs: registered.spec.params,
              values: binding?.params ?? const <String, Object?>{},
              onChanged: (key, value) => onChanged(
                component.withAction(
                  ActionBinding(
                    actionId: registered.spec.id,
                    params: <String, Object?>{...?binding?.params, key: value},
                  ),
                ),
              ),
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
    final size = placement.resolveSize(
      ComponentTypes.byId(component.typeId),
      variant: component.effectiveVariant,
    );
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
