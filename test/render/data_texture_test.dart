import 'dart:typed_data';

import 'package:anode/vfd/component_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Values chosen to be unrepresentable in 8 bits, so a silent downconversion of
/// the texture format shows up as a mismatch rather than passing by luck.
/// Narrowed to float32 first, since that is what the buffer stores.
final List<double> awkward =
    Float32List.fromList(<double>[1 / 3, -1.3, 0.084, 0.6815]).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pack writes the documented texel layout', () {
    final floats = ComponentData.pack(<ComponentFrame>[
      ComponentFrame(
        type: ShaderType.digits,
        centerX: awkward[3],
        centerY: 0.11,
        width: 1.035,
        height: 0.588,
        paramA: 3,
        segments: List<double>.generate(32, (i) => i / 32),
      ),
      ComponentFrame(
        type: ShaderType.bar,
        centerX: 0,
        centerY: -0.33,
        width: 1.96,
        height: awkward[2],
        paramA: 20,
        paramB: 0.5,
      ),
    ]);

    // Compared loosely: the buffer narrows to float32, the expectations do not.
    expect(floats[0], closeTo(ComponentData.encodeType(ShaderType.digits), 1e-7));
    expect(floats[1], closeTo(ComponentData.encodePosition(awkward[3]), 1e-7));
    expect(floats[6], closeTo(ComponentData.encodeCount(3), 1e-7));

    // First digit starts after the header texels; segments run three per texel.
    const digit0 = ComponentData.headerTexels * 4;
    expect(floats[digit0 + 0], 0 / 32); // segment 0
    expect(floats[digit0 + 2], 2 / 32); // segment 2
    expect(floats[digit0 + 4], 3 / 32); // segment 3, next texel
    expect(floats[digit0 + 8], 6 / 32); // segment 6, third texel

    // The second digit reads from the segment buffer's stride of eight.
    const digit1 = (ComponentData.headerTexels + ComponentData.texelsPerDigit) * 4;
    expect(floats[digit1 + 0], 8 / 32);

    const second = ComponentData.floatsPerComponent;
    expect(floats[second + 0], closeTo(ComponentData.encodeType(ShaderType.bar), 1e-7));
    expect(floats[second + 5], closeTo(ComponentData.encodeSize(awkward[2]), 1e-7));
    expect(floats[second + 8], 0.5); // a fraction, stored raw
  });

  test('nothing stored falls outside the clamped range', () {
    // The texture keeps float precision but is range-clamped, so anything
    // outside [0, 1] comes back pinned to the boundary.
    final floats = ComponentData.pack(<ComponentFrame>[
      ComponentFrame(
        type: ShaderType.legend,
        centerX: -1.3,
        centerY: 0.5,
        width: 1.96,
        height: 0.084,
        paramA: 40,
        paramB: 1.0,
        segments: List<double>.filled(32, 1.0),
      ),
    ]);

    for (var i = 0; i < ComponentData.floatsPerComponent; i++) {
      expect(floats[i], inInclusiveRange(0.0, 1.0), reason: 'float $i');
    }
  });

  test('alpha is 1 everywhere, including unused rows', () {
    final floats = ComponentData.pack(<ComponentFrame>[
      ComponentFrame(
        type: ShaderType.bar,
        centerX: 0,
        centerY: 0,
        width: 1,
        height: 1,
      ),
    ]);

    // Payload values stored in alpha come back scaled by premultiplication,
    // which silently zeroed every component the first time this was written.
    for (var i = 3; i < floats.length; i += 4) {
      expect(floats[i], 1.0, reason: 'alpha at float $i');
    }
  });

  test('unused component rows are zeroed so the shader reads nothing stale', () {
    final floats = ComponentData.pack(<ComponentFrame>[
      ComponentFrame(
        type: ShaderType.bar,
        centerX: 0,
        centerY: 0,
        width: 1,
        height: 1,
      ),
    ]);

    final rest = floats.sublist(ComponentData.floatsPerComponent);
    for (var i = 0; i < rest.length; i++) {
      expect(rest[i], i % 4 == 3 ? 1.0 : 0.0);
    }
  });

  test('more components than the texture holds are dropped, not overflowed', () {
    final many = List<ComponentFrame>.generate(
      ComponentData.maxComponents + 4,
      (i) => ComponentFrame(
        type: ShaderType.bar,
        centerX: i / 100,
        centerY: 0,
        width: 1,
        height: 1,
      ),
    );

    final floats = ComponentData.pack(many);
    expect(floats.length,
        ComponentData.maxComponents * ComponentData.floatsPerComponent);

    const lastIndex = ComponentData.maxComponents - 1;
    const last = lastIndex * ComponentData.floatsPerComponent;
    expect(floats[last + 1],
        closeTo(ComponentData.encodePosition(lastIndex / 100), 1e-7));
  });

  test('a position beyond the representable range clamps to the edge', () {
    expect(ComponentData.encodePosition(500), 1.0);
    expect(ComponentData.encodePosition(-500), 0.0);
    expect(ComponentData.encodeSize(500), 1.0);
  });
}
