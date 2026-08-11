import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../actions/action_registry.dart';
import '../mechanical/mechanical_push_drawer.dart';
import '../mechanical/prism_selector_bank.dart';
import '../mechanical/vfd_editable_field.dart';
import '../model/action_binding.dart';
import '../model/component_instance.dart';
import '../model/component_type.dart';
import '../model/dashboard.dart';
import '../model/design.dart';
import '../model/design_layout.dart';
import '../model/optical_profile.dart';
import '../model/placement.dart';
import '../model/settings.dart';
import '../model/variant.dart';
import '../model/vfd_module.dart';
import '../platform/physical_interface_orientation.dart';
import '../vfd/prism_widgets.dart';
import '../vfd/vfd_render_assets.dart';
import '../vfd/vfd_widgets.dart';
import 'editor_add_catalogue.dart';
import 'editor_canvas.dart';
import 'editor_chrome_skin.dart';
import 'editor_command_dock.dart';
import 'editor_live_preview.dart';
import 'effect_panel.dart';
import 'param_editor.dart';
import 'placement_transform.dart';

enum _EditorSection { design, part, module, look, prism, place }

class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.dashboard,
    required this.onChanged,
    this.renderAssets,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.actionRegistry,
    this.interfaceOrientation = PhysicalInterfaceOrientation.unknown,
    this.dockPreferences = const EditorDockPreferences(),
    this.onDockPreferencesChanged,
  });

  final Dashboard dashboard;
  final ValueChanged<Dashboard> onChanged;
  final VfdRenderAssets? renderAssets;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final ActionRegistry? actionRegistry;
  final PhysicalInterfaceOrientation interfaceOrientation;
  final EditorDockPreferences dockPreferences;
  final ValueChanged<EditorDockPreferences>? onDockPreferencesChanged;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  static const _historyLimit = 100;

  late Dashboard _dashboard = widget.dashboard;
  late String _layoutId = _dashboard.baseLayoutId;
  late EditorDockPreferences _dockPreferences = widget.dockPreferences;
  _LayoutDraft? _layoutDraft;
  String? _selectedId;
  String? _selectedModuleId;
  bool _drawerOpen = false;
  bool _addCatalogueOpen = false;
  bool _snapEnabled = true;
  final List<Dashboard> _undoStack = <Dashboard>[];
  final List<Dashboard> _redoStack = <Dashboard>[];
  Dashboard? _placementHistoryStart;
  final GlobalKey _workspaceKey = GlobalKey();
  final GlobalKey<_EditorServicePanelState> _servicePanelKey =
      GlobalKey<_EditorServicePanelState>();
  final EditorCanvasController _canvasController = EditorCanvasController();
  _WorkspaceDropPreview? _dropPreview;

  VfdPalette get _palette =>
      VfdPalette.of(_dashboard.settings.opticalProfile.phosphor);
  EditorChromeSkin get _chromeSkin => VfdEditorChromeSkin(
    palette: _palette,
    prismStyle: _dashboard.settings.prismStyle,
  );
  @override
  void didUpdateWidget(covariant EditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dockPreferences != widget.dockPreferences) {
      _dockPreferences = widget.dockPreferences;
    }
  }

  /// Full physical viewport. Authored designs may deliberately use unsafe
  /// regions.
  Size get _deviceViewportSize => MediaQuery.sizeOf(context);

  EdgeInsets get _deviceSafeInsets => MediaQuery.viewPaddingOf(context);

  @override
  Widget build(BuildContext context) {
    final physicalSafeInsets = _EditorSafeLayout.physicalInsets(
      viewPadding: _deviceSafeInsets,
      interfaceOrientation: widget.interfaceOrientation,
    );
    final headerExtent = _deviceSafeInsets.top + 48;
    final workspaceChromeInsets = EdgeInsets.fromLTRB(
      physicalSafeInsets.left,
      headerExtent,
      physicalSafeInsets.right,
      physicalSafeInsets.bottom,
    );
    return ColoredBox(
      color: const Color(0xFF050807),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ColoredBox(
            key: const ValueKey('editor-canvas-environment'),
            color: const Color(0xFF050807),
            child: LayoutBuilder(
              builder: (context, constraints) => _workspace(
                constraints,
                workspaceChromeInsets: workspaceChromeInsets,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: headerExtent,
            child: _topChrome(
              context,
              EdgeInsets.fromLTRB(
                _deviceSafeInsets.left,
                _deviceSafeInsets.top,
                _deviceSafeInsets.right,
                0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topChrome(BuildContext context, EdgeInsets safeInsets) =>
      _chromeSkin.surface(
        key: const ValueKey('editor-header-layer'),
        role: EditorChromeSurfaceRole.header,
        padding: EdgeInsets.zero,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: safeInsets.left + 4,
              right:
                  safeInsets.right +
                  PrismMetrics.width(PrismRole.compact, PrismSpan.one) +
                  12,
              top: safeInsets.top + 2,
              bottom: 2,
              child: Row(
                children: <Widget>[
                  _chromeSkin.button(
                    key: const ValueKey('editor-back'),
                    label: 'Back',
                    compact: true,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _chromeSkin.title(
                      _dashboard.name,
                      key: const ValueKey('editor-title'),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: safeInsets.right + 4,
              top: safeInsets.top + 2,
              bottom: 2,
              child: _chromeSkin.button(
                key: const ValueKey('editor-console'),
                label: 'Console',
                compact: true,
                lit: _drawerOpen,
                selected: _drawerOpen,
                onPressed: () => setState(() => _drawerOpen = !_drawerOpen),
              ),
            ),
          ],
        ),
      );

  Dashboard get _canvasDashboard {
    final draft = _layoutDraft;
    if (draft == null) return _dashboard;
    return switch (draft.mode) {
      _LayoutDraftMode.add => _dashboard.withLayout(
        id: draft.id,
        aspect: draft.aspect,
        sourceLayoutId: draft.sourceLayoutId,
      ),
      _LayoutDraftMode.modify => _dashboard.withLayoutAspect(
        draft.id,
        draft.aspect,
      ),
    };
  }

  String get _canvasLayoutId => _layoutDraft?.id ?? _layoutId;

  Widget _canvas({EdgeInsets frameInset = EdgeInsets.zero}) => EditorCanvas(
    dashboard: _canvasDashboard,
    layoutId: _canvasLayoutId,
    editable: _layoutDraft == null,
    deviceViewportSize: _deviceViewportSize,
    selectedId: _selectedId,
    selectedModuleId: _selectedModuleId,
    onSelect: _selectComponent,
    onPlacementChanged: _setPlacement,
    onPlacementGestureStarted: _beginPlacementHistory,
    onPlacementGestureEnded: _finishPlacementHistory,
    onModulePlacementChanged: _setModulePlacement,
    renderAssets: widget.renderAssets,
    frameInset: frameInset,
    onAddDropped: _layoutDraft == null ? _addDropped : null,
    controller: _canvasController,
    snapEnabled: _snapEnabled,
  );

  void _selectLayout(String layoutId) {
    final setup = _dashboard.screenSetup;
    if (setup.behavior == ScreenBehavior.lock &&
        setup.lockedLayoutId != layoutId) {
      return;
    }
    setState(() {
      _layoutId = layoutId;
      _layoutDraft = null;
      _selectedId = null;
      _selectedModuleId = null;
    });
  }

  Widget _workspace(
    BoxConstraints constraints, {
    required EdgeInsets workspaceChromeInsets,
  }) {
    final layout = _WorkspaceLayout.resolve(
      windowSize: MediaQuery.sizeOf(context),
      constraints: constraints,
    );
    return Stack(
      key: _workspaceKey,
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: <Widget>[
        MechanicalPushDrawer(
          key: const ValueKey('editor-workspace'),
          open: _drawerOpen,
          edge: layout.edge,
          extent: layout.drawerExtent,
          contentBuilder: (context, progress) {
            final safeLayout = _EditorSafeLayout.resolve(
              chromeInsets: workspaceChromeInsets,
              interfaceOrientation: widget.interfaceOrientation,
              drawerEdge: layout.edge,
              drawerProgress: progress,
            );
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _canvas(frameInset: safeLayout.frameInset),
                EditorCommandDock(
                  skin: _chromeSkin,
                  placement: _dockPlacement(layout.windowOrientation),
                  safeInsets: safeLayout.dockSafeInsets,
                  headerExtent: workspaceChromeInsets.top,
                  canUndo: _undoStack.isNotEmpty,
                  canRedo: _redoStack.isNotEmpty,
                  snapEnabled: _snapEnabled,
                  onUndo: _undo,
                  onRedo: _redo,
                  onToggleSnap: () =>
                      setState(() => _snapEnabled = !_snapEnabled),
                  onCenter: _canvasController.centerCamera,
                  onPlacementChanged: (placement) =>
                      _setDockPlacement(layout.windowOrientation, placement),
                ),
              ],
            );
          },
          drawer: _chromeSkin.consoleSurface(
            edge: layout.edge,
            safeInsets: workspaceChromeInsets,
            child: KeyedSubtree(
              key: const ValueKey('mechanical-drawer-safe-content'),
              child: IndexedStack(
                index: _addCatalogueOpen ? 1 : 0,
                children: <Widget>[
                  _servicePanel(),
                  EditorAddCatalogue(
                    palette: _palette,
                    prismStyle: _dashboard.settings.prismStyle,
                    soundEnabled: widget.soundEnabled,
                    hapticsEnabled: widget.hapticsEnabled,
                    dashboard: _dashboard,
                    renderAssets: widget.renderAssets,
                    safeInsets: _deviceSafeInsets,
                    onClose: () => setState(() => _addCatalogueOpen = false),
                    onDragEnded: _clearDropPreview,
                    onDragUpdated: _updateDropPreview,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_dropPreview case final preview?)
          Positioned.fromRect(
            rect: preview.rect,
            child: IgnorePointer(
              child: EditorCanvasDropPreview(
                dashboard: _dashboard,
                request: preview.request,
                renderAssets: widget.renderAssets,
              ),
            ),
          ),
      ],
    );
  }

  Widget _servicePanel() => _EditorServicePanel(
    key: _servicePanelKey,
    dashboard: _dashboard,
    layoutId: _layoutId,
    layoutDraft: _layoutDraft,
    selectedId: _selectedId,
    selectedModuleId: _selectedModuleId,
    palette: _palette,
    soundEnabled: widget.soundEnabled,
    hapticsEnabled: widget.hapticsEnabled,
    actionRegistry: widget.actionRegistry ?? ActionRegistry.forAuthoring(),
    renderAssets: widget.renderAssets,
    safeInsets: _deviceSafeInsets,
    onOpenAddCatalogue: _openAddCatalogue,
    onSelectLayout: _selectLayout,
    onSelectComponent: _selectComponent,
    onSelectModule: _selectModule,
    onAddComponent: (type) => _addComponent(type, Offset.zero),
    onAddModule: () => _addModule(Offset.zero),
    onRemoveComponent: _removeComponent,
    onRemoveModule: _removeModule,
    onMoveComponent: _moveComponent,
    onVisibilityChanged: _setVisibility,
    onComponentChanged: _replaceComponent,
    onDashboardChanged: _replaceDashboard,
    onBeginLayoutDraft: _beginLayoutDraft,
    onBeginLayoutModification: _beginLayoutModification,
    onLayoutDraftAspectChanged: _setLayoutDraftAspect,
    onCancelLayoutDraft: _cancelLayoutDraft,
    onCommitLayoutDraft: _commitLayoutDraft,
    onRemoveLayout: _removeLayout,
    onToggleScreenLock: _toggleScreenLock,
    onPlacementChanged: _setPlacement,
    onModulePlacementChanged: _setModulePlacement,
  );

  void _selectComponent(String? id) => setState(() {
    _selectedId = id;
    _selectedModuleId = null;
    _addCatalogueOpen = false;
  });

  void _selectModule(String id) => setState(() {
    _selectedId = null;
    _selectedModuleId = id;
    _addCatalogueOpen = false;
  });

  void _openAddCatalogue() => setState(() {
    _addCatalogueOpen = true;
    _drawerOpen = true;
  });

  void _addDropped(EditorAddRequest request, Offset center) {
    _clearDropPreview();
    if (request.componentType case final type?) {
      _addComponent(type, center);
    } else {
      _addModule(center);
    }
  }

  void _setDropPreview(EditorAddRequest request, Rect globalRect) {
    final box = _workspaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.globalToLocal(globalRect.topLeft);
    final next = _WorkspaceDropPreview(
      request: request,
      rect: origin & globalRect.size,
    );
    if (_dropPreview == next) return;
    setState(() => _dropPreview = next);
  }

  void _updateDropPreview(EditorAddRequest request, Offset globalPosition) {
    final rect = _canvasController.previewRect(request, globalPosition);
    if (rect == null) return;
    _setDropPreview(request, rect);
  }

  EditorDockPlacement _dockPlacement(ViewportOrientation windowOrientation) =>
      windowOrientation == ViewportOrientation.portrait
      ? _dockPreferences.portrait
      : _dockPreferences.landscape;

  void _setDockPlacement(
    ViewportOrientation windowOrientation,
    EditorDockPlacement placement,
  ) {
    final next = windowOrientation == ViewportOrientation.portrait
        ? _dockPreferences.copyWith(portrait: placement)
        : _dockPreferences.copyWith(landscape: placement);
    if (next == _dockPreferences) return;
    setState(() => _dockPreferences = next);
    widget.onDockPreferencesChanged?.call(next);
  }

  void _clearDropPreview() {
    if (_dropPreview == null) return;
    setState(() => _dropPreview = null);
  }

  void _setVisibility(ComponentInstance component, bool visible) {
    final existing = component.placements[_layoutId];
    _replaceComponent(
      component.withPlacement(
        _layoutId,
        visible
            ? (existing ??
                  Placement(
                    center: Offset.zero,
                    size:
                        ComponentTypes.byId(component.typeId)?.defaultSize ??
                        const Size(1, 1),
                  ))
            : null,
      ),
    );
  }

  void _beginLayoutDraft() => setState(() {
    final sourceAspect = _dashboard.frameAspect(_layoutId);
    _layoutDraft = _LayoutDraft(
      mode: _LayoutDraftMode.add,
      id: _nextLayoutId(),
      sourceLayoutId: _layoutId,
      aspect: sourceAspect >= 1 ? 9 / 16 : 16 / 9,
    );
    _selectedId = null;
    _selectedModuleId = null;
  });

  void _beginLayoutModification() => setState(() {
    _layoutDraft = _LayoutDraft(
      mode: _LayoutDraftMode.modify,
      id: _layoutId,
      sourceLayoutId: _layoutId,
      aspect: _dashboard.frameAspect(_layoutId),
    );
    _selectedId = null;
    _selectedModuleId = null;
  });

  void _setLayoutDraftAspect(double aspect) {
    final draft = _layoutDraft;
    if (draft == null || !aspect.isFinite || aspect <= 0) return;
    setState(() => _layoutDraft = draft.copyWith(aspect: aspect));
  }

  void _cancelLayoutDraft() => setState(() => _layoutDraft = null);

  void _commitLayoutDraft() {
    final draft = _layoutDraft;
    if (draft == null || _hasLayoutAspect(draft.aspect, excluding: draft)) {
      return;
    }
    var next = _canvasDashboard;
    final locked = next.screenSetup.behavior == ScreenBehavior.lock;
    if (draft.mode == _LayoutDraftMode.modify &&
        next.screenSetup.lockedLayoutId == draft.id) {
      next = next.copyWith(
        screenSetup: _lockedScreenSetup(draft.id, draft.aspect),
      );
    }
    setState(() {
      _layoutDraft = null;
      if (draft.mode == _LayoutDraftMode.add && !locked) {
        _layoutId = draft.id;
      }
    });
    _replaceDashboard(next);
  }

  void _removeLayout(String layoutId) {
    final next = _dashboard.withoutLayout(layoutId);
    if (identical(next, _dashboard)) return;
    _replaceDashboard(next);
  }

  void _toggleScreenLock() {
    if (_dashboard.screenSetup.behavior == ScreenBehavior.lock) {
      _replaceDashboard(
        _dashboard.copyWith(screenSetup: const ScreenSetup.adapt()),
      );
      return;
    }
    _lockCurrentLayout();
  }

  void _lockCurrentLayout() {
    final aspect = _dashboard.frameAspect(_layoutId);
    _replaceDashboard(
      _dashboard.copyWith(screenSetup: _lockedScreenSetup(_layoutId, aspect)),
    );
  }

  ScreenSetup _lockedScreenSetup(String layoutId, double aspect) {
    final current = ViewportOrientation.fromSize(_deviceViewportSize);
    final orientation = aspect > 1
        ? ViewportOrientation.landscape
        : aspect < 1
        ? ViewportOrientation.portrait
        : current;
    return ScreenSetup.lock(layoutId: layoutId, orientation: orientation);
  }

  void _setPlacement(String id, Placement placement) {
    final component = _component(id);
    if (component != null) {
      _replaceComponent(component.withPlacement(_layoutId, placement));
    }
  }

  void _setModulePlacement(String id, Placement placement) {
    final module = _module(id);
    if (module == null || id == kMainVfdModuleId) return;
    _replaceDashboard(
      _dashboard.withModule(
        module.copyWith(
          regions: <String, Placement>{...module.regions, _layoutId: placement},
        ),
      ),
    );
  }

  void _addComponent(ComponentTypeSpec type, Offset center) {
    final component = ComponentInstance(
      id: _nextComponentId(type.id),
      typeId: type.id,
      params: type.defaults,
      placements: <String, Placement>{
        _layoutId: Placement(
          center: center,
          size: type.legacyVariantSpec.recommendedSize,
        ),
      },
    );
    _replaceDashboard(_dashboard.withComponent(component));
    _selectComponent(component.id);
  }

  void _addModule(Offset center) {
    var index = 2;
    var id = 'module-$index';
    final ids = _dashboard.modules.map((module) => module.id).toSet();
    while (ids.contains(id)) {
      id = 'module-${++index}';
    }
    final module = VfdModule(
      id: id,
      name: 'VFD module $index',
      regions: <String, Placement>{
        _layoutId: Placement(center: center, size: Size(1, 0.5)),
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
    if (identical(next, _dashboard)) return;
    if (_placementHistoryStart != null) {
      setState(() {
        _dashboard = next;
        _clearInvalidSelection(next);
      });
      widget.onChanged(next);
      return;
    }
    setState(() {
      _pushHistory(_undoStack, _dashboard);
      _redoStack.clear();
      _dashboard = next;
      _clearInvalidSelection(next);
    });
    widget.onChanged(next);
  }

  void _beginPlacementHistory() {
    _placementHistoryStart ??= _dashboard;
  }

  void _finishPlacementHistory(bool commit) {
    final start = _placementHistoryStart;
    _placementHistoryStart = null;
    if (start == null) return;
    if (!commit) {
      setState(() {
        _dashboard = start;
        _clearInvalidSelection(start);
      });
      widget.onChanged(start);
      return;
    }
    setState(() {
      _pushHistory(_undoStack, start);
      _redoStack.clear();
    });
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final previous = _undoStack.removeLast();
    setState(() {
      _pushHistory(_redoStack, _dashboard);
      _dashboard = previous;
      _clearInvalidSelection(previous);
    });
    widget.onChanged(previous);
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    setState(() {
      _pushHistory(_undoStack, _dashboard);
      _dashboard = next;
      _clearInvalidSelection(next);
    });
    widget.onChanged(next);
  }

  void _pushHistory(List<Dashboard> stack, Dashboard value) {
    if (stack.length == _historyLimit) stack.removeAt(0);
    stack.add(value);
  }

  void _clearInvalidSelection(Dashboard dashboard) {
    if (!dashboard.layouts.any((layout) => layout.id == _layoutId)) {
      _layoutId = dashboard.baseLayoutId;
      _layoutDraft = null;
      _selectedId = null;
      _selectedModuleId = null;
      return;
    }
    if ((_selectedId != null &&
            _componentIn(dashboard, _selectedId!) == null) ||
        (_selectedModuleId != null &&
            _moduleIn(dashboard, _selectedModuleId!) == null)) {
      _selectedId = null;
      _selectedModuleId = null;
    }
  }

  ComponentInstance? _componentIn(Dashboard dashboard, String id) =>
      dashboard.components.where((item) => item.id == id).firstOrNull;

  VfdModule? _moduleIn(Dashboard dashboard, String id) =>
      dashboard.modules.where((item) => item.id == id).firstOrNull;

  ComponentInstance? _component(String id) => _componentIn(_dashboard, id);

  VfdModule? _module(String id) => _moduleIn(_dashboard, id);

  String _nextComponentId(String typeId) {
    var index = 1;
    var candidate = '$typeId-$index';
    final ids = _dashboard.components.map((item) => item.id).toSet();
    while (ids.contains(candidate)) {
      candidate = '$typeId-${++index}';
    }
    return candidate;
  }

  String _nextLayoutId() {
    var index = 1;
    var candidate = 'layout-$index';
    final ids = _dashboard.layouts.map((layout) => layout.id).toSet();
    while (ids.contains(candidate)) {
      candidate = 'layout-${++index}';
    }
    return candidate;
  }

  bool _hasLayoutAspect(double aspect, {required _LayoutDraft excluding}) =>
      _dashboard.layouts.any(
        (layout) =>
            !(excluding.mode == _LayoutDraftMode.modify &&
                layout.id == excluding.id) &&
            (math.log(layout.aspect / aspect)).abs() < 0.001,
      );
}

@immutable
class _WorkspaceDropPreview {
  const _WorkspaceDropPreview({required this.request, required this.rect});

  final EditorAddRequest request;
  final Rect rect;

  @override
  bool operator ==(Object other) =>
      other is _WorkspaceDropPreview &&
      other.request.kind == request.kind &&
      other.request.componentType?.id == request.componentType?.id &&
      other.rect == rect;

  @override
  int get hashCode =>
      Object.hash(request.kind, request.componentType?.id, rect);
}

enum _LayoutDraftMode { add, modify }

@immutable
class _LayoutDraft {
  const _LayoutDraft({
    required this.mode,
    required this.id,
    required this.sourceLayoutId,
    required this.aspect,
  });

  final _LayoutDraftMode mode;
  final String id;
  final String sourceLayoutId;
  final double aspect;

  _LayoutDraft copyWith({double? aspect}) => _LayoutDraft(
    mode: mode,
    id: id,
    sourceLayoutId: sourceLayoutId,
    aspect: aspect ?? this.aspect,
  );
}

/// Where the service bay enters from and how much room it takes.
///
/// Portrait and landscape keep their own numbers — a bay that pushes up wants a
/// different reserve from one that pushes in from the side — but every other
/// part of the editor is shape-agnostic, so this is the only branch.
class _WorkspaceLayout {
  const _WorkspaceLayout({
    required this.edge,
    required this.drawerExtent,
    required this.windowOrientation,
  });

  final MechanicalDrawerEdge edge;
  final double drawerExtent;
  final ViewportOrientation windowOrientation;

  static _WorkspaceLayout resolve({
    required Size windowSize,
    required BoxConstraints constraints,
  }) {
    if (windowSize.height > windowSize.width) {
      final maxExtent = math.max(160.0, constraints.maxHeight - 120);
      return _WorkspaceLayout(
        edge: MechanicalDrawerEdge.bottom,
        windowOrientation: ViewportOrientation.portrait,
        drawerExtent: math.min(
          maxExtent,
          (constraints.maxHeight * 0.42).clamp(220, 420).toDouble(),
        ),
      );
    }
    final maxExtent = math.max(240.0, constraints.maxWidth - 60);
    return _WorkspaceLayout(
      edge: MechanicalDrawerEdge.right,
      windowOrientation: ViewportOrientation.landscape,
      drawerExtent: math.min(
        maxExtent,
        (constraints.maxWidth * 0.38).clamp(280, 420).toDouble(),
      ),
    );
  }
}

/// Assigns physical safe space to the pane that owns each screen edge.
///
/// Runtime geometry remains full-viewport. Only the editor preview fit and its
/// screen-space controls change while the service drawer travels.
class _EditorSafeLayout {
  const _EditorSafeLayout({
    required this.frameInset,
    required this.dockSafeInsets,
  });

  final EdgeInsets frameInset;
  final EdgeInsets dockSafeInsets;

  /// Safe side ownership follows physical interface direction. Landscape
  /// padding on the opposite side belongs to the other pane, not both panes.
  static EdgeInsets physicalInsets({
    required EdgeInsets viewPadding,
    required PhysicalInterfaceOrientation interfaceOrientation,
  }) => switch (interfaceOrientation) {
    PhysicalInterfaceOrientation.landscapeLeft => EdgeInsets.only(
      left: viewPadding.left,
      bottom: viewPadding.bottom,
    ),
    PhysicalInterfaceOrientation.landscapeRight => EdgeInsets.only(
      right: viewPadding.right,
      bottom: viewPadding.bottom,
    ),
    _ => viewPadding,
  };

  static _EditorSafeLayout resolve({
    required EdgeInsets chromeInsets,
    required PhysicalInterfaceOrientation interfaceOrientation,
    required MechanicalDrawerEdge drawerEdge,
    required double drawerProgress,
  }) {
    final progress = drawerProgress.clamp(0.0, 1.0);
    final frameLeft =
        drawerEdge == MechanicalDrawerEdge.right &&
            interfaceOrientation == PhysicalInterfaceOrientation.landscapeLeft
        ? chromeInsets.left * progress
        : 0.0;
    final canvasRight = drawerEdge == MechanicalDrawerEdge.right
        ? chromeInsets.right * (1 - progress)
        : chromeInsets.right;
    final canvasBottom = drawerEdge == MechanicalDrawerEdge.bottom
        ? chromeInsets.bottom * (1 - progress)
        : chromeInsets.bottom;

    return _EditorSafeLayout(
      frameInset: EdgeInsets.only(left: frameLeft),
      dockSafeInsets: EdgeInsets.fromLTRB(
        chromeInsets.left,
        0,
        canvasRight,
        canvasBottom,
      ),
    );
  }
}

class _EditorServicePanel extends StatefulWidget {
  const _EditorServicePanel({
    super.key,
    required this.dashboard,
    required this.layoutId,
    required this.layoutDraft,
    required this.selectedId,
    required this.selectedModuleId,
    required this.palette,
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.actionRegistry,
    required this.renderAssets,
    required this.safeInsets,
    required this.onOpenAddCatalogue,
    required this.onSelectLayout,
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
    required this.onBeginLayoutDraft,
    required this.onBeginLayoutModification,
    required this.onLayoutDraftAspectChanged,
    required this.onCancelLayoutDraft,
    required this.onCommitLayoutDraft,
    required this.onRemoveLayout,
    required this.onToggleScreenLock,
    required this.onPlacementChanged,
    required this.onModulePlacementChanged,
  });

  final Dashboard dashboard;
  final String layoutId;
  final _LayoutDraft? layoutDraft;
  final String? selectedId;
  final String? selectedModuleId;
  final VfdPalette palette;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final ActionRegistry actionRegistry;
  final VfdRenderAssets? renderAssets;
  final EdgeInsets safeInsets;
  final VoidCallback onOpenAddCatalogue;
  final ValueChanged<String> onSelectLayout;
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
  final VoidCallback onBeginLayoutDraft;
  final VoidCallback onBeginLayoutModification;
  final ValueChanged<double> onLayoutDraftAspectChanged;
  final VoidCallback onCancelLayoutDraft;
  final VoidCallback onCommitLayoutDraft;
  final ValueChanged<String> onRemoveLayout;
  final VoidCallback onToggleScreenLock;
  final void Function(String id, Placement placement) onPlacementChanged;
  final void Function(String id, Placement placement) onModulePlacementChanged;

  @override
  State<_EditorServicePanel> createState() => _EditorServicePanelState();
}

class _EditorServicePanelState extends State<_EditorServicePanel> {
  _EditorSection _section = _EditorSection.design;

  List<_EditorSection> get _sections {
    if (widget.selectedId != null) {
      return const <_EditorSection>[
        _EditorSection.part,
        _EditorSection.look,
        _EditorSection.place,
      ];
    }
    if (widget.selectedModuleId != null) {
      return const <_EditorSection>[
        _EditorSection.module,
        _EditorSection.look,
        _EditorSection.place,
      ];
    }
    return const <_EditorSection>[
      _EditorSection.design,
      _EditorSection.look,
      _EditorSection.prism,
    ];
  }

  @override
  void didUpdateWidget(covariant _EditorServicePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sections.contains(_section)) _section = _sections.first;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
    child: Builder(
      builder: (context) {
        final sections = _sections;
        final active = sections.contains(_section) ? _section : sections.first;
        _section = active;
        return Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: PrismSelectorBank<_EditorSection>(
                    choices: <PrismSelectorChoice<_EditorSection>>[
                      for (final section in sections)
                        PrismSelectorChoice<_EditorSection>(
                          value: section,
                          label: section.name,
                          controlKey: ValueKey(
                            'editor-service-section-${section.name}',
                          ),
                          lit: section == active,
                        ),
                    ],
                    selected: active,
                    palette: widget.palette,
                    prismStyle: widget.dashboard.settings.prismStyle,
                    rows: 1,
                    columns: sections.length,
                    role: PrismRole.compact,
                    soundEnabled: widget.soundEnabled,
                    hapticsEnabled: widget.hapticsEnabled,
                    semanticLabel: 'Editor service section',
                    onSelected: (section) => setState(() => _section = section),
                  ),
                ),
                const SizedBox(width: 6),
                PrismButton(
                  key: const ValueKey('console-add'),
                  label: 'Add',
                  palette: widget.palette,
                  enabled: widget.layoutDraft == null,
                  role: PrismRole.compact,
                  style: widget.dashboard.settings.prismStyle,
                  onPressed: widget.layoutDraft == null
                      ? widget.onOpenAddCatalogue
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(child: _sectionBody(active)),
          ],
        );
      },
    ),
  );

  Widget _sectionBody(_EditorSection section) => switch (section) {
    _EditorSection.design => _DesignPanel(host: widget),
    _EditorSection.part => _PartPanel(host: widget),
    _EditorSection.module => _ModulePanel(host: widget),
    _EditorSection.look => _look(),
    _EditorSection.prism => PrismStyleEditor(
      profile: widget.dashboard.settings.opticalProfile,
      style: widget.dashboard.settings.prismStyle,
      soundEnabled: widget.soundEnabled,
      hapticsEnabled: widget.hapticsEnabled,
      contentSafeInsets: widget.safeInsets,
      onChanged: (style) => widget.onDashboardChanged(
        widget.dashboard.copyWith(
          settings: widget.dashboard.settings.copyWith(prismStyle: style),
        ),
      ),
    ),
    _EditorSection.place => _PlacementPanel(host: widget),
  };

  Widget _look() {
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
        contentSafeInsets: widget.safeInsets,
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
            lit: item.visibleIn(host.layoutId),
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
        component?.appearsIn(host.layoutId) ??
        (module?.regionIn(host.layoutId) != null);
    return Row(
      children: <Widget>[
        if (component != null) ...<Widget>[
          _action('Up', () => host.onMoveComponent(component, -1)),
          const SizedBox(width: 4),
          _action('Down', () => host.onMoveComponent(component, 1)),
          const SizedBox(width: 4),
        ],
        _action(
          'Visible',
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
      onPressed: () => setState(() {
        _addingComponent = component && !_addingComponent;
        _addingModule = !component && !_addingModule;
      }),
    ),
  );

  void _toggleModuleVisibility(VfdModule module, bool visible) {
    final regions = <String, Placement>{...module.regions};
    if (visible) {
      regions.remove(host.layoutId);
    } else {
      regions[host.layoutId] = const Placement(
        center: Offset.zero,
        size: Size(1, 0.5),
      );
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

  bool visibleIn(String layoutId) =>
      component?.appearsIn(layoutId) ?? (module?.regionIn(layoutId) != null);

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
  static const _commonAspects = <double>[
    9 / 20,
    9 / 16,
    3 / 4,
    1,
    4 / 3,
    16 / 9,
    20 / 9,
  ];
  static const _commonAspectLabels = <String>[
    '9:20',
    '9:16',
    '3:4',
    '1:1',
    '4:3',
    '16:9',
    '20:9',
  ];
  static const _dangerPalette = VfdPalette(
    lit: Color(0xFFFF4A3D),
    unlit: Color(0xFF783D38),
  );

  @override
  Widget build(BuildContext context) => PrismPanel(
    palette: host.palette,
    padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + host.safeInsets.bottom),
    child: switch (host.layoutDraft) {
      final draft? => _layoutDraft(draft),
      null => _layoutBrowser(),
    },
  );

  Widget _layoutBrowser() {
    final locked = host.dashboard.screenSetup.behavior == ScreenBehavior.lock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            PrismButton(
              key: const ValueKey('add-layout'),
              label: 'Add layout',
              palette: host.palette,
              lit: true,
              role: PrismRole.compact,
              span: PrismSpan.two,
              style: host.dashboard.settings.prismStyle,
              onPressed: host.onBeginLayoutDraft,
            ),
            const Spacer(),
            PrismButton(
              key: const ValueKey('screen-lock'),
              label: 'Lock',
              palette: host.palette,
              lit: locked,
              selected: locked,
              role: PrismRole.compact,
              style: host.dashboard.settings.prismStyle,
              onPressed: host.onToggleScreenLock,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: _layoutGrid(locked)),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            PrismButton(
              key: const ValueKey('modify-layout'),
              label: 'Modify',
              palette: host.palette,
              role: PrismRole.compact,
              span: PrismSpan.two,
              style: host.dashboard.settings.prismStyle,
              onPressed: host.onBeginLayoutModification,
            ),
            const Spacer(),
            if (host.layoutId != host.dashboard.baseLayoutId)
              PrismButton(
                key: const ValueKey('remove-layout'),
                label: 'Remove',
                palette: _dangerPalette,
                lit: true,
                role: PrismRole.compact,
                style: host.dashboard.settings.prismStyle,
                onPressed: () => host.onRemoveLayout(host.layoutId),
              ),
          ],
        ),
      ],
    );
  }

  Widget _layoutGrid(bool locked) => GridView.builder(
    key: const ValueKey('screen-layout-grid'),
    padding: EdgeInsets.zero,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisExtent: PrismMetrics.height(PrismRole.standard),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
    ),
    itemCount: host.dashboard.layouts.length,
    itemBuilder: (context, index) {
      final layout = host.dashboard.layouts[index];
      return Center(child: _layoutButton(layout, locked));
    },
  );

  Widget _layoutButton(DesignLayout layout, bool locked) {
    final selected = layout.id == host.layoutId;
    final base = layout.id == host.dashboard.baseLayoutId;
    final enabled = !locked || selected;
    final ratio = formatLayoutRatio(layout.aspect);
    return PrismButton(
      key: ValueKey('screen-layout-${layout.id}'),
      label: '$ratio layout${base ? ', base' : ''}',
      value: selected ? 'Selected' : null,
      face: _LayoutPrismFace(
        layoutId: layout.id,
        aspect: layout.aspect,
        ratio: ratio,
        palette: host.palette,
        style: host.dashboard.settings.prismStyle,
        selected: selected,
        enabled: enabled,
      ),
      palette: host.palette,
      lit: selected,
      selected: selected,
      enabled: enabled,
      role: PrismRole.standard,
      square: true,
      style: host.dashboard.settings.prismStyle,
      onPressed: enabled ? () => host.onSelectLayout(layout.id) : null,
    );
  }

  Widget _layoutDraft(_LayoutDraft draft) {
    final modifying = draft.mode == _LayoutDraftMode.modify;
    final ratio = _RatioPair.fromAspect(draft.aspect);
    final duplicate = host.dashboard.layouts.any(
      (layout) =>
          (!modifying || layout.id != draft.id) &&
          (math.log(layout.aspect / draft.aspect)).abs() < 0.001,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        VfdLegend(
          modifying ? 'Modify layout' : 'Add layout',
          palette: host.palette,
          lit: true,
          size: 12,
        ),
        const SizedBox(height: 4),
        VfdLegend(
          modifying
              ? 'Set the frame ratio. Parts keep their size and position.'
              : 'Select a frame ratio. Parts keep their size and position.',
          palette: host.palette,
          size: 9,
          maxLines: 2,
        ),
        const SizedBox(height: 6),
        Expanded(
          child: CustomPaint(
            key: const ValueKey('layout-aspect-map'),
            painter: _AspectMapPainter(
              aspects: _commonAspects,
              selectedAspect: draft.aspect,
              lit: host.palette.lit,
              unlit: host.palette.unlit,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 6),
        _aspectPresets(draft.aspect),
        const SizedBox(height: 6),
        _ratioFields(
          ratio,
          onChanged: host.onLayoutDraftAspectChanged,
          keyPrefix: modifying ? 'modify-layout' : 'new-layout',
        ),
        if (duplicate) ...<Widget>[
          const SizedBox(height: 4),
          VfdLegend(
            'This frame ratio already exists.',
            palette: host.palette,
            size: 9,
          ),
        ],
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            PrismButton(
              key: const ValueKey('cancel-layout-draft'),
              label: 'Cancel',
              palette: host.palette,
              role: PrismRole.compact,
              style: host.dashboard.settings.prismStyle,
              onPressed: host.onCancelLayoutDraft,
            ),
            const Spacer(),
            PrismButton(
              key: ValueKey(modifying ? 'apply-layout' : 'create-layout'),
              label: modifying ? 'Apply' : 'Create layout',
              palette: host.palette,
              lit: !duplicate,
              enabled: !duplicate,
              role: PrismRole.compact,
              span: PrismSpan.two,
              style: host.dashboard.settings.prismStyle,
              onPressed: duplicate ? null : host.onCommitLayoutDraft,
            ),
          ],
        ),
      ],
    );
  }

  Widget _aspectPresets(double selectedAspect) => SizedBox(
    height: PrismMetrics.height(PrismRole.micro),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _commonAspects.length,
      separatorBuilder: (_, _) => const SizedBox(width: 3),
      itemBuilder: (context, index) {
        final aspect = _commonAspects[index];
        final selected = (math.log(aspect / selectedAspect)).abs() < 0.001;
        return PrismButton(
          key: ValueKey('layout-preset-$index'),
          label: _commonAspectLabels[index],
          palette: host.palette,
          lit: selected,
          selected: selected,
          role: PrismRole.micro,
          style: host.dashboard.settings.prismStyle,
          onPressed: () => host.onLayoutDraftAspectChanged(aspect),
        );
      },
    ),
  );

  Widget _ratioFields(
    _RatioPair ratio, {
    required ValueChanged<double> onChanged,
    required String keyPrefix,
  }) => Row(
    children: <Widget>[
      Expanded(
        child: VfdEditableField(
          key: ValueKey('$keyPrefix-width'),
          label: 'Frame W',
          value: ratio.width.toStringAsFixed(3),
          palette: host.palette,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) {},
          onSubmitted: (raw) {
            final width = double.tryParse(raw);
            if (width != null && width > 0) onChanged(width / ratio.height);
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: VfdLegend(':', palette: host.palette, size: 11),
      ),
      Expanded(
        child: VfdEditableField(
          key: ValueKey('$keyPrefix-height'),
          label: 'Frame H',
          value: ratio.height.toStringAsFixed(3),
          palette: host.palette,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) {},
          onSubmitted: (raw) {
            final height = double.tryParse(raw);
            if (height != null && height > 0) onChanged(ratio.width / height);
          },
        ),
      ),
    ],
  );
}

@immutable
class _RatioPair {
  const _RatioPair(this.width, this.height);

  factory _RatioPair.fromAspect(double aspect) =>
      aspect >= 1 ? _RatioPair(aspect, 1) : _RatioPair(1, 1 / aspect);

  final double width;
  final double height;
}

class _LayoutPrismFace extends StatelessWidget {
  const _LayoutPrismFace({
    required this.layoutId,
    required this.aspect,
    required this.ratio,
    required this.palette,
    required this.style,
    required this.selected,
    required this.enabled,
  });

  final String layoutId;
  final double aspect;
  final String ratio;
  final VfdPalette palette;
  final PrismStyle style;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      SizedBox(
        width: 30,
        height: 14,
        child: CustomPaint(
          key: ValueKey('layout-ratio-frame-$layoutId'),
          painter: _LayoutShapePainter(
            aspect: aspect,
            color: (selected ? palette.lit : palette.unlit).withValues(
              alpha: enabled ? 1 : 0.32,
            ),
          ),
        ),
      ),
      const SizedBox(height: 1),
      PrismLegend(
        ratio,
        palette: palette,
        lit: selected,
        enabled: enabled,
        inactiveLuminosity: style.inactiveLuminosity,
        size: 8,
      ),
    ],
  );
}

class _LayoutShapePainter extends CustomPainter {
  const _LayoutShapePainter({required this.aspect, required this.color});

  final double aspect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final available = Size(
      math.max(0, size.width - 12),
      math.max(0, size.height - 12),
    );
    final fitted = applyBoxFit(BoxFit.contain, Size(aspect, 1), available);
    final rect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(covariant _LayoutShapePainter oldDelegate) =>
      oldDelegate.aspect != aspect || oldDelegate.color != color;
}

class _AspectMapPainter extends CustomPainter {
  const _AspectMapPainter({
    required this.aspects,
    required this.selectedAspect,
    required this.lit,
    required this.unlit,
  });

  final List<double> aspects;
  final double selectedAspect;
  final Color lit;
  final Color unlit;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxWidth = math.max(1.0, size.width - 20);
    final maxHeight = math.max(1.0, size.height - 12);
    for (final aspect in aspects) {
      final fitted = applyBoxFit(
        BoxFit.contain,
        Size(aspect, 1),
        Size(maxWidth, maxHeight),
      ).destination;
      canvas.drawRect(
        Alignment.center.inscribe(fitted, Offset.zero & size),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = unlit.withValues(alpha: 0.22),
      );
    }
    final selected = applyBoxFit(
      BoxFit.contain,
      Size(selectedAspect, 1),
      Size(maxWidth, maxHeight),
    ).destination;
    final selectedRect = Rect.fromCenter(
      center: center,
      width: selected.width,
      height: selected.height,
    );
    canvas.drawRect(
      selectedRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = lit.withValues(alpha: 0.92),
    );
    canvas.drawCircle(center, 2, Paint()..color = lit);
  }

  @override
  bool shouldRepaint(covariant _AspectMapPainter oldDelegate) =>
      oldDelegate.selectedAspect != selectedAspect ||
      oldDelegate.lit != lit ||
      oldDelegate.unlit != unlit;
}

class _PartPanel extends StatefulWidget {
  const _PartPanel({required this.host});

  final _EditorServicePanel host;

  @override
  State<_PartPanel> createState() => _PartPanelState();
}

class _PartPanelState extends State<_PartPanel> {
  String? _controlId;

  _EditorServicePanel get host => widget.host;

  @override
  void didUpdateWidget(covariant _PartPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host.selectedId != host.selectedId) _controlId = null;
  }

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: VfdLegend(
                  type.displayName,
                  palette: host.palette,
                  lit: true,
                  size: 12,
                ),
              ),
              _GuardedRemove(
                itemName: type.displayName,
                prismStyle: host.dashboard.settings.prismStyle,
                soundEnabled: host.soundEnabled,
                hapticsEnabled: host.hapticsEnabled,
                onRemove: () => host.onRemoveComponent(component),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Expanded(
            child: _controlId == null
                ? _controlList(component, type)
                : _detail(component, type, _controlId!),
          ),
        ],
      ),
    );
  }

  Widget _controlList(ComponentInstance component, ComponentTypeSpec type) {
    final controls = <Widget>[
      _selectorRow(
        key: const ValueKey('part-control-variant'),
        label: 'Variant',
        value:
            type.variant(component.effectiveVariant)?.displayName ??
            component.effectiveVariant.id,
        onPressed: () => setState(() => _controlId = 'variant'),
      ),
      _selectorRow(
        key: const ValueKey('part-control-module'),
        label: 'Module',
        value:
            host.dashboard.modules
                .where((item) => item.id == component.moduleId)
                .firstOrNull
                ?.name ??
            'Missing',
        onPressed: () => setState(() => _controlId = 'module'),
      ),
      if (component.typeId == ComponentTypes.prismButton)
        _selectorRow(
          key: const ValueKey('part-control-action'),
          label: 'Action',
          value: component.actionBinding?.actionId ?? 'None',
          onPressed: () => setState(() => _controlId = 'action'),
        ),
      for (final spec in type.paramsFor(component.effectiveVariant))
        ParamControlRow(
          key: ValueKey('part-control-param:${spec.key}'),
          spec: spec,
          value: spec.coerce(component.effectiveParams[spec.key]),
          palette: host.palette,
          prismStyle: host.dashboard.settings.prismStyle,
          soundEnabled: host.soundEnabled,
          hapticsEnabled: host.hapticsEnabled,
          onChanged: (value) =>
              host.onComponentChanged(component.withParam(spec.key, value)),
        ),
    ];
    return SingleChildScrollView(
      key: ValueKey('part-controls-${component.id}'),
      padding: EdgeInsets.only(bottom: host.safeInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var index = 0; index < controls.length; index++) ...<Widget>[
            controls[index],
            if (index + 1 < controls.length) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _selectorRow({
    required Key key,
    required String label,
    required String value,
    required VoidCallback onPressed,
  }) => Row(
    key: key,
    children: <Widget>[
      Expanded(
        flex: 4,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: VfdLegend(label, palette: host.palette, size: 9),
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        flex: 7,
        child: PrismButton(
          label: value,
          palette: host.palette,
          lit: true,
          role: PrismRole.compact,
          span: PrismSpan.two,
          style: host.dashboard.settings.prismStyle,
          onPressed: onPressed,
        ),
      ),
    ],
  );

  Widget _detail(
    ComponentInstance component,
    ComponentTypeSpec type,
    String controlId,
  ) {
    final control = _controls(
      component,
    ).where((item) => item.id == controlId).firstOrNull;
    if (control == null) {
      _controlId = null;
      return _controlList(component, type);
    }
    final body = switch (controlId) {
      'variant' => _variant(component, type),
      'module' => _module(component),
      'action' => _action(component),
      _ => const SizedBox.shrink(),
    };
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            PrismButton(
              key: const ValueKey('part-control-back'),
              label: 'Back',
              palette: host.palette,
              role: PrismRole.compact,
              style: host.dashboard.settings.prismStyle,
              onPressed: () => setState(() => _controlId = null),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: VfdLegend(
                control.label,
                palette: host.palette,
                lit: true,
                size: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Expanded(child: body),
      ],
    );
  }

  List<_PartControl> _controls(ComponentInstance component) {
    final controls = <_PartControl>[
      const _PartControl('variant', 'Variant'),
      const _PartControl('module', 'Module'),
      if (component.typeId == ComponentTypes.prismButton)
        const _PartControl('action', 'Action'),
    ];
    return controls;
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
        SizedBox(
          height: 74,
          child: _PartVariantPreview(
            component: component,
            type: type,
            dashboard: host.dashboard,
            renderAssets: host.renderAssets,
            palette: host.palette,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: PrismSelectorBank<VariantReference>(
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
        ),
        const SizedBox(height: 6),
        PrismButton(
          label: 'Reset to variant size',
          palette: host.palette,
          role: PrismRole.compact,
          span: PrismSpan.three,
          style: host.dashboard.settings.prismStyle,
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
    final placement = component.placements[host.layoutId];
    if (placement == null) return;
    final variant =
        type.variant(component.effectiveVariant) ?? type.legacyVariantSpec;
    host.onComponentChanged(
      component.withPlacement(
        host.layoutId,
        placement.copyWith(size: variant.recommendedSize),
      ),
    );
  }
}

class _PartVariantPreview extends StatelessWidget {
  const _PartVariantPreview({
    required this.component,
    required this.type,
    required this.dashboard,
    required this.renderAssets,
    required this.palette,
  });

  final ComponentInstance component;
  final ComponentTypeSpec type;
  final Dashboard dashboard;
  final VfdRenderAssets? renderAssets;
  final VfdPalette palette;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF020403),
      border: Border.all(color: palette.unlit.withValues(alpha: 0.5)),
    ),
    child: renderAssets == null
        ? Center(child: VfdLegend('Preview', palette: palette, size: 9))
        : EditorLiveVfdPreview(
            renderAssets: renderAssets!,
            dashboard: _previewDashboard(),
            layoutId: 'preview',
          ),
  );

  Dashboard _previewDashboard() {
    const frame = FrameSpec(width: 2.6, height: 1);
    final recommended =
        type.variant(component.effectiveVariant)?.recommendedSize ??
        type.defaultSize;
    final scale = math.min(
      1,
      math.min(1.8 / recommended.width, 0.58 / recommended.height),
    );
    final size = Size(recommended.width * scale, recommended.height * scale);
    return Dashboard(
      id: 'part.variant.preview',
      name: type.displayName,
      baseLayoutId: 'preview',
      layouts: const <DesignLayout>[DesignLayout(id: 'preview', frame: frame)],
      settings: dashboard.settings,
      components: <ComponentInstance>[
        component.copyWith(
          id: 'part.variant.preview.component',
          moduleId: kMainVfdModuleId,
          placements: <String, Placement>{
            'preview': Placement(center: Offset.zero, size: size),
          },
        ),
      ],
    );
  }
}

class _PartControl {
  const _PartControl(this.id, this.label);

  final String id;
  final String label;
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
      padding: EdgeInsets.fromLTRB(14, 14, 14, 14 + host.safeInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: VfdLegend(
                  module.name,
                  palette: host.palette,
                  lit: true,
                  size: 12,
                ),
              ),
              if (module.id != kMainVfdModuleId)
                _GuardedRemove(
                  itemName: module.name,
                  prismStyle: host.dashboard.settings.prismStyle,
                  soundEnabled: host.soundEnabled,
                  hapticsEnabled: host.hapticsEnabled,
                  onRemove: () => host.onRemoveModule(module),
                ),
            ],
          ),
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

class _GuardedRemove extends StatelessWidget {
  const _GuardedRemove({
    required this.itemName,
    required this.prismStyle,
    required this.soundEnabled,
    required this.hapticsEnabled,
    required this.onRemove,
  });

  final String itemName;
  final PrismStyle prismStyle;
  final bool soundEnabled;
  final bool hapticsEnabled;
  final VoidCallback onRemove;

  static const _dangerPalette = VfdPalette(
    lit: Color(0xFFFF4A3D),
    unlit: Color(0xFF783D38),
  );

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: Semantics(
      label: 'Remove $itemName',
      child: PrismButton(
        key: const ValueKey('remove-arm'),
        label: 'Remove',
        palette: _dangerPalette,
        lit: true,
        role: PrismRole.compact,
        style: prismStyle,
        onPressed: onRemove,
      ),
    ),
  );
}

