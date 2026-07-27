import 'package:anode/app_state.dart';
import 'package:anode/data/design_repository.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/design_preset.dart';
import 'package:anode/model/settings.dart';
import 'package:anode/vfd/vfd_layers.dart';
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
    first.updateGlobalSettings(
      const GlobalSettings(layers: VfdLayers(grain: false)),
    );
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
    expect(restored.globalSettings.layers.grain, isFalse);
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
}
