import 'dart:convert';

import 'package:anode/model/component_instance.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/design_preset.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('opposite viewport falls back wholesale to primary layout', () {
    final source = DesignPreset(
      id: 'primary',
      name: 'Primary',
      version: 1,
      frameSpecs: const <DesignOrientation, FrameSpec>{
        DesignOrientation.landscape: FrameSpec.aspect(2.4),
      },
      components: <ComponentInstance>[digits()],
    );

    expect(source.primaryOrientation, DesignOrientation.landscape);
    expect(source.authoredOrientations, <DesignOrientation>{
      DesignOrientation.landscape,
    });
    expect(
      source.layoutForViewport(DesignOrientation.portrait),
      DesignOrientation.landscape,
    );
    expect(source.frameAspect(DesignOrientation.portrait), 2.4);
    expect(
      source.componentsIn(DesignOrientation.portrait).single.id,
      source.components.single.id,
    );
  });

  test(
    'explicit alternate layout and primary identity survive json and fork',
    () {
      final source = DesignPreset(
        id: 'aspects',
        name: 'Aspects',
        version: 1,
        primaryOrientation: DesignOrientation.portrait,
        frameSpecs: const <DesignOrientation, FrameSpec>{
          DesignOrientation.landscape: FrameSpec.aspect(2.4),
          DesignOrientation.portrait: FrameSpec.aspect(0.6),
        },
        components: <ComponentInstance>[digits()],
      );
      final encoded = (jsonDecode(jsonEncode(source.toJson())) as Map)
          .cast<String, Object?>();
      final roundTrip = DesignPreset.fromJson(encoded);
      final dashboard = Dashboard.forkFrom(roundTrip, id: 'fork');

      expect(roundTrip.primaryOrientation, DesignOrientation.portrait);
      expect(dashboard.primaryOrientation, DesignOrientation.portrait);
      expect(dashboard.frameAspect(DesignOrientation.landscape), 2.4);
      expect(dashboard.frameAspect(DesignOrientation.portrait), 0.6);
    },
  );

  test('creating alternate bakes contained primary appearance', () {
    final component = ComponentInstance(
      id: 'placed',
      typeId: 'unknown',
      placements: const <DesignOrientation, Placement>{
        DesignOrientation.landscape: Placement(
          center: Offset(0.4, 0.2),
          size: Size(0.8, 0.4),
        ),
      },
    );
    final source = Dashboard(
      id: 'source',
      name: 'Source',
      frameSpecs: const <DesignOrientation, FrameSpec>{
        DesignOrientation.landscape: FrameSpec.aspect(2),
      },
      components: <ComponentInstance>[component],
    );
    final baked = source.withBakedLayout(
      DesignOrientation.portrait,
      extent: const Size(2, 4),
    );
    final placement =
        baked.components.single.placements[DesignOrientation.portrait]!;

    expect(baked.hasAuthoredLayout(DesignOrientation.portrait), isTrue);
    expect(baked.frameExtent(DesignOrientation.portrait), const Size(2, 4));
    // Verbatim. The envelope grows; the geometry inside it does not move or
    // shrink, which is what keeps the optical layer at the same scale too.
    expect(placement.center, const Offset(0.4, 0.2));
    expect(placement.size, const Size(0.8, 0.4));
  });

  test('resetting alternate removes its placements and restores fallback', () {
    final source = Dashboard.forkFrom(preset(), id: 'source');
    final reset = source.withoutLayout(DesignOrientation.portrait);

    expect(reset.hasAuthoredLayout(DesignOrientation.portrait), isFalse);
    expect(
      reset.layoutForViewport(DesignOrientation.portrait),
      DesignOrientation.landscape,
    );
    expect(
      reset.components.any(
        (component) =>
            component.placements.containsKey(DesignOrientation.portrait),
      ),
      isFalse,
    );
  });

  test('legacy frame aspects decode as explicit fixed layouts', () {
    final legacy = preset().toJson()
      ..remove('primaryOrientation')
      ..remove('frameSpecs')
      ..['supportedOrientations'] = <String>['landscape', 'portrait']
      ..['frameAspects'] = <String, Object?>{'landscape': 2.4, 'portrait': 0.6};
    final decoded = DesignPreset.fromJson(legacy);

    expect(decoded.primaryOrientation, DesignOrientation.landscape);
    expect(decoded.frameAspect(DesignOrientation.landscape), 2.4);
    expect(decoded.frameAspect(DesignOrientation.portrait), 0.6);
  });
}
