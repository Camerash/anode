import 'dart:ui' show Offset, Size;

import 'component_instance.dart';
import 'component_type.dart';
import 'design_preset.dart';
import 'placement.dart';

/// Development scaffolding, NOT an authored preset.
///
/// Shipped presets are authored last, against a model the editor has proven.
/// This exists only so the renderer has a component list to consume before the
/// editor exists, and reproduces the previously hardcoded layout exactly.
DesignPreset developmentPreset() {
  const digitsPlacement = Placement(
    center: Offset(0, 0.11),
    size: Size(1.035, 0.588),
  );
  const barPlacement = Placement(
    center: Offset(0, -0.33),
    size: Size(1.96, 0.084),
  );
  const legendPlacement = Placement(
    center: Offset(0.6815, 0.11),
    size: Size(0.203, 0.242),
  );
  return DesignPreset(
    id: 'dev.classic',
    name: 'Classic',
    version: 1,
    frameSpecs: const <DesignOrientation, FrameSpec>{
      DesignOrientation.landscape: FrameSpec(width: 2.6, height: 1),
    },
    components: <ComponentInstance>[
      ComponentInstance(
        id: 'speed',
        typeId: ComponentTypes.speedDigits,
        params: const <String, Object?>{'digits': 3, 'unit': 'kph'},
        placements: <DesignOrientation, Placement>{
          DesignOrientation.landscape: digitsPlacement,
        },
      ),
      ComponentInstance(
        id: 'bar',
        typeId: ComponentTypes.speedBar,
        params: const <String, Object?>{'cells': 20, 'maxKph': 260.0},
        placements: <DesignOrientation, Placement>{
          DesignOrientation.landscape: barPlacement,
        },
      ),
      ComponentInstance(
        id: 'legend',
        typeId: ComponentTypes.unitLegend,
        placements: <DesignOrientation, Placement>{
          DesignOrientation.landscape: legendPlacement,
        },
      ),
    ],
  );
}
