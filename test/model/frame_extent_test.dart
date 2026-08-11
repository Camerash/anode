import 'dart:ui' show Size;

import 'package:anode/model/design_layout.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('containingFrameForAspect', () {
    test('grows height for a taller target', () {
      const source = FrameSpec(width: 2.6, height: 1);
      final target = containingFrameForAspect(source, 0.5);

      expect(target.extent, const Size(2.6, 5.2));
    });

    test('grows width for a wider target', () {
      const source = FrameSpec(width: 1, height: 2);
      final target = containingFrameForAspect(source, 2);

      expect(target.extent, const Size(4, 2));
    });

    test('does not change source design-unit scale', () {
      const source = FrameSpec(width: 2.6, height: 1);
      final target = containingFrameForAspect(source, 0.5);

      expect(target.width, source.width);
    });
  });

  group('FrameSpec serialization', () {
    test('round trips an extent whose height is not one unit', () {
      const spec = FrameSpec(width: 2.6, height: 5.637);
      final back = FrameSpec.fromJson(
        spec.toJson(),
        fallback: const FrameSpec.aspect(2.6),
      );
      expect(back.width, closeTo(2.6, 1e-12));
      expect(back.height, closeTo(5.637, 1e-12));
    });

    test('an obsolete aspect-only payload uses the explicit fallback', () {
      final back = FrameSpec.fromJson(<String, Object?>{
        'referenceAspect': 2.4,
      }, fallback: const FrameSpec.aspect(2.6));
      expect(back.extent, const Size(2.6, 1));
    });

    test('a degenerate extent falls back', () {
      final back = FrameSpec.fromJson(<String, Object?>{
        'width': 0,
        'height': 4,
      }, fallback: const FrameSpec.aspect(2.6));
      expect(back.extent, const Size(2.6, 1));
    });
  });
}
