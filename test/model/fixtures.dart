import 'dart:ui' show Offset, Size;

import 'package:anode/model/component_instance.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/design_layout.dart';
import 'package:anode/model/design_preset.dart';
import 'package:anode/model/optical_profile.dart';
import 'package:anode/model/placement.dart';
import 'package:anode/model/settings.dart';

const wideLayoutId = 'wide';
const tallLayoutId = 'tall';

ComponentInstance digits({
  String id = 'digits',
  Map<String, Placement>? placements,
}) => ComponentInstance(
  id: id,
  typeId: ComponentTypes.speedDigits,
  params: const <String, Object?>{'digits': 3, 'unit': 'kph'},
  placements:
      placements ??
      const <String, Placement>{
        wideLayoutId: Placement(
          center: Offset(0, 0.11),
          size: Size(1.035, 0.588),
        ),
        tallLayoutId: Placement(
          center: Offset(0, 0.20),
          size: Size(1.035, 0.588),
        ),
      },
);

ComponentInstance bar({String id = 'bar'}) => ComponentInstance(
  id: id,
  typeId: ComponentTypes.speedBar,
  params: const <String, Object?>{'cells': 20},
  placements: const <String, Placement>{
    wideLayoutId: Placement(center: Offset(0, -0.33), size: Size(1.96, 0.084)),
  },
);

ComponentInstance altimeter({String id = 'alt'}) => ComponentInstance(
  id: id,
  typeId: ComponentTypes.altitude,
  placements: const <String, Placement>{
    wideLayoutId: Placement(center: Offset(0.8, 0), size: Size(0.5, 0.25)),
  },
);

DesignPreset preset({String id = 'preset.classic', int version = 1}) =>
    DesignPreset(
      id: id,
      name: 'Classic',
      version: version,
      baseLayoutId: wideLayoutId,
      layouts: const <DesignLayout>[
        DesignLayout(id: wideLayoutId, frame: FrameSpec.aspect(2.6)),
        DesignLayout(id: tallLayoutId, frame: FrameSpec.aspect(1 / 2.6)),
      ],
      components: <ComponentInstance>[digits(), bar()],
      defaults: DashboardSettings(
        opticalProfile: OpticalProfile(phosphorName: 'Amber'),
      ),
    );
