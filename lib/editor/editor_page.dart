import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../actions/action_registry.dart';
import '../mechanical/mechanical_pager.dart';
import '../mechanical/mechanical_push_drawer.dart';
import '../mechanical/prism_selector_bank.dart';
import '../mechanical/vfd_editable_field.dart';
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
import 'placement_transform.dart';

enum _EditorSection { rack, design, part, module, optics, prism, place }

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.dashboard,
    required this.onChanged,
    this.renderAssets,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.actionRegistry,
  });

  final Dashboard dashboard;
  final ValueChanged<Dashboard> onChanged;
  final VfdRenderAssets? renderAssets;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final ActionRegistry? actionRegistry;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late Dashboard _dashboard = widget.dashboard;
  late DesignOrientation _orientation = _dashboard.primaryOrientation;
  bool _initialOrientationResolved = false;
  String? _selectedId;
  String? _selectedModuleId;
  bool _drawerOpen = false;
  bool _fullScreen = false;

  VfdPalette get _palette =>
      VfdPalette.of(_dashboard.settings.opticalProfile.phosphor);
  DesignOrientation get _layoutOrientation =>
      _dashboard.layoutForViewport(_orientation);
  bool get _layoutInherited => _layoutOrientation != _orientation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialOrientationResolved) return;
    _initialOrientationResolved = true;
    final size = MediaQuery.sizeOf(context);
    final current = size.width > size.height
        ? DesignOrientation.landscape
        : DesignOrientation.portrait;
    _orientation = current;
  }

  /// The device's own safe rect. Read here, above this route's `SafeArea`,
  /// which would otherwise have consumed the padding. `CREATE` and the
  /// read-only preview both size their envelope from it, so neither depends on
  /// how much room the editor chrome happens to leave.
  Size get _deviceSafeSize {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    return Size(
      math.max(1, size.width - padding.horizontal),
      math.max(1, size.height - padding.vertical),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_fullScreen) {
      return ColoredBox(
        color: const Color(0xFF050807),
        child: _canvas(frameInset: MediaQuery.paddingOf(context)),
      );
    }
    return ColoredBox(
      color: const Color(0xFF050807),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(height: 48, child: _topRail(context)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _workspace(constraints),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topRail(BuildContext context) => PrismPanel(
    palette: _palette,
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    child: Row(
      children: <Widget>[
        PrismButton(
          label: 'Back',
          palette: _palette,
          role: PrismRole.compact,
          style: _dashboard.settings.prismStyle,
          soundEnabled: widget.soundEnabled,
          hapticsEnabled: widget.hapticsEnabled,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: VfdLegend(
            _dashboard.name,
            palette: _palette,
            lit: true,
            size: 12,
          ),
        ),
        for (final value in DesignOrientation.values) ...<Widget>[
          PrismButton(
            key: ValueKey('orientation-${value.name}'),
            label: value.name,
            palette: _palette,
            lit: value == _orientation,
            selected: value == _orientation,
            role: PrismRole.compact,
            style: _dashboard.settings.prismStyle,
            soundEnabled: widget.soundEnabled,
            hapticsEnabled: widget.hapticsEnabled,
            onPressed: () => setState(() {
              _orientation = value;
              _selectedId = null;
              _selectedModuleId = null;
            }),
          ),
          const SizedBox(width: 4),
        ],
      ],
    ),
  );

  Widget _canvas({EdgeInsets frameInset = const EdgeInsets.all(24)}) =>
      EditorCanvas(
        dashboard: _dashboard,
        orientation: _layoutOrientation,
        previewOrientation: _orientation,
        editable: !_layoutInherited,
        deviceSafeSize: _deviceSafeSize,
        selectedId: _selectedId,
        selectedModuleId: _selectedModuleId,
        onSelect: _selectComponent,
        onPlacementChanged: _setPlacement,
        onModulePlacementChanged: _setModulePlacement,
        renderAssets: widget.renderAssets,
        frameInset: frameInset,
        fullScreen: _fullScreen,
        onToggleFullScreen: () =>
            setState(() => _fullScreen = !_fullScreen),
      );

  Widget _workspace(BoxConstraints constraints) {
    final layout = _WorkspaceLayout.resolve(
      portrait: _orientation == DesignOrientation.portrait,
      constraints: constraints,
    );
    final canvas = Padding(
      padding: const EdgeInsets.all(4),
      child: _canvas(),
    );
    return MechanicalPushDrawer(
      key: const ValueKey('editor-workspace'),
      open: _drawerOpen,
      edge: layout.edge,
      extent: layout.drawerExtent,
      palette: _palette,
      soundEnabled: widget.soundEnabled,
      hapticsEnabled: widget.hapticsEnabled,
      onOpenChanged: (open) => setState(() => _drawerOpen = open),
      content: canvas,
      drawer: _EditorServicePanel(
        dashboard: _dashboard,
        orientation: _layoutOrientation,
        previewOrientation: _orientation,
        layoutInherited: _layoutInherited,
        frameExtent: _dashboard.frameExtent(_layoutOrientation),
        selectedId: _selectedId,
        selectedModuleId: _selectedModuleId,
        palette: _palette,
        soundEnabled: widget.soundEnabled,
        hapticsEnabled: widget.hapticsEnabled,
        actionRegistry: widget.actionRegistry ?? ActionRegistry.forAuthoring(),
        onSelectComponent: _selectComponent,
        onSelectModule: _selectModule,
        onAddComponent: _addComponent,
        onAddModule: _addModule,
        onRemoveComponent: _removeComponent,
        onRemoveModule: _removeModule,
        onMoveComponent: _moveComponent,
        onVisibilityChanged: _setVisibility,
        onComponentChanged: _replaceComponent,
        onDashboardChanged: _replaceDashboard,
        onFrameExtentChanged: _setFrameExtent,
        onCreateLayout: _createPreviewLayout,
        onRemoveLayout: _removePreviewLayout,
        onPlacementChanged: _setPlacement,
        onModulePlacementChanged: _setModulePlacement,
      ),
    );
  }

  void _selectComponent(String? id) => setState(() {
    _selectedId = id;
    _selectedModuleId = null;
  });

  void _selectModule(String id) => setState(() {
    _selectedId = null;
    _selectedModuleId = id;
  });

  void _setFrameExtent(Size value) {
    if (_layoutInherited) return;
    final next = FrameSpec(width: value.width, height: value.height);
    if (!next.isValid) return;
    _replaceDashboard(
      _dashboard.copyWith(
        frameSpecs: <DesignOrientation, FrameSpec>{
          ..._dashboard.frameSpecs,
          _layoutOrientation: next,
        },
      ),
    );
  }

  void _createPreviewLayout() {
    if (!_layoutInherited) return;
    _replaceDashboard(
      _dashboard.withBakedLayout(
        _orientation,
        // Same function the read-only preview draws with, so what was on screen
        // is what becomes authored.
        extent: viewportFrameExtent(
          _orientation,
          _deviceSafeSize,
          _dashboard.frameSpec(_layoutOrientation),
        ),
      ),
    );
  }

  void _removePreviewLayout() {
    if (_orientation == _dashboard.primaryOrientation) return;
    _replaceDashboard(_dashboard.withoutLayout(_orientation));
    _selectComponent(null);
  }

  void _setPlacement(String id, Placement placement) {
    final component = _component(id);
    if (component != null) {
      _replaceComponent(component.withPlacement(_layoutOrientation, placement));
    }
  }

  void _setModulePlacement(String id, Placement placement) {
    final module = _module(id);
    if (module == null || id == kMainVfdModuleId) return;
    _replaceDashboard(
      _dashboard.withModule(
        module.copyWith(
          regions: <DesignOrientation, Placement>{
            ...module.regions,
            _layoutOrientation: placement,
          },
        ),
      ),
    );
  }

  void _setVisibility(ComponentInstance component, bool visible) {
    final existing = component.placements[_layoutOrientation];
    _replaceComponent(
      component.withPlacement(
        _layoutOrientation,
        visible ? (existing ?? const Placement()) : null,
      ),
    );
  }

  void _addComponent(ComponentTypeSpec type) {
    final component = ComponentInstance(
      id: _nextComponentId(type.id),
      typeId: type.id,
      params: type.defaults,
      placements: <DesignOrientation, Placement>{
        _layoutOrientation: const Placement(),
      },
    );
    _replaceDashboard(_dashboard.withComponent(component));
    _selectComponent(component.id);
  }

  void _addModule() {
    var index = 2;
    var id = 'module-$index';
    final ids = _dashboard.modules.map((module) => module.id).toSet();
    while (ids.contains(id)) {
      id = 'module-${++index}';
    }
    final module = VfdModule(
      id: id,
      name: 'VFD module $index',
      regions: <DesignOrientation, Placement>{
        _layoutOrientation: const Placement(size: Size(1, 0.5)),
      },
    );
    _replaceDashboard(_dashboard.withModule(module));
    _selectModule(id);
  }

  void _removeComponent(ComponentInstance component) {
    _replaceDashboard(_dashboard.withoutComponent(component.id));
    _selectComponent(null);
  }

  void _removeModule(VfdModule module) {
    _replaceDashboard(_dashboard.withoutModule(module.id));
    _selectModule(kMainVfdModuleId);
  }

  void _moveComponent(ComponentInstance component, int delta) {
    final from = _dashboard.components.indexOf(component);
    final to = (from + delta).clamp(0, _dashboard.components.length - 1);
    if (to != from) {
      _replaceDashboard(_dashboard.reorderComponent(from, to));
    }
  }

  void _replaceComponent(ComponentInstance component) =>
      _replaceDashboard(_dashboard.withComponent(component));

  void _replaceDashboard(Dashboard next) {
    setState(() {
      _dashboard = next;
      if (next.layoutForViewport(_orientation) != _orientation) {
        _selectedId = null;
        _selectedModuleId = null;
      }
    });
    widget.onChanged(next);
  }

  ComponentInstance? _component(String id) =>
      _dashboard.components.where((item) => item.id == id).firstOrNull;

  VfdModule? _module(String id) =>
      _dashboard.modules.where((item) => item.id == id).firstOrNull;

  String _nextComponentId(String typeId) {
    var index = 1;
    var candidate = '$typeId-$index';
    final ids = _dashboard.components.map((item) => item.id).toSet();
    while (ids.contains(candidate)) {
      candidate = '$typeId-${++index}';
    }
    return candidate;
  }
}

/// Where the service bay enters from and how much room it takes.
///
/// Portrait and landscape keep their own numbers — a bay that pushes up wants a
/// different reserve from one that pushes in from the side — but every other
/// part of the editor is shape-agnostic, so this is the only branch.
class _WorkspaceLayout {
  const _WorkspaceLayout({required this.edge, required this.drawerExtent});

  final MechanicalDrawerEdge edge;
  final double drawerExtent;

  static _WorkspaceLayout resolve({
    required bool portrait,
    required BoxConstraints constraints,
  }) {
    if (portrait) {
      final maxExtent = math.max(160.0, constraints.maxHeight - 120);
      return _WorkspaceLayout(
        edge: MechanicalDrawerEdge.bottom,
        drawerExtent: math.min(
          maxExtent,
          (constraints.maxHeight * 0.42).clamp(220, 420).toDouble(),
        ),
      );
    }
    final maxExtent = math.max(240.0, constraints.maxWidth - 60);
    return _WorkspaceLayout(
      edge: MechanicalDrawerEdge.right,
      drawerExtent: math.min(
        maxExtent,
        (constraints.maxWidth * 0.38).clamp(280, 420).toDouble(),
      ),
    );
  }
}

class _EditorServicePanel extends StatefulWidget {
  const _EditorServicePanel({
    required this.dashboard,
    required this.orientation,
    required this.previewOrientation,
    required this.layoutInherited,
    required this.frameExtent,
    required this.selectedId,
    required this.selectedModuleId,
    required this.palette,
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.actionRegistry,
    required this.onSelectComponent,
    required this.onSelectModule,
    required this.onAddComponent,
    required this.onAddModule,
    required this.onRemoveComponent,
    required this.onRemoveModule,
    required this.onMoveComponent,
    required this.onVisibilityChanged,
    required this.onComponentChanged,
    required this.onDashboardChanged,
    required this.onFrameExtentChanged,
    required this.onCreateLayout,
    required this.onRemoveLayout,
    required this.onPlacementChanged,
    required this.onModulePlacementChanged,
  });

  final Dashboard dashboard;
  final DesignOrientation orientation;
  final DesignOrientation previewOrientation;
  final bool layoutInherited;
  final Size frameExtent;
  final String? selectedId;
  final String? selectedModuleId;
  final VfdPalette palette;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final ActionRegistry actionRegistry;
  final ValueChanged<String?> onSelectComponent;
  final ValueChanged<String> onSelectModule;
  final ValueChanged<ComponentTypeSpec> onAddComponent;
  final VoidCallback onAddModule;
  final ValueChanged<ComponentInstance> onRemoveComponent;
  final ValueChanged<VfdModule> onRemoveModule;
  final void Function(ComponentInstance component, int delta) onMoveComponent;
  final void Function(ComponentInstance component, bool visible)
  onVisibilityChanged;
  final ValueChanged<ComponentInstance> onComponentChanged;
  final ValueChanged<Dashboard> onDashboardChanged;
  final ValueChanged<Size> onFrameExtentChanged;
  final VoidCallback onCreateLayout;
  final VoidCallback onRemoveLayout;
  final void Function(String id, Placement placement) onPlacementChanged;
  final void Function(String id, Placement placement) onModulePlacementChanged;

  @override
  State<_EditorServicePanel> createState() => _EditorServicePanelState();
}

class _EditorServicePanelState extends State<_EditorServicePanel> {
  _EditorSection _section = _EditorSection.rack;

  List<_EditorSection> get _sections {
    if (widget.layoutInherited) {
      return const <_EditorSection>[
        _EditorSection.design,
        _EditorSection.optics,
        _EditorSection.prism,
      ];
    }
    if (widget.selectedId != null) {
      return const <_EditorSection>[
        _EditorSection.rack,
        _EditorSection.part,
        _EditorSection.optics,
        _EditorSection.place,
      ];
    }
    if (widget.selectedModuleId != null) {
      return const <_EditorSection>[
        _EditorSection.rack,
        _EditorSection.module,
        _EditorSection.optics,
        _EditorSection.place,
      ];
    }
    return const <_EditorSection>[
      _EditorSection.rack,
      _EditorSection.design,
      _EditorSection.optics,
      _EditorSection.prism,
    ];
  }

  @override
  void didUpdateWidget(covariant _EditorServicePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sections.contains(_section)) _section = _EditorSection.rack;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Builder(
      builder: (context) {
        final sections = _sections;
        final active = sections.contains(_section) ? _section : sections.first;
        _section = active;
        return Column(
          children: <Widget>[
            PrismSelectorBank<_EditorSection>(
              choices: <PrismSelectorChoice<_EditorSection>>[
                for (final section in sections)
                  PrismSelectorChoice<_EditorSection>(
                    value: section,
                    label: section.name,
                    lit: section == active,
                  ),
              ],
              selected: active,
              palette: widget.palette,
              prismStyle: widget.dashboard.settings.prismStyle,
              rows: 1,
              role: PrismRole.compact,
              soundEnabled: widget.soundEnabled,
              hapticsEnabled: widget.hapticsEnabled,
              semanticLabel: 'Editor service section',
              onSelected: (section) => setState(() => _section = section),
            ),
            const SizedBox(height: 8),
            Expanded(child: _sectionBody(active)),
          ],
        );
      },
    ),
  );

  Widget _sectionBody(_EditorSection section) => switch (section) {
    _EditorSection.rack => _RackPanel(host: widget),
    _EditorSection.design => _DesignPanel(host: widget),
    _EditorSection.part => _PartPanel(host: widget),
    _EditorSection.module => _ModulePanel(host: widget),
    _EditorSection.optics => _optics(),
    _EditorSection.prism => PrismStyleEditor(
      profile: widget.dashboard.settings.opticalProfile,
      style: widget.dashboard.settings.prismStyle,
      soundEnabled: widget.soundEnabled,
      hapticsEnabled: widget.hapticsEnabled,
      onChanged: (style) => widget.onDashboardChanged(
        widget.dashboard.copyWith(
          settings: widget.dashboard.settings.copyWith(prismStyle: style),
        ),
      ),
    ),
    _EditorSection.place => _PlacementPanel(host: widget),
  };

  Widget _optics() {
    final component = _selectedComponent;
    if (component != null) {
      final module = widget.dashboard.moduleFor(component);
      final inherited = widget.dashboard.settings.opticalProfile.apply(
        module.opticalOverrides,
      );
      return EffectPanel(
        title:
            '${ComponentTypes.byId(component.typeId)?.displayName ?? component.typeId} · Local effects',
        dashboardProfile: widget.dashboard.settings.opticalProfile,
        baseProfile: inherited,
        overrides: component.opticalOverrides,
        scope: EffectScope.component,
        prismStyle: widget.dashboard.settings.prismStyle,
        soundEnabled: widget.soundEnabled,
        hapticsEnabled: widget.hapticsEnabled,
        onOverridesChanged: (value) =>
            widget.onComponentChanged(component.withOpticalOverrides(value)),
      );
    }
    final module = _selectedModule;
    if (module != null) {
      return EffectPanel(
        title: '${module.name} · Module effects',
        dashboardProfile: widget.dashboard.settings.opticalProfile,
        baseProfile: widget.dashboard.settings.opticalProfile,
        overrides: module.opticalOverrides,
        scope: EffectScope.module,
        prismStyle: widget.dashboard.settings.prismStyle,
        soundEnabled: widget.soundEnabled,
        hapticsEnabled: widget.hapticsEnabled,
        onOverridesChanged: (value) => widget.onDashboardChanged(
          widget.dashboard.withModule(module.copyWith(opticalOverrides: value)),
        ),
      );
    }
    return EffectPanel(
      title: 'Design effects',
      dashboardProfile: widget.dashboard.settings.opticalProfile,
      baseProfile: widget.dashboard.settings.opticalProfile,
      scope: EffectScope.dashboard,
      prismStyle: widget.dashboard.settings.prismStyle,
      soundEnabled: widget.soundEnabled,
      hapticsEnabled: widget.hapticsEnabled,
      onProfileChanged: (profile) => widget.onDashboardChanged(
        widget.dashboard.copyWith(
          settings: widget.dashboard.settings.copyWith(opticalProfile: profile),
        ),
      ),
    );
  }

  ComponentInstance? get _selectedComponent => widget.dashboard.components
      .where((item) => item.id == widget.selectedId)
      .firstOrNull;

  VfdModule? get _selectedModule => widget.dashboard.modules
      .where((item) => item.id == widget.selectedModuleId)
      .firstOrNull;
}

class _RackPanel extends StatefulWidget {
  const _RackPanel({required this.host});

  final _EditorServicePanel host;

  @override
  State<_RackPanel> createState() => _RackPanelState();
}

class _RackPanelState extends State<_RackPanel> {
  bool _addingComponent = false;
  bool _addingModule = false;

  _EditorServicePanel get host => widget.host;

  @override
  Widget build(BuildContext context) => PrismPanel(
    palette: host.palette,
    padding: const EdgeInsets.all(9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        VfdLegend('Rack', palette: host.palette, lit: true, size: 12),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final rows = ((constraints.maxHeight + 6) / 50).floor().clamp(
                1,
                4,
              );
              return _rackContent(rows);
            },
          ),
        ),
        const SizedBox(height: 8),
        _selectedActions(),
        const SizedBox(height: 7),
        Row(
          children: <Widget>[
            Expanded(child: _addButton('Add part', true)),
            const SizedBox(width: 6),
            Expanded(child: _addButton('Add module', false)),
          ],
        ),
      ],
    ),
  );

  Widget _rackContent(int rows) {
    if (_addingComponent) {
      return PrismSelectorBank<ComponentTypeSpec>(
        choices: <PrismSelectorChoice<ComponentTypeSpec>>[
          for (final type in ComponentTypes.all)
            PrismSelectorChoice<ComponentTypeSpec>(
              value: type,
              label: type.displayName,
            ),
        ],
        selected: null,
        palette: host.palette,
        prismStyle: host.dashboard.settings.prismStyle,
        rows: rows,
        soundEnabled: host.soundEnabled,
        hapticsEnabled: host.hapticsEnabled,
        semanticLabel: 'Add component',
        onSelected: (type) {
          host.onAddComponent(type);
          setState(() => _addingComponent = false);
        },
      );
    }
    if (_addingModule) {
      return PrismSelectorBank<String>(
        choices: const <PrismSelectorChoice<String>>[
          PrismSelectorChoice<String>(value: 'vfd', label: 'VFD module'),
        ],
        selected: null,
        palette: host.palette,
        prismStyle: host.dashboard.settings.prismStyle,
        rows: 1,
        soundEnabled: host.soundEnabled,
        hapticsEnabled: host.hapticsEnabled,
        semanticLabel: 'Add module',
        onSelected: (_) {
          host.onAddModule();
          setState(() => _addingModule = false);
        },
      );
    }
    final items = <_RackItem>[
      for (final component in host.dashboard.components)
        _RackItem.component(component),
      if (host.dashboard.modules.length > 1)
        for (final module in host.dashboard.modules) _RackItem.module(module),
    ];
    if (items.isEmpty) {
      return VfdLegend('Rack empty', palette: host.palette, size: 10);
    }
    return PrismSelectorBank<_RackItem>(
      choices: <PrismSelectorChoice<_RackItem>>[
        for (final item in items)
          PrismSelectorChoice<_RackItem>(
            value: item,
            label: item.label,
            lit: item.visibleIn(host.orientation),
          ),
      ],
      selected: items.where((item) => item.isSelected(host)).firstOrNull,
      palette: host.palette,
      prismStyle: host.dashboard.settings.prismStyle,
      rows: rows,
      soundEnabled: host.soundEnabled,
      hapticsEnabled: host.hapticsEnabled,
      semanticLabel: 'Rack items',
      onSelected: (item) => item.select(host),
    );
  }

  Widget _selectedActions() {
    final component = host.dashboard.components
        .where((item) => item.id == host.selectedId)
        .firstOrNull;
    final module = host.dashboard.modules
        .where((item) => item.id == host.selectedModuleId)
        .firstOrNull;
    if (component == null && module == null) {
      return SizedBox(
        height: PrismMetrics.height(PrismRole.compact),
        child: VfdLegend('Select rack item', palette: host.palette, size: 9),
      );
    }
    final visible =
        component?.appearsIn(host.orientation) ??
        (module?.regionIn(host.orientation) != null);
    return Row(
      children: <Widget>[
        if (component != null) ...<Widget>[
          _action('Up', () => host.onMoveComponent(component, -1)),
          const SizedBox(width: 4),
          _action('Down', () => host.onMoveComponent(component, 1)),
          const SizedBox(width: 4),
        ],
        _action(
          visible ? 'Visible' : 'Hidden',
          component != null
              ? () => host.onVisibilityChanged(component, !visible)
              : () => _toggleModuleVisibility(module!, visible),
          lit: visible,
        ),
        if (component != null || module?.id != kMainVfdModuleId) ...<Widget>[
          const SizedBox(width: 4),
          _action(
            'Remove',
            component != null
                ? () => host.onRemoveComponent(component)
                : () => host.onRemoveModule(module!),
          ),
        ],
      ],
    );
  }

  Widget _action(String label, VoidCallback onPressed, {bool lit = false}) =>
      Expanded(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: PrismButton(
            label: label,
            palette: host.palette,
            lit: lit,
            role: PrismRole.compact,
            style: host.dashboard.settings.prismStyle,
            soundEnabled: host.soundEnabled,
            hapticsEnabled: host.hapticsEnabled,
            onPressed: onPressed,
          ),
        ),
      );

  Widget _addButton(String label, bool component) => FittedBox(
    fit: BoxFit.scaleDown,
    child: PrismButton(
      label: label,
      palette: host.palette,
      lit: component ? _addingComponent : _addingModule,
      selected: component ? _addingComponent : _addingModule,
      role: PrismRole.compact,
      span: PrismSpan.two,
      style: host.dashboard.settings.prismStyle,
      soundEnabled: host.soundEnabled,
      hapticsEnabled: host.hapticsEnabled,
      onPressed: () => setState(() {
        _addingComponent = component && !_addingComponent;
        _addingModule = !component && !_addingModule;
      }),
    ),
  );

  void _toggleModuleVisibility(VfdModule module, bool visible) {
    final regions = <DesignOrientation, Placement>{...module.regions};
    if (visible) {
      regions.remove(host.orientation);
    } else {
      regions[host.orientation] = const Placement(size: Size(1, 0.5));
    }
    host.onDashboardChanged(
      host.dashboard.withModule(module.copyWith(regions: regions)),
    );
  }
}

