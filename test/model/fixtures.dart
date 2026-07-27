import 'dart:ui' show Offset;

import 'package:anode/model/component_instance.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/design_preset.dart';
import 'package:anode/model/placement.dart';
import 'package:anode/model/settings.dart';

ComponentInstance digits({
  String id = 'digits',
  Map<DesignOrientation, Placement>? placements,
}) =>
    ComponentInstance(
      id: id,
      typeId: ComponentTypes.speedDigits,
      params: const <String, Object?>{'digits': 3, 'unit': 'kph'},
      placements: placements ??
          <DesignOrientation, Placement>{
            DesignOrientation.landscape:
                const Placement(anchor: Anchor.center, offset: Offset(0, 0.11)),
            DesignOrientation.portrait:
                const Placement(anchor: Anchor.center, offset: Offset(0, 0.20)),
          },
    );

ComponentInstance bar({String id = 'bar'}) => ComponentInstance(
      id: id,
      typeId: ComponentTypes.speedBar,
      params: const <String, Object?>{'cells': 20},
      placements: <DesignOrientation, Placement>{
        DesignOrientation.landscape: const Placement(
            anchor: Anchor.bottomCenter, offset: Offset(0, 0.17)),
      },
    );

/// Barometer-backed, landscape only. Used to prove the capability union is
/// scoped per orientation.
ComponentInstance altimeter({String id = 'alt'}) => ComponentInstance(
      id: id,
      typeId: ComponentTypes.altitude,
      placements: <DesignOrientation, Placement>{
        DesignOrientation.landscape:
            const Placement(anchor: Anchor.centerRight, offset: Offset(-0.2, 0)),
      },
    );

DesignPreset preset({String id = 'preset.classic', int version = 1}) =>
    DesignPreset(
      id: id,
      name: 'Classic',
      version: version,
      supportedOrientations: <DesignOrientation>{
        DesignOrientation.landscape,
        DesignOrientation.portrait,
      },
      components: <ComponentInstance>[digits(), bar()],
      defaults: const DashboardSettings(phosphorName: 'Amber'),
    );
