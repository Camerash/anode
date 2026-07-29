import 'dart:ui' show Offset, Size;

import 'package:anode/model/component_instance.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/design_preset.dart';
import 'package:anode/model/optical_profile.dart';
import 'package:anode/model/placement.dart';
import 'package:anode/model/settings.dart';

ComponentInstance digits({
  String id = 'digits',
  Map<DesignOrientation, Placement>? placements,
}) => ComponentInstance(
  id: id,
  typeId: ComponentTypes.speedDigits,
  params: const <String, Object?>{'digits': 3, 'unit': 'kph'},
  placements:
      placements ??
      <DesignOrientation, Placement>{
        DesignOrientation.landscape: const Placement(
          center: Offset(0, 0.11),
          size: Size(1.035, 0.588),
        ),
        DesignOrientation.portrait: const Placement(
          center: Offset(0, 0.20),
          size: Size(1.035, 0.588),
        ),
      },
);

ComponentInstance bar({String id = 'bar'}) => ComponentInstance(
  id: id,
  typeId: ComponentTypes.speedBar,
  params: const <String, Object?>{'cells': 20},
  placements: <DesignOrientation, Placement>{
    DesignOrientation.landscape: const Placement(
      center: Offset(0, -0.33),
      size: Size(1.96, 0.084),
    ),
  },
);

/// Barometer-backed, landscape only. Used to prove the capability union is
/// scoped per orientation.
ComponentInstance altimeter({String id = 'alt'}) => ComponentInstance(
  id: id,
  typeId: ComponentTypes.altitude,
  placements: <DesignOrientation, Placement>{
    DesignOrientation.landscape: const Placement(
      center: Offset(0.8, 0),
      size: Size(0.5, 0.25),
    ),
  },
);

DesignPreset preset({String id = 'preset.classic', int version = 1}) =>
    DesignPreset(
      id: id,
      name: 'Classic',
      version: version,
      frameSpecs: const <DesignOrientation, FrameSpec>{
        DesignOrientation.landscape: FrameSpec.aspect(2.6),
        DesignOrientation.portrait: FrameSpec.aspect(1 / 2.6),
      },
      components: <ComponentInstance>[digits(), bar()],
      defaults: DashboardSettings(
        opticalProfile: OpticalProfile(phosphorName: 'Amber'),
      ),
    );
