import 'dart:convert';
import 'package:anode/model/component_instance.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/design_preset.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Round tripping through a real encode/decode catches types that only look
/// serializable, which comparing object graphs would miss.
Map<String, Object?> reencode(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  test('preset survives a json round trip', () {
    final original = preset();
    final back = DesignPreset.fromJson(reencode(original.toJson()));
    expect(jsonEncode(back.toJson()), jsonEncode(original.toJson()));
  });

  test('dashboard survives a json round trip, provenance included', () {
    final original = Dashboard.forkFrom(preset(),
        id: 'dash.1', at: DateTime.utc(2026, 7, 27, 9, 30));
    final back = Dashboard.fromJson(reencode(original.toJson()));

    expect(jsonEncode(back.toJson()), jsonEncode(original.toJson()));
    expect(back.sourcePresetId, 'preset.classic');
    expect(back.sourcePresetVersion, 1);
    expect(back.forkedAt, DateTime.utc(2026, 7, 27, 9, 30));
  });

  test('per-orientation placements survive independently', () {
    final back = DesignPreset.fromJson(reencode(preset().toJson()));
    final d = back.components.firstWhere((c) => c.id == 'digits');

    expect(d.placements[DesignOrientation.portrait]!.offset,
        const Offset(0, 0.20));
    expect(d.placements[DesignOrientation.landscape]!.offset,
        const Offset(0, 0.11));
  });

  test('a component type this build does not know is dropped, not thrown', () {
    final json = preset().toJson();
    (json['components'] as List).add(<String, Object?>{
      'id': 'mystery',
      'typeId': 'gauge.from.the.future',
      'params': <String, Object?>{},
      'placements': <String, Object?>{
        'landscape': const Placement().toJson(),
      },
    });

    final back = DesignPreset.fromJson(reencode(json));
    expect(back.components.map((c) => c.id), <String>['digits', 'bar']);
  });

  test('an unknown orientation key is ignored, known ones survive', () {
    final json = preset().toJson();
    final first = (json['components'] as List).first as Map<String, Object?>;
    (first['placements'] as Map)['skewLeft'] = const Placement().toJson();

    final back = DesignPreset.fromJson(reencode(json));
    final d = back.components.first;
    expect(d.placements.keys.map((o) => o.name).toSet(),
        <String>{'landscape', 'portrait'});
  });

  test('params a newer build wrote are preserved, not silently dropped', () {
    final instance = digits().withParam('futureTuning', 42);
    final back = ComponentInstance.fromJson(reencode(instance.toJson()));
    expect(back.params['futureTuning'], 42);
  });

  test('effectiveParams fills defaults without mutating what was stored', () {
    final instance = ComponentInstance(
      id: 'd',
      typeId: ComponentTypes.speedDigits,
      params: const <String, Object?>{'digits': 2},
    );

    expect(instance.params.containsKey('blankLeadingZeros'), isFalse);
    expect(instance.effectiveParams['blankLeadingZeros'], isTrue);
    expect(instance.effectiveParams['digits'], 2);
  });

  test('a stored param outside its range is clamped on read', () {
    final instance = ComponentInstance(
      id: 'd',
      typeId: ComponentTypes.speedDigits,
      params: const <String, Object?>{'digits': 99},
    );
    expect(instance.effectiveParams['digits'], 4);
  });

  test('every schema payload carries a version', () {
    expect(preset().toJson()['schemaVersion'], kSchemaVersion);
    expect(
      Dashboard.forkFrom(preset(), id: 'd').toJson()['schemaVersion'],
      kSchemaVersion,
    );
  });
}
