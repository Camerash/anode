import 'dart:ui' show Offset, Size;

import 'package:anode/model/capabilities.dart';
import 'package:anode/model/capability.dart';
import 'package:anode/model/component_instance.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Dashboard dashboardWith(List<ComponentInstance> components) =>
    Dashboard(id: 'dash.1', name: 'Test', components: components);

void main() {
  test('the union covers every component in the dashboard', () {
    final d = dashboardWith(<ComponentInstance>[digits(), bar(), altimeter()]);
    expect(d.capabilities(), <Capability>{
      Capability.gps,
      Capability.barometer,
    });
  });

  test('removing the only barometer component drops the barometer', () {
    final d = dashboardWith(<ComponentInstance>[
      digits(),
      bar(),
      altimeter(),
    ]).withoutComponent('alt');
    expect(d.capabilities(), <Capability>{Capability.gps});
  });

  test('a component needing nothing contributes nothing', () {
    final legend = ComponentInstance(
      id: 'legend',
      typeId: ComponentTypes.unitLegend,
      placements: <DesignOrientation, Placement>{
        DesignOrientation.landscape: const Placement(
          center: Offset.zero,
          size: Size(0.2, 0.1),
        ),
      },
    );
    expect(dashboardWith(<ComponentInstance>[legend]).capabilities(), isEmpty);
  });

  test('viewport capability scope follows resolved authored layout', () {
    // The altimeter is authored into landscape only.
    final primaryOnly = dashboardWith(<ComponentInstance>[
      digits(),
      altimeter(),
    ]);
    final withPortrait = primaryOnly.copyWith(
      frameSpecs: const <DesignOrientation, FrameSpec>{
        DesignOrientation.landscape: FrameSpec.aspect(2.6),
        DesignOrientation.portrait: FrameSpec.aspect(0.5),
      },
    );

    expect(
      primaryOnly.capabilities(orientation: DesignOrientation.portrait),
      <Capability>{Capability.gps, Capability.barometer},
    );
    expect(
      withPortrait.capabilities(orientation: DesignOrientation.portrait),
      <Capability>{Capability.gps},
    );
  });

  test('a component placed in no orientation is absent and needs nothing', () {
    final orphan = ComponentInstance(
      id: 'orphan',
      typeId: ComponentTypes.altitude,
    );
    expect(dashboardWith(<ComponentInstance>[orphan]).capabilities(), isEmpty);
  });

  test('a type this build does not know contributes nothing', () {
    final unknown = ComponentInstance(
      id: 'x',
      typeId: 'gauge.from.the.future',
      placements: <DesignOrientation, Placement>{
        DesignOrientation.landscape: const Placement(
          center: Offset.zero,
          size: Size(0.2, 0.1),
        ),
      },
    );
    expect(dashboardWith(<ComponentInstance>[unknown]).capabilities(), isEmpty);
  });

  test('a weather gauge is what pulls in network permission', () {
    final temp = ComponentInstance(
      id: 'temp',
      typeId: ComponentTypes.outsideTemp,
      placements: <DesignOrientation, Placement>{
        DesignOrientation.landscape: const Placement(
          center: Offset.zero,
          size: Size(0.2, 0.1),
        ),
      },
    );

    expect(
      dashboardWith(<ComponentInstance>[digits()]).capabilities(),
      isNot(contains(Capability.network)),
    );
    expect(
      dashboardWith(<ComponentInstance>[digits(), temp]).capabilities(),
      contains(Capability.network),
    );
  });

  test('presets answer the same question as dashboards', () {
    expect(preset().capabilities(), <Capability>{Capability.gps});
  });
}
