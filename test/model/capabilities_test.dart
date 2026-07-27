import 'package:anode/model/capabilities.dart';
import 'package:anode/model/capability.dart';
import 'package:anode/model/component_instance.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Dashboard dashboardWith(List<ComponentInstance> components) => Dashboard(
      id: 'dash.1',
      name: 'Test',
      supportedOrientations: <DesignOrientation>{
        DesignOrientation.landscape,
        DesignOrientation.portrait,
      },
      components: components,
    );

void main() {
  test('the union covers every component in the dashboard', () {
    final d = dashboardWith(<ComponentInstance>[digits(), bar(), altimeter()]);
    expect(d.capabilities(), <Capability>{Capability.gps, Capability.barometer});
  });

  test('removing the only barometer component drops the barometer', () {
    final d = dashboardWith(<ComponentInstance>[digits(), bar(), altimeter()])
        .withoutComponent('alt');
    expect(d.capabilities(), <Capability>{Capability.gps});
  });

  test('a component needing nothing contributes nothing', () {
    final legend = ComponentInstance(
      id: 'legend',
      typeId: ComponentTypes.unitLegend,
      placements: <DesignOrientation, Placement>{
        DesignOrientation.landscape: const Placement(),
      },
    );
    expect(dashboardWith(<ComponentInstance>[legend]).capabilities(), isEmpty);
  });

  test('scoping to an orientation keeps a sensor off when its gauge is absent',
      () {
    // The altimeter is authored into landscape only.
    final d = dashboardWith(<ComponentInstance>[digits(), altimeter()]);

    expect(d.capabilities(orientation: DesignOrientation.landscape),
        <Capability>{Capability.gps, Capability.barometer});
    expect(d.capabilities(orientation: DesignOrientation.portrait),
        <Capability>{Capability.gps});
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
        DesignOrientation.landscape: const Placement(),
      },
    );
    expect(dashboardWith(<ComponentInstance>[unknown]).capabilities(), isEmpty);
  });

  test('a weather gauge is what pulls in network permission', () {
    final temp = ComponentInstance(
      id: 'temp',
      typeId: ComponentTypes.outsideTemp,
      placements: <DesignOrientation, Placement>{
        DesignOrientation.landscape: const Placement(),
      },
    );

    expect(dashboardWith(<ComponentInstance>[digits()]).capabilities(),
        isNot(contains(Capability.network)));
    expect(dashboardWith(<ComponentInstance>[digits(), temp]).capabilities(),
        contains(Capability.network));
  });

  test('presets answer the same question as dashboards', () {
    expect(preset().capabilities(), <Capability>{Capability.gps});
  });
}
