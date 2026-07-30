import 'dart:typed_data';

import 'package:anode/vfd/component_data.dart';
import 'package:anode/vfd/prism_glyphs.dart';
import 'package:flutter_test/flutter_test.dart';

/// Values chosen to be unrepresentable in 8 bits, so a silent downconversion of
/// the texture format shows up as a mismatch rather than passing by luck.
/// Narrowed to float32 first, since that is what the buffer stores.
final List<double> awkward = Float32List.fromList(<double>[
  1 / 3,
  -1.3,
  0.084,
  0.6815,
]).toList();

double packedGeometry(
  Float32List floats,
  int base,
  int value, {
  bool prism = false,
}) {
  final lowOffsets = prism
      ? ComponentData.prismGeometryLowByteOffsets
      : ComponentData.nonPrismGeometryLowByteOffsets;
  return ComponentData.decodePackedScalar(
    floats[base + ComponentData.geometryHighByteOffsets[value]],
    floats[base + lowOffsets[value]],
  );
}

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
        variantCode: 7,
        phosphorR: 0.2,
        phosphorG: 0.7,
        phosphorB: 0.4,
        bloom: 1.5,
        moduleCenterX: -0.4,
        moduleWidth: 0.9,
        prismPressed: 1,
        filamentVariantCode: 2,
        prismBevelDepth: 0.16,
        prismFaceOpacity: 0.8,
        prismInactiveLuminosity: 0.25,
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
    expect(
      floats[0],
      closeTo(
        ComponentData.encodeTypeAndPositionSigns(
          ShaderType.digits,
          awkward[3],
          0.11,
        ),
        1e-7,
      ),
    );
    expect(
      packedGeometry(floats, 0, 0),
      closeTo(ComponentData.encodePositionMagnitude(awkward[3]), 1 / 65535),
    );
    expect(floats[6], closeTo(ComponentData.encodeCount(3), 1e-7));
    expect(floats[9], closeTo(ComponentData.encodeCount(7), 1e-7));
    expect(floats[12], closeTo(0.2, 1e-7));
    expect(floats[13], closeTo(0.7, 1e-7));
    expect(floats[14], closeTo(0.4, 1e-7));
    expect(floats[17], closeTo(ComponentData.encodeEffect(1.5), 1e-7));
    expect(
      packedGeometry(floats, 0, 4),
      closeTo(ComponentData.encodePositionMagnitude(-0.4), 1 / 65535),
    );
    expect(
      packedGeometry(floats, 0, 6),
      closeTo(ComponentData.encodeSize(0.9), 1 / 65535),
    );
    expect(floats[32], 1);
    expect(floats[33], closeTo(ComponentData.encodeCount(2), 1e-7));
    expect(floats[36], closeTo(0.16, 1e-7));
    expect(floats[37], closeTo(0.8, 1e-7));
    expect(floats[38], closeTo(0.25, 1e-7));

    // First digit starts after the header texels; segments run three per texel.
    const digit0 = ComponentData.headerTexels * 4;
    expect(floats[digit0 + 0], 0 / 32); // segment 0
    expect(floats[digit0 + 2], 2 / 32); // segment 2
    expect(floats[digit0 + 4], 3 / 32); // segment 3, next texel
    expect(floats[digit0 + 8], 6 / 32); // segment 6, third texel

    // The second digit reads from the segment buffer's stride of eight.
    const digit1 =
        (ComponentData.headerTexels + ComponentData.texelsPerDigit) * 4;
    expect(floats[digit1 + 0], 8 / 32);

    const second = ComponentData.floatsPerComponent;
    expect(
      floats[second + 0],
      closeTo(
        ComponentData.encodeTypeAndPositionSigns(ShaderType.bar, 0, -0.33),
        1e-7,
      ),
    );
    expect(
      packedGeometry(floats, second, 3),
      closeTo(ComponentData.encodeSize(awkward[2]), 1 / 65535),
    );
    expect(floats[second + 8], 0.5); // a fraction, stored raw
  });

  test('nothing stored falls outside the clamped range', () {
    // The sampled texture is normalised, so anything outside [0, 1] comes back
    // pinned to the boundary.
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

  test('Prism rows reuse segment payload for glyph indices', () {
    final glyphs = PrismGlyphs.encode('RESET 50%');
    final floats = ComponentData.pack(<ComponentFrame>[
      ComponentFrame(
        type: ShaderType.prism,
        centerX: -0.005,
        centerY: 0.0173,
        width: 0.7,
        height: 0.24,
        paramA: 63,
        prismGlyphs: glyphs,
      ),
    ]);

    expect(
      floats[6],
      closeTo(ComponentData.encodeCount(glyphs.length.toDouble()), 1e-7),
    );
    final payload = ComponentData.headerTexels * 4;
    for (var i = 0; i < glyphs.length; i++) {
      final offset = payload + (i ~/ 3) * 4 + i % 3;
      expect(floats[offset], closeTo(glyphs[i], 1e-7));
    }
    expect(floats[payload + (glyphs.length ~/ 3) * 4 + 2], 0);
    expect(
      packedGeometry(floats, 0, 0, prism: true) * ComponentData.positionRange,
      closeTo(0.005, ComponentData.positionRange / 65535),
    );
    expect(
      packedGeometry(floats, 0, 1, prism: true) * ComponentData.positionRange,
      closeTo(0.0173, ComponentData.positionRange / 65535),
    );
  });

  test('Prism payload length clamps to atlas capacity', () {
    final floats = ComponentData.pack(<ComponentFrame>[
      ComponentFrame(
        type: ShaderType.prism,
        centerX: 0,
        centerY: 0,
        width: 0.7,
        height: 0.24,
        prismGlyphs: List<double>.filled(40, 0.5),
      ),
    ]);

    expect(
      floats[6],
      closeTo(
        ComponentData.encodeCount(PrismGlyphs.maxVisibleGlyphs.toDouble()),
        1e-7,
      ),
    );
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

  test(
    'unused component rows are zeroed so the shader reads nothing stale',
    () {
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
    },
  );

  test(
    'more components than the texture holds are dropped, not overflowed',
    () {
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
      expect(
        floats.length,
        ComponentData.maxComponents * ComponentData.floatsPerComponent,
      );

      const lastIndex = ComponentData.maxComponents - 1;
      const last = lastIndex * ComponentData.floatsPerComponent;
      expect(
        packedGeometry(floats, last, 0),
        closeTo(
          ComponentData.encodePositionMagnitude(lastIndex / 100),
          1 / 65535,
        ),
      );
    },
  );

  test('a position beyond the representable range clamps to the edge', () {
    expect(ComponentData.encodePositionMagnitude(5000), 1.0);
    expect(ComponentData.encodePositionMagnitude(-5000), 1.0);
    expect(ComponentData.encodeSize(5000), 1.0);
  });

  test('position signs round-trip independently from magnitudes', () {
    final floats = ComponentData.pack(<ComponentFrame>[
      ComponentFrame(
        type: ShaderType.legend,
        centerX: -0.005,
        centerY: 0.0173,
        width: 1,
        height: 1,
        moduleCenterX: 0.125,
        moduleCenterY: -0.25,
        isMainModule: false,
      ),
    ]);

    final typeAndSigns = (floats[0] * ComponentData.typeAndPositionSignScale)
        .round();
    expect(typeAndSigns ~/ 4, ShaderType.legend);
    expect(typeAndSigns % 4, 1);
    expect(
      packedGeometry(floats, 0, 0) * ComponentData.positionRange,
      closeTo(0.005, ComponentData.positionRange / 65535),
    );
    expect(
      packedGeometry(floats, 0, 1) * ComponentData.positionRange,
      closeTo(0.0173, ComponentData.positionRange / 65535),
    );

    final moduleFlags = (floats[34] * ComponentData.moduleFlagScale).round();
    expect(moduleFlags, 4);
    expect(
      packedGeometry(floats, 0, 4) * ComponentData.positionRange,
      closeTo(0.125, ComponentData.positionRange / 65535),
    );
    expect(
      packedGeometry(floats, 0, 5) * ComponentData.positionRange,
      closeTo(0.25, ComponentData.positionRange / 65535),
    );
  });

  test('the range covers an envelope derived from a narrow tall window', () {
    // A landscape primary contained into 320x1024 derives an 8.32-unit-tall
    // envelope. The previous sizeScale of 8 clamped it silently.
    expect(ComponentData.encodeSize(8.32), lessThan(1.0));
    expect(
      ComponentData.encodeSize(8.32) * ComponentData.sizeScale,
      closeTo(8.32, 1e-6),
    );
  });

  test('the main module is flagged, not inferred from its geometry', () {
    // Main-module size equals the frame extent, so a sub-module a user happens
    // to size to the whole frame must not be mistaken for the tube itself.
    final floats = ComponentData.pack(<ComponentFrame>[
      ComponentFrame(
        type: ShaderType.digits,
        centerX: 0,
        centerY: 0,
        width: 1,
        height: 0.5,
        moduleWidth: 2.6,
        moduleHeight: 1,
      ),
      ComponentFrame(
        type: ShaderType.digits,
        centerX: 0,
        centerY: 0,
        width: 1,
        height: 0.5,
        moduleWidth: 2.6,
        moduleHeight: 1,
        isMainModule: false,
      ),
    ]);

    expect(floats[34], 1 / ComponentData.moduleFlagScale);
    expect(floats[ComponentData.floatsPerComponent + 34], 0.0);
  });
}
