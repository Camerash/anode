import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/dashboard.dart';
import '../model/optical_profile.dart';
import '../model/settings.dart';

class StoredDesignState {
  const StoredDesignState({
    required this.dashboards,
    required this.activeDesignKey,
    required this.globalSettings,
  });

  final List<Dashboard> dashboards;
  final String? activeDesignKey;
  final GlobalSettings globalSettings;
}

/// Shared-preferences persistence for small user-authored design payloads.
///
/// Presets never enter this store: they ship with the app and remain immutable.
class DesignRepository {
  DesignRepository(this._preferences);

  static const _dashboardsKey = 'anode.dashboards.v1';
  static const _activeDesignKey = 'anode.activeDesign.v1';
  static const _globalSettingsKey = 'anode.globalSettings.v1';

  final SharedPreferences _preferences;

  StoredDesignState load() {
    final rawGlobal = _loadGlobalSettingsMap();
    return StoredDesignState(
      dashboards: _loadDashboards(
        legacyEffects: _legacyEffects(rawGlobal['layers']),
      ),
      activeDesignKey: _preferences.getString(_activeDesignKey),
      globalSettings: GlobalSettings.fromJson(rawGlobal),
    );
  }

  Future<void> save({
    required List<Dashboard> dashboards,
    required String activeDesignKey,
    required GlobalSettings globalSettings,
  }) async {
    await Future.wait(<Future<bool>>[
      _preferences.setString(
        _dashboardsKey,
        jsonEncode(dashboards.map((dashboard) => dashboard.toJson()).toList()),
      ),
      _preferences.setString(_activeDesignKey, activeDesignKey),
      _preferences.setString(
        _globalSettingsKey,
        jsonEncode(globalSettings.toJson()),
      ),
    ]);
  }

  List<Dashboard> _loadDashboards({
    required Map<String, EffectSetting> legacyEffects,
  }) {
    final raw = _decodeMapList(_preferences.getString(_dashboardsKey));
    final dashboards = <Dashboard>[];
    for (final value in raw) {
      try {
        var dashboard = Dashboard.fromJson(value);
        final settings =
            (value['settings'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{};
        if (!settings.containsKey('opticalProfile') &&
            legacyEffects.isNotEmpty) {
          dashboard = dashboard.copyWith(
            settings: dashboard.settings.copyWith(
              opticalProfile: OpticalProfile(
                phosphorName: dashboard.settings.phosphorName,
                effects: legacyEffects,
              ),
            ),
          );
        }
        dashboards.add(dashboard);
      } on Object {
        // One damaged user dashboard must not prevent every other design from
        // loading. The invalid payload remains in preferences until next save.
      }
    }
    return dashboards;
  }

  Map<String, Object?> _loadGlobalSettingsMap() {
    final raw = _preferences.getString(_globalSettingsKey);
    if (raw == null) return const <String, Object?>{};
    try {
      return (jsonDecode(raw) as Map).cast<String, Object?>();
    } on Object {
      return const <String, Object?>{};
    }
  }

  Map<String, EffectSetting> _legacyEffects(Object? raw) {
    final layers = (raw as Map?)?.cast<String, Object?>();
    if (layers == null) return const <String, EffectSetting>{};
    const ids = <String, String>{
      'bloom': EffectIds.bloom,
      'unlitSegments': EffectIds.unlitPhosphor,
      'gridMesh': EffectIds.gridMesh,
      'filamentWires': EffectIds.filamentWires,
      'grain': EffectIds.glassGrain,
      'phosphorDecay': EffectIds.phosphorDecay,
      'tiltParallax': EffectIds.tiltParallax,
    };
    return <String, EffectSetting>{
      for (final entry in ids.entries)
        if (layers[entry.key] is bool)
          entry.value: EffectSetting(
            strength: layers[entry.key] as bool ? 1 : 0,
            resumeStrength: 1,
          ),
    };
  }

  List<Map<String, Object?>> _decodeMapList(String? raw) {
    if (raw == null) return const <Map<String, Object?>>[];
    try {
      return <Map<String, Object?>>[
        for (final value in jsonDecode(raw) as List)
          (value as Map).cast<String, Object?>(),
      ];
    } on Object {
      return const <Map<String, Object?>>[];
    }
  }
}
