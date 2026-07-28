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
  const digitsPlacement = Placement(offset: Offset(0, 0.11));
  const barPlacement = Placement(offset: Offset(0, -0.33));
  const legendPlacement = Placement(offset: Offset(0.6815, 0.11));
  const portraitDigitsPlacement = Placement(
    offset: Offset(-0.025, 0.12),
    size: Size(0.31, 0.46),
  );
  const portraitBarPlacement = Placement(
    offset: Offset(0, -0.27),
    size: Size(0.31, 0.05),
  );
  const portraitLegendPlacement = Placement(
    offset: Offset(0.125, 0.12),
    size: Size(0.075, 0.16),
  );

  return DesignPreset(
    id: 'dev.classic',
    name: 'Classic',
    version: 1,
    supportedOrientations: <DesignOrientation>{
      DesignOrientation.landscape,
      DesignOrientation.portrait,
    },
    frameSpecs: const <DesignOrientation, FrameSpec>{
      DesignOrientation.landscape: FrameSpec(referenceAspect: 2.6),
      DesignOrientation.portrait: FrameSpec(referenceAspect: 1 / 2.6),
    },
    components: <ComponentInstance>[
      ComponentInstance(
        id: 'speed',
        typeId: ComponentTypes.speedDigits,
        params: const <String, Object?>{'digits': 3, 'unit': 'kph'},
        placements: <DesignOrientation, Placement>{
          DesignOrientation.landscape: digitsPlacement,
          DesignOrientation.portrait: portraitDigitsPlacement,
        },
      ),
      ComponentInstance(
        id: 'bar',
        typeId: ComponentTypes.speedBar,
        params: const <String, Object?>{'cells': 20, 'maxKph': 260.0},
        placements: <DesignOrientation, Placement>{
          DesignOrientation.landscape: barPlacement,
          DesignOrientation.portrait: portraitBarPlacement,
        },
      ),
      ComponentInstance(
        id: 'legend',
        typeId: ComponentTypes.unitLegend,
        placements: <DesignOrientation, Placement>{
          DesignOrientation.landscape: legendPlacement,
          DesignOrientation.portrait: portraitLegendPlacement,
        },
      ),
    ],
  );
}