class _RackItem {
  const _RackItem._({this.component, this.module});

  factory _RackItem.component(ComponentInstance value) =>
      _RackItem._(component: value);
  factory _RackItem.module(VfdModule value) => _RackItem._(module: value);

  final ComponentInstance? component;
  final VfdModule? module;

  String get label => component == null
      ? module!.name
      : ComponentTypes.byId(component!.typeId)?.displayName ??
            component!.typeId;

  bool visibleIn(DesignOrientation orientation) =>
      component?.appearsIn(orientation) ??
      (module?.regionIn(orientation) != null);

  bool isSelected(_EditorServicePanel host) =>
      component?.id == host.selectedId || module?.id == host.selectedModuleId;

  void select(_EditorServicePanel host) {
    if (component != null) {
      host.onSelectComponent(component!.id);
    } else {
      host.onSelectModule(module!.id);
    }
  }
}

class _DesignPanel extends StatelessWidget {
  const _DesignPanel({required this.host});

  final _EditorServicePanel host;

  @override
  Widget build(BuildContext context) {
    final preview = host.previewOrientation;
    final primary = host.dashboard.primaryOrientation;
    final isPrimary = preview == primary;
    final authored = host.dashboard.hasAuthoredLayout(preview);
    final spec = host.dashboard.frameSpec(preview);
    return PrismPanel(
      palette: host.palette,
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            VfdLegend(
              'Primary · ${primary.name}',
              palette: host.palette,
              lit: true,
              size: 11,
            ),
            const SizedBox(height: 5),
            VfdLegend(
              authored
                  ? '${preview.name} · authored fixed layout'
                  : '${preview.name} · contains ${primary.name}',
              palette: host.palette,
              size: 9,
            ),
            if (!authored && constraints.maxHeight >= 145) ...<Widget>[
              const SizedBox(height: 5),
              VfdLegend(
                'Create copies this appearance into an editable layout.',
                palette: host.palette,
                size: 9,
              ),
            ],
            const Spacer(),
            if (authored)
              Row(
                children: <Widget>[
                  Expanded(
                    child: VfdEditableField(
                      label:
                          'Frame W · ${spec.referenceAspect.toStringAsFixed(3)}:1',
                      value: spec.width.toStringAsFixed(3),
                      palette: host.palette,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) {},
                      onSubmitted: (raw) {
                        final value = double.tryParse(raw);
                        if (value != null) {
                          host.onFrameExtentChanged(
                            Size(value, spec.height),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: VfdEditableField(
                      label: 'Frame H · ${preview.name}',
                      value: spec.height.toStringAsFixed(3),
                      palette: host.palette,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) {},
                      onSubmitted: (raw) {
                        final value = double.tryParse(raw);
                        if (value != null) {
                          host.onFrameExtentChanged(Size(spec.width, value));
                        }
                      },
                    ),
                  ),
                  if (!isPrimary) ...<Widget>[
                    const SizedBox(width: 6),
                    PrismButton(
                      key: const ValueKey('remove-layout'),
                      label: 'Reset',
                      palette: host.palette,
                      role: PrismRole.compact,
                      style: host.dashboard.settings.prismStyle,
                      soundEnabled: host.soundEnabled,
                      hapticsEnabled: host.hapticsEnabled,
                      onPressed: host.onRemoveLayout,
                    ),
                  ],
                ],
              )
            else
              Center(
                child: PrismButton(
                  key: const ValueKey('create-layout'),
                  label: 'Create ${preview.name}',
                  palette: host.palette,
                  lit: true,
                  role: PrismRole.compact,
                  span: PrismSpan.three,
                  style: host.dashboard.settings.prismStyle,
                  soundEnabled: host.soundEnabled,
                  hapticsEnabled: host.hapticsEnabled,
                  onPressed: host.onCreateLayout,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PartPanel extends StatelessWidget {
  const _PartPanel({required this.host});

  final _EditorServicePanel host;

  @override
  Widget build(BuildContext context) {
    final component = host.dashboard.components
        .where((item) => item.id == host.selectedId)
        .firstOrNull;
    final type = component == null
        ? null
        : ComponentTypes.byId(component.typeId);
    if (component == null || type == null) {
      return VfdLegend('No part selected', palette: host.palette);
    }
    return PrismPanel(
      palette: host.palette,
      padding: const EdgeInsets.all(9),
      child: MechanicalPager(
        pages: <Widget>[
          _variant(component, type),
          _module(component),
          if (component.typeId == ComponentTypes.prismButton)
            _action(component),
          ParamEditor(
            specs: type.paramsFor(component.effectiveVariant),
            values: component.effectiveParams,
            palette: host.palette,
            prismStyle: host.dashboard.settings.prismStyle,
            soundEnabled: host.soundEnabled,
            hapticsEnabled: host.hapticsEnabled,
            onChanged: (key, value) =>
                host.onComponentChanged(component.withParam(key, value)),
          ),
        ],
        palette: host.palette,
        prismStyle: host.dashboard.settings.prismStyle,
        soundEnabled: host.soundEnabled,
        hapticsEnabled: host.hapticsEnabled,
        semanticLabel: 'Part controls',
      ),
    );
  }

  Widget _variant(ComponentInstance component, ComponentTypeSpec type) {
    final known = type.variant(component.effectiveVariant);
    final variants = <ComponentVariantSpec>[
      ...type.availableVariants,
      if (known != null && known.deprecated) known,
      if (known == null)
        ComponentVariantSpec(
          reference: component.effectiveVariant,
          displayName: 'Missing ${component.effectiveVariant.id}',
          recommendedSize: type.defaultSize,
          deprecated: true,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        VfdLegend('Variant', palette: host.palette, lit: true, size: 11),
        const SizedBox(height: 8),
        PrismSelectorBank<VariantReference>(
          choices: <PrismSelectorChoice<VariantReference>>[
            for (final variant in variants)
              PrismSelectorChoice<VariantReference>(
                value: variant.reference,
                label: variant.displayName,
                lit: variant.reference == component.effectiveVariant,
              ),
          ],
          selected: component.effectiveVariant,
          palette: host.palette,
          prismStyle: host.dashboard.settings.prismStyle,
          rows: 2,
          soundEnabled: host.soundEnabled,
          hapticsEnabled: host.hapticsEnabled,
          semanticLabel: 'Design variant',
          onSelected: (value) =>
              host.onComponentChanged(component.copyWith(variant: value)),
        ),
        const Spacer(),
        PrismButton(
          label: 'Reset to variant size',
          palette: host.palette,
          role: PrismRole.compact,
          span: PrismSpan.three,
          style: host.dashboard.settings.prismStyle,
          soundEnabled: host.soundEnabled,
          hapticsEnabled: host.hapticsEnabled,
          onPressed: () => _resetSize(component, type),
        ),
      ],
    );
  }

  Widget _module(ComponentInstance component) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      VfdLegend('VFD module', palette: host.palette, lit: true, size: 11),
      const SizedBox(height: 8),
      PrismSelectorBank<String>(
        choices: <PrismSelectorChoice<String>>[
          if (!host.dashboard.modules.any(
            (item) => item.id == component.moduleId,
          ))
            PrismSelectorChoice<String>(
              value: component.moduleId,
              label: 'Missing ${component.moduleId}',
              lit: true,
              enabled: false,
            ),
          for (final module in host.dashboard.modules)
            PrismSelectorChoice<String>(
              value: module.id,
              label: module.name,
              lit: module.id == component.moduleId,
            ),
        ],
        selected: component.moduleId,
        palette: host.palette,
        prismStyle: host.dashboard.settings.prismStyle,
        rows: 2,
        soundEnabled: host.soundEnabled,
        hapticsEnabled: host.hapticsEnabled,
        semanticLabel: 'VFD module',
        onSelected: (id) =>
            host.onComponentChanged(component.copyWith(moduleId: id)),
      ),
    ],
  );

  Widget _action(ComponentInstance component) {
    final selected = component.actionBinding?.actionId ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        VfdLegend('Action', palette: host.palette, lit: true, size: 11),
        const SizedBox(height: 8),
        PrismSelectorBank<String>(
          choices: <PrismSelectorChoice<String>>[
            PrismSelectorChoice<String>(
              value: '',
              label: 'No action',
              lit: selected.isEmpty,
            ),
            if (selected.isNotEmpty && host.actionRegistry[selected] == null)
              PrismSelectorChoice<String>(
                value: selected,
                label: 'Unavailable',
                lit: true,
                enabled: false,
              ),
            for (final action in host.actionRegistry.actions)
              PrismSelectorChoice<String>(
                value: action.spec.id,
                label: action.spec.label,
                lit: action.spec.id == selected,
              ),
          ],
          selected: selected,
          palette: host.palette,
          prismStyle: host.dashboard.settings.prismStyle,
          rows: 3,
          soundEnabled: host.soundEnabled,
          hapticsEnabled: host.hapticsEnabled,
          semanticLabel: 'Action',
          onSelected: (id) => host.onComponentChanged(
            component.withAction(
              id.isEmpty ? null : ActionBinding(actionId: id),
            ),
          ),
        ),
      ],
    );
  }

  void _resetSize(ComponentInstance component, ComponentTypeSpec type) {
    final placement = component.placements[host.orientation];
    if (placement == null) return;
    final variant =
        type.variant(component.effectiveVariant) ?? type.legacyVariantSpec;
    host.onComponentChanged(
      component.withPlacement(
        host.orientation,
        placement.copyWith(size: variant.recommendedSize),
      ),
    );
  }
}

class _ModulePanel extends StatelessWidget {
  const _ModulePanel({required this.host});

  final _EditorServicePanel host;

  @override
  Widget build(BuildContext context) {
    final module = host.dashboard.modules
        .where((item) => item.id == host.selectedModuleId)
        .firstOrNull;
    if (module == null) {
      return VfdLegend('No module selected', palette: host.palette);
    }
    return PrismPanel(
      palette: host.palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          VfdLegend(module.name, palette: host.palette, lit: true, size: 12),
          const SizedBox(height: 10),
          PrismSelectorBank<VariantReference>(
            choices: <PrismSelectorChoice<VariantReference>>[
              if (FilamentVariants.byReference(module.filamentVariant) == null)
                PrismSelectorChoice<VariantReference>(
                  value: module.filamentVariant,
                  label: 'Missing filament',
                  enabled: false,
                ),
              for (final variant in FilamentVariants.all)
                PrismSelectorChoice<VariantReference>(
                  value: variant.reference,
                  label: variant.displayName,
                  lit: variant.reference == module.filamentVariant,
                ),
            ],
            selected: module.filamentVariant,
            palette: host.palette,
            prismStyle: host.dashboard.settings.prismStyle,
            rows: 2,
            soundEnabled: host.soundEnabled,
            hapticsEnabled: host.hapticsEnabled,
            semanticLabel: 'Filament geometry',
            onSelected: (value) => host.onDashboardChanged(
              host.dashboard.withModule(
                module.copyWith(filamentVariant: value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlacementPanel extends StatelessWidget {
  const _PlacementPanel({required this.host});

  final _EditorServicePanel host;
  static const _nudge = 0.005;

  @override
  Widget build(BuildContext context) {
    final component = host.dashboard.components
        .where((item) => item.id == host.selectedId)
        .firstOrNull;
    final module = host.dashboard.modules
        .where((item) => item.id == host.selectedModuleId)
        .firstOrNull;
    final placement =
        component?.placements[host.orientation] ??
        module?.regionIn(host.orientation);
    if (placement == null) {
      return VfdLegend('Not present in orientation', palette: host.palette);
    }
    final type = component == null
        ? null
        : ComponentTypes.byId(component.typeId);
    final frame = host.frameExtent;
    final size = placement.resolveSizeIn(
      frame,
      type,
      variant: component?.effectiveVariant,
    );
    final center = placement.resolve(frame);
    return PrismPanel(
      palette: host.palette,
      padding: const EdgeInsets.all(9),
      child: MechanicalPager(
        pages: <Widget>[
          _anchorPage(placement, frame, component, module),
          _spanPage(placement, frame, size, component, module),
          _recoveryPage(placement, center, component, module),
          _axisPage('X', center.dx, -_nudge, _nudge, (delta) {
            _write(component, module, nudgePlacement(placement, dx: delta));
          }),
          _axisPage('Y', center.dy, -_nudge, _nudge, (delta) {
            _write(component, module, nudgePlacement(placement, dy: delta));
          }),
          _axisPage('W', size.width, -_nudge, _nudge, (delta) {
            _write(
              component,
              module,
              resizePlacementFromEdges(
                placement: placement,
                resolvedSize: size,
                frame: frame,
                widthDelta: delta,
              ),
            );
          }),
          _axisPage('H', size.height, -_nudge, _nudge, (delta) {
            _write(
              component,
              module,
              resizePlacementFromEdges(
                placement: placement,
                resolvedSize: size,
                frame: frame,
                heightDelta: delta,
              ),
            );
          }),
        ],
        palette: host.palette,
        prismStyle: host.dashboard.settings.prismStyle,
        soundEnabled: host.soundEnabled,
        hapticsEnabled: host.hapticsEnabled,
        semanticLabel: 'Placement control',
      ),
    );
  }

  Widget _anchorPage(
    Placement placement,
    Size frame,
    ComponentInstance? component,
    VfdModule? module,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      VfdLegend('Anchor', palette: host.palette, lit: true, size: 11),
      const SizedBox(height: 8),
      PrismSelectorBank<Anchor>(
        choices: <PrismSelectorChoice<Anchor>>[
          for (final anchor in Anchor.values)
            PrismSelectorChoice<Anchor>(
              value: anchor,
              label: anchor.name,
              lit: anchor == placement.anchor,
            ),
        ],
        selected: placement.anchor,
        palette: host.palette,
        prismStyle: host.dashboard.settings.prismStyle,
        rows: 3,
        soundEnabled: host.soundEnabled,
        hapticsEnabled: host.hapticsEnabled,
        semanticLabel: 'Anchor',
        onSelected: (anchor) {
          final center = placement.resolve(frame);
          _write(
            component,
            module,
            placement.copyWith(
              anchor: anchor,
              offset: center - anchor.pointIn(frame),
            ),
          );
        },
      ),
    ],
  );

  Widget _spanPage(
    Placement placement,
    Size frame,
    Size size,
    ComponentInstance? component,
    VfdModule? module,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      VfdLegend('Axis sizing', palette: host.palette, lit: true, size: 11),
      const SizedBox(height: 8),
      PrismSelectorBank<String>(
        choices: <PrismSelectorChoice<String>>[
          PrismSelectorChoice<String>(
            value: 'x-fixed',
            label: 'X fixed',
            lit: placement.horizontalSpan == null,
          ),
          PrismSelectorChoice<String>(
            value: 'x-span',
            label: 'X span',
            lit: placement.horizontalSpan != null,
          ),
          PrismSelectorChoice<String>(
            value: 'y-fixed',
            label: 'Y fixed',
            lit: placement.verticalSpan == null,
          ),
          PrismSelectorChoice<String>(
            value: 'y-span',
            label: 'Y span',
            lit: placement.verticalSpan != null,
          ),
        ],
        selected: null,
        palette: host.palette,
        prismStyle: host.dashboard.settings.prismStyle,
        rows: 2,
        columns: 2,
        soundEnabled: host.soundEnabled,
        hapticsEnabled: host.hapticsEnabled,
        semanticLabel: 'Axis sizing mode',
        onSelected: (value) {
          final center = placement.resolve(frame);
          var next = placement.copyWith(
            offset: center - placement.anchor.pointIn(frame),
            size: size,
          );
          switch (value) {
            case 'x-fixed':
              next = next.withHorizontalSpan(null);
            case 'x-span':
              next = next.withHorizontalSpan(
                AxisSpan(
                  startInset: frame.width / 2 + center.dx - size.width / 2,
                  endInset: frame.width / 2 - center.dx - size.width / 2,
                ),
              );
            case 'y-fixed':
              next = next.withVerticalSpan(null);
            case 'y-span':
              next = next.withVerticalSpan(
                AxisSpan(
                  startInset: frame.height / 2 - center.dy - size.height / 2,
                  endInset: frame.height / 2 + center.dy - size.height / 2,
                ),
              );
          }
          _write(component, module, next);
        },
      ),
    ],
  );

  Widget _recoveryPage(
    Placement placement,
    Offset center,
    ComponentInstance? component,
    VfdModule? module,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      VfdLegend('Frame recovery', palette: host.palette, lit: true, size: 11),
      const SizedBox(height: 8),
      VfdLegend(
        'Centers item without changing size.',
        palette: host.palette,
        size: 9,
      ),
      const Spacer(),
      Center(
        child: PrismButton(
          label: 'Bring in',
          palette: host.palette,
          role: PrismRole.standard,
          span: PrismSpan.two,
          style: host.dashboard.settings.prismStyle,
          soundEnabled: host.soundEnabled,
          hapticsEnabled: host.hapticsEnabled,
          onPressed: () => _write(
            component,
            module,
            nudgePlacement(placement, dx: -center.dx, dy: -center.dy),
          ),
        ),
      ),
      const Spacer(),
    ],
  );

  Widget _axisPage(
    String axis,
    double value,
    double decrease,
    double increase,
    ValueChanged<double> onNudge,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      VfdLegend('$axis placement', palette: host.palette, lit: true, size: 11),
      const Spacer(),
      Center(
        child: VfdLegend(
          value.toStringAsFixed(3),
          palette: host.palette,
          lit: true,
          size: 18,
        ),
      ),
      const Spacer(),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _nudgeButton('$axis -', () => onNudge(decrease)),
          const SizedBox(width: 8),
          _nudgeButton('$axis +', () => onNudge(increase)),
        ],
      ),
    ],
  );

  Widget _nudgeButton(String label, VoidCallback onPressed) => PrismButton(
    label: label,
    palette: host.palette,
    role: PrismRole.compact,
    span: PrismSpan.two,
    style: host.dashboard.settings.prismStyle,
    soundEnabled: host.soundEnabled,
    hapticsEnabled: host.hapticsEnabled,
    onPressed: onPressed,
  );

  void _write(
    ComponentInstance? component,
    VfdModule? module,
    Placement placement,
  ) {
    if (component != null) {
      host.onPlacementChanged(component.id, placement);
    } else if (module != null) {
      host.onModulePlacementChanged(module.id, placement);
    }
  }
}
