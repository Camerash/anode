import 'dart:convert';
import 'dart:ui' show Size;

import 'package:anode/model/component_instance.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/design.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('a fork snapshots the preset wholesale', () {
    final p = preset();
    final d = Dashboard.forkFrom(p, id: 'dash.1');

    expect(d.components.map((c) => c.id), p.components.map((c) => c.id));
    expect(d.baseLayoutId, p.baseLayoutId);
    expect(
      d.layouts.map((layout) => layout.id),
      p.layouts.map((layout) => layout.id),
    );
    expect(d.settings.phosphorName, 'Amber');
  });

  test('the fork records provenance and nothing more', () {
    final d = Dashboard.forkFrom(preset(version: 3), id: 'dash.1');
    expect(d.sourcePresetId, 'preset.classic');
    expect(d.sourcePresetVersion, 3);
    expect(d.forkedAt, isNotNull);
  });

  test('editing a fork leaves the source preset untouched', () {
    final p = preset();
    final before = jsonEncode(p.toJson());

    final d = Dashboard.forkFrom(p, id: 'dash.1')
        .withComponent(digits().withParam('digits', 4))
        .withoutComponent('bar')
        .copyWith(name: 'My Classic');

    expect(d.components.map((c) => c.id), <String>['digits']);
    expect(d.components.first.effectiveParams['digits'], 4);
    expect(jsonEncode(p.toJson()), before);
  });

  test('moving a component in the fork does not move it in the preset', () {
    final p = preset();
    final d = Dashboard.forkFrom(p, id: 'dash.1');

    final moved = d.withComponent(
      d.components.first.withPlacement(
        tallLayoutId,
        const Placement(center: Offset(0.4, -0.1), size: Size(1.035, 0.588)),
      ),
    );

    expect(
      moved.components.first.placements[tallLayoutId]!.center,
      const Offset(0.4, -0.1),
    );
    expect(
      p.components.first.placements[tallLayoutId]!.center,
      const Offset(0, 0.20),
    );
  });

  test('dropping a component from one layout keeps the other', () {
    final d = Dashboard.forkFrom(preset(), id: 'dash.1');
    final edited = d.withComponent(
      d.components.first.withPlacement(tallLayoutId, null),
    );

    final c = edited.components.first;
    expect(c.appearsIn(tallLayoutId), isFalse);
    expect(c.appearsIn(wideLayoutId), isTrue);
    expect(edited.componentsIn(tallLayoutId), isEmpty);
    expect(edited.componentsIn(wideLayoutId), hasLength(2));
  });

  test('reordering is stable and does not lose components', () {
    final d = Dashboard.forkFrom(preset(), id: 'dash.1');
    final reordered = d.reorderComponent(0, 1);
    expect(reordered.components.map((c) => c.id), <String>['bar', 'digits']);
    expect(reordered.components, hasLength(d.components.length));
  });

  test('a map handed to the constructor cannot be mutated afterwards', () {
    final params = <String, Object?>{'digits': 3};
    final c = ComponentInstance(
      id: 'd',
      typeId: ComponentTypes.speedDigits,
      params: params,
    );

    params['digits'] = 1;

    expect(c.params['digits'], 3);
    expect(() => c.params['digits'] = 2, throwsUnsupportedError);
  });
}
