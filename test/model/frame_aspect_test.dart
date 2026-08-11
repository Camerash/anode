import 'dart:convert';
import 'dart:ui' show Offset, Size;

import 'package:anode/model/component_instance.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/design.dart';
import 'package:anode/model/design_layout.dart';
import 'package:anode/model/design_preset.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('one layout contain-fits all viewport shapes', () {
    final source = DesignPreset(
      id: 'single',
      name: 'Single',
      version: 1,
      baseLayoutId: wideLayoutId,
      layouts: const <DesignLayout>[
        DesignLayout(id: wideLayoutId, frame: FrameSpec.aspect(2.4)),
      ],
      components: <ComponentInstance>[digits()],
    );

    expect(source.layoutForViewport(const Size(390, 844)), wideLayoutId);
    expect(source.frameAspect(wideLayoutId), 2.4);
    expect(source.componentsIn(wideLayoutId).single.id, 'digits');
  });

  test('adapt selects nearest layout ratio', () {
    final source = preset();

    expect(source.layoutForViewport(const Size(844, 390)), wideLayoutId);
    expect(source.layoutForViewport(const Size(390, 844)), tallLayoutId);
  });

  test('lock selects one layout for all viewport shapes', () {
    final source = Dashboard.forkFrom(preset(), id: 'locked').copyWith(
      screenSetup: const ScreenSetup.lock(
        layoutId: wideLayoutId,
        orientation: ViewportOrientation.landscape,
      ),
    );

    expect(source.layoutForViewport(const Size(390, 844)), wideLayoutId);
    expect(source.layoutForViewport(const Size(844, 390)), wideLayoutId);
  });

  test('layouts and screen setup survive JSON and fork', () {
    final source = DesignPreset(
      id: 'layouts',
      name: 'Layouts',
      version: 1,
      baseLayoutId: tallLayoutId,
      layouts: const <DesignLayout>[
        DesignLayout(id: wideLayoutId, frame: FrameSpec.aspect(2.4)),
        DesignLayout(id: tallLayoutId, frame: FrameSpec.aspect(0.6)),
      ],
      screenSetup: const ScreenSetup.lock(
        layoutId: tallLayoutId,
        orientation: ViewportOrientation.portrait,
      ),
      components: <ComponentInstance>[digits()],
    );
    final encoded = (jsonDecode(jsonEncode(source.toJson())) as Map)
        .cast<String, Object?>();
    final roundTrip = DesignPreset.fromJson(encoded);
    final dashboard = Dashboard.forkFrom(roundTrip, id: 'fork');

    expect(roundTrip.baseLayoutId, tallLayoutId);
    expect(dashboard.screenSetup.lockedLayoutId, tallLayoutId);
    expect(dashboard.frameAspect(wideLayoutId), 2.4);
    expect(dashboard.frameAspect(tallLayoutId), 0.6);
  });

  test('new layout copies geometry without changing optical scale', () {
    const placement = Placement(center: Offset(0.4, 0.2), size: Size(0.8, 0.4));
    final source = Dashboard(
      id: 'source',
      name: 'Source',
      baseLayoutId: wideLayoutId,
      layouts: const <DesignLayout>[
        DesignLayout(id: wideLayoutId, frame: FrameSpec.aspect(2)),
      ],
      components: <ComponentInstance>[
        ComponentInstance(
          id: 'placed',
          typeId: 'unknown',
          placements: const <String, Placement>{wideLayoutId: placement},
        ),
      ],
    );
    final created = source.withLayout(
      id: tallLayoutId,
      aspect: 0.5,
      sourceLayoutId: wideLayoutId,
    );

    expect(created.frameExtent(tallLayoutId), const Size(2, 4));
    expect(created.components.single.placements[tallLayoutId], same(placement));
  });

  test('removing layout removes placements and clears its lock', () {
    final source = Dashboard.forkFrom(preset(), id: 'source').copyWith(
      screenSetup: const ScreenSetup.lock(
        layoutId: tallLayoutId,
        orientation: ViewportOrientation.portrait,
      ),
    );
    final reset = source.withoutLayout(tallLayoutId);

    expect(reset.layouts.map((layout) => layout.id), <String>[wideLayoutId]);
    expect(reset.screenSetup.behavior, ScreenBehavior.adapt);
    expect(
      reset.components.any(
        (component) => component.placements.containsKey(tallLayoutId),
      ),
      isFalse,
    );
  });
}
