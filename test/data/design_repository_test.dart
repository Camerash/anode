import 'dart:convert';

import 'package:anode/app_state.dart';
import 'package:anode/data/design_repository.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/design_preset.dart';
import 'package:anode/model/optical_profile.dart';
import 'package:anode/model/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/fixtures.dart';

void main() {
  late DesignPreset source;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    source = preset();
  });

  test('fork, editor changes, active selection and settings persist', () async {
    final preferences = await SharedPreferences.getInstance();
    final first = AnodeState.load(
      repository: DesignRepository(preferences),
      presets: <DesignPreset>[source],
    );

    final fork = first.forkPreset(source, at: DateTime.utc(2026, 7, 27, 12));
    first.updateActiveComponentParam(ComponentTypes.speedDigits, 'digits', 2);
    first.updateGlobalSettings(const GlobalSettings(soundEnabled: false));
    await first.flush();

    final restored = AnodeState.load(
      repository: DesignRepository(preferences),
      presets: <DesignPreset>[source],
    );

    expect(restored.dashboards, hasLength(1));
    expect(restored.activeReference.kind, DesignKind.dashboard);
    expect(restored.activeReference.id, fork.id);
    expect(
      restored.dashboards.single.components.first.effectiveParams['digits'],
      2,
    );
    expect(restored.globalSettings.soundEnabled, isFalse);
  });

  test('activating a preset does not create a dashboard', () async {
    final preferences = await SharedPreferences.getInstance();
    final state = AnodeState.load(
      repository: DesignRepository(preferences),
      presets: <DesignPreset>[source],
    );

    state.activatePreset(source);

    expect(state.activeReference.kind, DesignKind.preset);
    expect(state.dashboards, isEmpty);
  });

  test('customizing an active preset forks before mutation', () async {
    final preferences = await SharedPreferences.getInstance();
    final state = AnodeState.load(
      repository: DesignRepository(preferences),
      presets: <DesignPreset>[source],
    );

    state.updateActiveSettings(source.defaults.copyWith(phosphorName: 'Red'));

    expect(state.dashboards, hasLength(1));
    expect(state.activeReference.kind, DesignKind.dashboard);
    expect(state.dashboards.single.settings.phosphorName, 'Red');
    expect(source.defaults.phosphorName, 'Amber');
  });

  test('legacy global layer booleans migrate into legacy dashboards', () async {
    final legacyDashboard = Dashboard.forkFrom(source, id: 'legacy').toJson();
    (legacyDashboard['settings'] as Map).remove('opticalProfile');
    (legacyDashboard['settings'] as Map)['phosphorName'] = 'Amber';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'anode.dashboards.v1': jsonEncode(<Object?>[legacyDashboard]),
      'anode.globalSettings.v1': jsonEncode(<String, Object?>{
        'demoMode': true,
        'layers': <String, bool>{
          'bloom': false,
          'grain': false,
          'gridMesh': true,
        },
      }),
    });
    final preferences = await SharedPreferences.getInstance();

    final stored = DesignRepository(preferences).load();

    expect(stored.dashboards.single.settings.phosphorName, 'Amber');
    expect(
      stored.dashboards.single.settings.opticalProfile
          .effect(EffectIds.bloom)
          .strength,
      0,
    );
    expect(
      stored.dashboards.single.settings.opticalProfile
          .effect(EffectIds.gridMesh)
          .strength,
      1,
    );
    expect(stored.globalSettings.demoMode, isTrue);
  });
}
