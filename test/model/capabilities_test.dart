import 'dart:ui' show Offset, Size;

import 'package:anode/model/capabilities.dart';
import 'package:anode/model/capability.dart';
import 'package:anode/model/component_instance.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/design_layout.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Dashboard dashboardWith(List<ComponentInstance> components) => Dashboard(
  id: 'dash.1',
  name: 'Test',
  baseLayoutId: wideLayoutId,
  layouts: const <DesignLayout>[
    DesignLayout(id: wideLayoutId, frame: FrameSpec.aspect(2.6)),
    DesignLayout(id: tallLayoutId, frame: FrameSpec.aspect(0.5)),
  ],
  components: components,
);

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
      placements: const <String, Placement>{
        wideLayoutId: Placement(center: Offset.zero, size: Size(0.2, 0.1)),
      },
    );
    expect(dashboardWith(<ComponentInstance>[legend]).capabilities(), isEmpty);
  });

  test('capability scope follows selected layout', () {
    final dashboard = dashboardWith(<ComponentInstance>[digits(), altimeter()]);
    expect(dashboard.capabilities(layoutId: wideLayoutId), <Capability>{
      Capability.gps,
      Capability.barometer,
    });
    expect(dashboard.capabilities(layoutId: tallLayoutId), <Capability>{
      Capability.gps,
    });
  });

  test('a component placed in no layout is absent and needs nothing', () {
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
      placements: const <String, Placement>{
        wideLayoutId: Placement(center: Offset.zero, size: Size(0.2, 0.1)),
      },
    );
    expect(dashboardWith(<ComponentInstance>[unknown]).capabilities(), isEmpty);
  });

  test('a weather gauge is what pulls in network permission', () {
    final temp = ComponentInstance(
      id: 'temp',
      typeId: ComponentTypes.outsideTemp,
      placements: const <String, Placement>{
        wideLayoutId: Placement(center: Offset.zero, size: Size(0.2, 0.1)),
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
