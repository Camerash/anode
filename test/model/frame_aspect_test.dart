import 'dart:convert';

import 'package:anode/model/component_instance.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/design_preset.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('viewport aspect is normalized to authored orientation', () {
    expect(
      orientViewportAspect(16 / 9, DesignOrientation.portrait),
      closeTo(9 / 16, 1e-9),
    );
    expect(
      orientViewportAspect(9 / 16, DesignOrientation.landscape),
      closeTo(16 / 9, 1e-9),
    );
  });

  test('preset and fork preserve authored aspects per orientation', () {
    final source = DesignPreset(
      id: 'aspects',
      name: 'Aspects',
      version: 1,
      supportedOrientations: DesignOrientation.values.toSet(),
      frameAspects: const <DesignOrientation, double>{
        DesignOrientation.landscape: 2.4,
        DesignOrientation.portrait: 0.6,
      },
      components: <ComponentInstance>[digits()],
    );

    final dashboard = Dashboard.forkFrom(source, id: 'fork');

    expect(dashboard.frameAspect(DesignOrientation.landscape), 2.4);
    expect(dashboard.frameAspect(DesignOrientation.portrait), 0.6);
  });

  test('fixed frame specs survive json and resolve to authored aspect', () {
    final encoded = jsonDecode(jsonEncode(preset().toJson()));
    final roundTrip = DesignPreset.fromJson(
      (encoded as Map).cast<String, Object?>(),
    );
    expect(roundTrip.frameAspect(DesignOrientation.landscape), 2.6);
    expect(
      roundTrip.frameAspect(DesignOrientation.portrait),
      closeTo(1 / 2.6, 0.000001),
    );
    expect(
      roundTrip.frameAspect(DesignOrientation.landscape, viewportAspect: 1.5),
      2.6,
    );
    expect(
      roundTrip.frameSpec(DesignOrientation.landscape).mode,
      FrameAspectMode.fixed,
    );
  });

  test('adaptive frame resolves current viewport and preserves reference', () {
    final source = DesignPreset(
      id: 'adaptive',
      name: 'Adaptive',
      version: 1,
      supportedOrientations: const <DesignOrientation>{
        DesignOrientation.landscape,
      },
      frameSpecs: const <DesignOrientation, FrameSpec>{
        DesignOrientation.landscape: FrameSpec(
          referenceAspect: 2.6,
          mode: FrameAspectMode.adaptive,
        ),
      },
      components: <ComponentInstance>[digits()],
    );
    final back = DesignPreset.fromJson(
      (jsonDecode(jsonEncode(source.toJson())) as Map).cast<String, Object?>(),
    );

    expect(
      back.frameAspect(DesignOrientation.landscape, viewportAspect: 4 / 3),
      closeTo(4 / 3, 1e-9),
    );
    expect(back.frameSpec(DesignOrientation.landscape).referenceAspect, 2.6);
  });

  test('legacy frame aspects decode as fixed frame specs', () {
    final legacy = preset().toJson()
      ..remove('frameSpecs')
      ..['frameAspects'] = <String, Object?>{'landscape': 2.4, 'portrait': 0.6};
    final decoded = DesignPreset.fromJson(legacy);
    expect(decoded.frameAspect(DesignOrientation.landscape), 2.4);
    expect(decoded.frameAspect(DesignOrientation.portrait), 0.6);
    expect(
      decoded.frameSpec(DesignOrientation.landscape).mode,
      FrameAspectMode.fixed,
    );
  });
}
