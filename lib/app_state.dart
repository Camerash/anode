import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/design_repository.dart';
import 'model/dashboard.dart';
import 'model/design.dart';
import 'model/design_preset.dart';
import 'model/settings.dart';

enum DesignKind { preset, dashboard }

@immutable
class DesignReference {
  const DesignReference(this.kind, this.id);

  final DesignKind kind;
  final String id;

  String get storageKey => '${kind.name}:$id';

  static DesignReference? parse(String? raw) {
    if (raw == null) return null;
    final separator = raw.indexOf(':');
    if (separator < 1) return null;
    final kindName = raw.substring(0, separator);
    final id = raw.substring(separator + 1);
    for (final kind in DesignKind.values) {
      if (kind.name == kindName && id.isNotEmpty) {
        return DesignReference(kind, id);
      }
    }
    return null;
  }
}

/// App-level design state. UI mutates immutable model snapshots through here;
/// persistence is debounced so pointer drags do not write on every frame.
class AnodeState extends ChangeNotifier {
  AnodeState._({
    required DesignRepository repository,
    required List<DesignPreset> presets,
    required List<Dashboard> dashboards,
    required DesignReference activeReference,
    required GlobalSettings globalSettings,
  }) : _repository = repository,
       presets = List<DesignPreset>.unmodifiable(presets),
       _dashboards = dashboards,
       _activeReference = activeReference,
       _globalSettings = globalSettings;

  static AnodeState load({
    required DesignRepository repository,
    required List<DesignPreset> presets,
  }) {
    if (presets.isEmpty) {
      throw ArgumentError.value(presets, 'presets', 'must not be empty');
    }
    final stored = repository.load();
    final requested = DesignReference.parse(stored.activeDesignKey);
    final fallback = DesignReference(DesignKind.preset, presets.first.id);
    final active = _exists(requested, presets, stored.dashboards)
        ? requested!
        : fallback;
    return AnodeState._(
      repository: repository,
      presets: presets,
      dashboards: stored.dashboards,
      activeReference: active,
      globalSettings: stored.globalSettings,
    );
  }

  final DesignRepository _repository;
  final List<DesignPreset> presets;
  List<Dashboard> _dashboards;
  DesignReference _activeReference;
  GlobalSettings _globalSettings;
  Timer? _saveTimer;

  List<Dashboard> get dashboards => List<Dashboard>.unmodifiable(_dashboards);
  DesignReference get activeReference => _activeReference;
  GlobalSettings get globalSettings => _globalSettings;
  Dashboard? get activeDashboard =>
      activeDesign is Dashboard ? activeDesign as Dashboard : null;
  bool get activeDesignEditable => activeDashboard != null;

  Design get activeDesign {
    final design = designFor(_activeReference);
    return design ?? presets.first;
  }

  Design? designFor(DesignReference reference) {
    final source = reference.kind == DesignKind.preset ? presets : _dashboards;
    for (final design in source) {
      if (design.id == reference.id) return design;
    }
    return null;
  }

  bool isActive(DesignKind kind, String id) =>
      _activeReference.kind == kind && _activeReference.id == id;

  void activatePreset(DesignPreset preset) =>
      _activate(DesignReference(DesignKind.preset, preset.id));

  void activateDashboard(Dashboard dashboard) =>
      _activate(DesignReference(DesignKind.dashboard, dashboard.id));

  Dashboard forkPreset(DesignPreset preset, {DateTime? at, String? name}) {
    final forkedAt = at ?? DateTime.now();
    final dashboard = Dashboard.forkFrom(
      preset,
      id: _nextDashboardId(preset.id, forkedAt),
      name: name ?? '${preset.name} copy',
      at: forkedAt,
    );
    _dashboards = <Dashboard>[..._dashboards, dashboard];
    _activeReference = DesignReference(DesignKind.dashboard, dashboard.id);
    notifyListeners();
    _scheduleSave();
    return dashboard;
  }

  Dashboard cloneDashboard(Dashboard source, {DateTime? at, String? name}) {
    final clonedAt = at ?? DateTime.now();
    final dashboard = Dashboard.cloneFrom(
      source,
      id: _nextDashboardId(source.id, clonedAt),
      name: name ?? '${source.name} copy',
      at: clonedAt,
    );
    _dashboards = <Dashboard>[..._dashboards, dashboard];
    _activeReference = DesignReference(DesignKind.dashboard, dashboard.id);
    notifyListeners();
    _scheduleSave();
    return dashboard;
  }

  Dashboard customizeActiveDesign({DateTime? at}) {
    final active = activeDesign;
    if (active is Dashboard) return active;
    return forkPreset(active as DesignPreset, at: at);
  }

  void updateDashboard(Dashboard dashboard) {
    final index = _dashboards.indexWhere((value) => value.id == dashboard.id);
    if (index < 0) {
      throw ArgumentError.value(dashboard.id, 'dashboard.id', 'not found');
    }
    final next = <Dashboard>[..._dashboards]..[index] = dashboard;
    _dashboards = next;
    notifyListeners();
    _scheduleSave();
  }

  void updateActiveComponentParam(String typeId, String key, Object? value) {
    var dashboard = _dashboardForCustomization();
    for (final component in dashboard.components) {
      if (component.typeId != typeId) continue;
      dashboard = dashboard.withComponent(component.withParam(key, value));
    }
    updateDashboard(dashboard);
  }

  void updateActiveSettings(DashboardSettings settings) {
    final dashboard = _dashboardForCustomization();
    updateDashboard(dashboard.copyWith(settings: settings));
  }

  void updateEditableActiveSettings(DashboardSettings settings) {
    final dashboard = activeDashboard;
    if (dashboard == null) {
      throw StateError('Customize the active preset before changing it.');
    }
    updateDashboard(dashboard.copyWith(settings: settings));
  }

  void updateGlobalSettings(GlobalSettings settings) {
    _globalSettings = settings;
    notifyListeners();
    _scheduleSave();
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _save();
  }

  void _activate(DesignReference reference) {
    if (_activeReference.storageKey == reference.storageKey) return;
    _activeReference = reference;
    notifyListeners();
    _scheduleSave();
  }

  Dashboard _dashboardForCustomization() {
    final active = activeDesign;
    if (active is Dashboard) return active;
    return forkPreset(active as DesignPreset);
  }

  String _nextDashboardId(String presetId, DateTime at) {
    final base = '$presetId.${at.microsecondsSinceEpoch}';
    var candidate = base;
    var suffix = 2;
    while (_dashboards.any((dashboard) => dashboard.id == candidate)) {
      candidate = '$base.$suffix';
      suffix++;
    }
    return candidate;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), () {
      _saveTimer = null;
      unawaited(_save());
    });
  }

  Future<void> _save() => _repository.save(
    dashboards: _dashboards,
    activeDesignKey: _activeReference.storageKey,
    globalSettings: _globalSettings,
  );

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(_save());
    super.dispose();
  }

  static bool _exists(
    DesignReference? reference,
    List<DesignPreset> presets,
    List<Dashboard> dashboards,
  ) {
    if (reference == null) return false;
    final source = reference.kind == DesignKind.preset ? presets : dashboards;
    return source.any((design) => design.id == reference.id);
  }
}
