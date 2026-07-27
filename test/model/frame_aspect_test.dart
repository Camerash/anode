import 'dart:convert';

import 'package:anode/model/component_instance.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/design_preset.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
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

  test('frame aspects survive json and legacy payloads get safe defaults', () {
    final encoded = jsonDecode(jsonEncode(preset().toJson()));
    final roundTrip = DesignPreset.fromJson(
      (encoded as Map).cast<String, Object?>(),
    );
    expect(roundTrip.frameAspect(DesignOrientation.landscape), 2.6);
    expect(
      roundTrip.frameAspect(DesignOrientation.portrait),
      closeTo(1 / 2.6, 0.000001),
    );

    final legacy = preset().toJson()..remove('frameAspects');
    final decoded = DesignPreset.fromJson(legacy);
    expect(decoded.frameAspect(DesignOrientation.landscape), 2.6);
    expect(
      decoded.frameAspect(DesignOrientation.portrait),
      closeTo(1 / 2.6, 0.000001),
    );
  });
}