class _PlacementPanel extends StatelessWidget {
  const _PlacementPanel({required this.host});

  final _EditorServicePanel host;
  static const _nudge = editorFineStep;

  @override
  Widget build(BuildContext context) {
    final component = host.dashboard.components
        .where((item) => item.id == host.selectedId)
        .firstOrNull;
    final module = host.dashboard.modules
        .where((item) => item.id == host.selectedModuleId)
        .firstOrNull;
    final placement =
        component?.placements[host.layoutId] ?? module?.regionIn(host.layoutId);
    if (placement == null) {
      return VfdLegend('Not present in layout', palette: host.palette);
    }
    return PrismPanel(
      palette: host.palette,
      padding: const EdgeInsets.all(9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              VfdLegend('Place', palette: host.palette, lit: true, size: 11),
              const Spacer(),
              VfdLegend(
                'X ${placement.center.dx.toStringAsFixed(3)}  '
                'Y ${placement.center.dy.toStringAsFixed(3)}',
                palette: host.palette,
                lit: true,
                size: 10,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dpadSize = math.min(
                  138.0,
                  math.min(constraints.maxWidth * 0.48, constraints.maxHeight),
                );
                return Row(
                  children: <Widget>[
                    SizedBox(
                      key: const ValueKey('placement-dpad'),
                      width: dpadSize,
                      height: dpadSize,
                      child: _dpad(placement, component, module),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          _sizeRow(
                            'W',
                            placement.size.width,
                            () => _resize(
                              placement,
                              component,
                              module,
                              widthDelta: -_nudge,
                            ),
                            () => _resize(
                              placement,
                              component,
                              module,
                              widthDelta: _nudge,
                            ),
                          ),
                          _sizeRow(
                            'H',
                            placement.size.height,
                            () => _resize(
                              placement,
                              component,
                              module,
                              heightDelta: -_nudge,
                            ),
                            () => _resize(
                              placement,
                              component,
                              module,
                              heightDelta: _nudge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _dpad(
    Placement placement,
    ComponentInstance? component,
    VfdModule? module,
  ) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      _dpadRow(
        null,
        _move(
          'Move up',
          placement,
          component,
          module,
          dy: _nudge,
          shape: PrismShape.triangleUp,
          key: const ValueKey('placement-y+'),
        ),
        null,
      ),
      _dpadRow(
        _move(
          'Move left',
          placement,
          component,
          module,
          dx: -_nudge,
          shape: PrismShape.triangleLeft,
          key: const ValueKey('placement-x-'),
        ),
        _button(
          'Center',
          () => _write(
            component,
            module,
            placement.copyWith(center: Offset.zero),
          ),
          key: const ValueKey('placement-center'),
          symbol: PrismSymbol.center,
          square: true,
        ),
        _move(
          'Move right',
          placement,
          component,
          module,
          dx: _nudge,
          shape: PrismShape.triangleRight,
          key: const ValueKey('placement-x+'),
        ),
      ),
      _dpadRow(
        null,
        _move(
          'Move down',
          placement,
          component,
          module,
          dy: -_nudge,
          shape: PrismShape.triangleDown,
          key: const ValueKey('placement-y-'),
        ),
        null,
      ),
    ],
  );

  Widget _dpadRow(Widget? left, Widget middle, Widget? right) => Expanded(
    child: Row(
      children: <Widget>[
        Expanded(child: left ?? const SizedBox.shrink()),
        Expanded(child: middle),
        Expanded(child: right ?? const SizedBox.shrink()),
      ],
    ),
  );

  Widget _move(
    String label,
    Placement placement,
    ComponentInstance? component,
    VfdModule? module, {
    double dx = 0,
    double dy = 0,
    required PrismShape shape,
    required Key key,
  }) => _button(
    label,
    () => _write(component, module, nudgePlacement(placement, dx: dx, dy: dy)),
    key: key,
    shape: shape,
    face: const SizedBox.shrink(),
  );

  Widget _sizeRow(
    String axis,
    double value,
    VoidCallback decrease,
    VoidCallback increase,
  ) => Row(
    children: <Widget>[
      _button('-', decrease, key: ValueKey('placement-$axis-minus')),
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            VfdLegend(axis, palette: host.palette, size: 9),
            VfdLegend(
              value.toStringAsFixed(3),
              palette: host.palette,
              lit: true,
              size: 11,
            ),
          ],
        ),
      ),
      _button('+', increase, key: ValueKey('placement-$axis-plus')),
    ],
  );

  Widget _button(
    String label,
    VoidCallback onPressed, {
    Key? key,
    PrismShape shape = PrismShape.rectangular,
    Widget? face,
    PrismSymbol? symbol,
    bool square = false,
  }) => PrismButton(
    key: key,
    label: label,
    face: face,
    symbol: symbol,
    shape: shape,
    square: square,
    palette: host.palette,
    role: PrismRole.compact,
    style: host.dashboard.settings.prismStyle,
    onPressed: onPressed,
  );

  void _resize(
    Placement placement,
    ComponentInstance? component,
    VfdModule? module, {
    double widthDelta = 0,
    double heightDelta = 0,
  }) => _write(
    component,
    module,
    resizePlacementFromEdges(
      placement: placement,
      widthDelta: widthDelta,
      heightDelta: heightDelta,
    ),
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
