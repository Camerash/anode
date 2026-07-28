import 'dart:ui' show Offset, Size;

import 'package:anode/model/component_type.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The aspect spread a single authored orientation has to absorb.
  const aspects = <String, double>{
    'authored 2.6:1': 2.6,
    'phone landscape 18:9': 2.0,
    'phone landscape 16:9': 16 / 9,
    'iPad 4:3': 4 / 3,
  };

  group('anchor points', () {
    test('centre is the origin at every aspect', () {
      for (final a in aspects.values) {
        expect(Anchor.center.pointIn(a), Offset.zero);
      }
    });

    test('y is up: top is positive, bottom negative, always half a unit', () {
      for (final a in aspects.values) {
        expect(Anchor.topCenter.pointIn(a).dy, 0.5);
        expect(Anchor.bottomCenter.pointIn(a).dy, -0.5);
      }
    });

    test('x edges track the aspect', () {
      expect(Anchor.centerRight.pointIn(2.6).dx, closeTo(1.3, 1e-9));
      expect(Anchor.centerLeft.pointIn(2.6).dx, closeTo(-1.3, 1e-9));
      expect(Anchor.centerRight.pointIn(4 / 3).dx, closeTo(2 / 3, 1e-9));
    });
  });

  group('resolution', () {
    test('a right-anchored component stays welded to the right edge', () {
      const p = Placement(anchor: Anchor.centerRight, offset: Offset(-0.2, 0));
      for (final entry in aspects.entries) {
        final aspect = entry.value;
        final distanceFromRightEdge = aspect / 2 - p.resolve(aspect).dx;
        expect(
          distanceFromRightEdge,
          closeTo(0.2, 1e-9),
          reason: 'drifted at ${entry.key}',
        );
      }
    });

    test('a centre-anchored component does not move with aspect', () {
      const p = Placement(offset: Offset(0.1, 0.11));
      final positions = aspects.values.map((a) => p.resolve(a)).toSet();
      expect(positions, hasLength(1));
    });

    test('offsets are added to the anchor, not multiplied by it', () {
      const p = Placement(anchor: Anchor.bottomLeft, offset: Offset(0.3, 0.05));
      expect(p.resolve(2.6), const Offset(-1.3 + 0.3, -0.5 + 0.05));
    });
  });

  group('independent sizing', () {
    test('falls back to the type default when unset', () {
      const p = Placement();
      final type = ComponentTypes.byId(ComponentTypes.speedDigits);
      expect(p.resolveSize(type), type!.defaultSize);
    });

    test('width and height move independently', () {
      const p = Placement(size: Size(2.4, 0.3));
      final type = ComponentTypes.byId(ComponentTypes.speedDigits);
      expect(p.resolveSize(type), const Size(2.4, 0.3));
    });

    test('an unknown type still yields a usable size', () {
      const p = Placement();
      expect(p.resolveSize(null), const Size(1, 1));
    });

    test('size survives a json round trip and stays absent when unset', () {
      const sized = Placement(size: Size(1.2, 0.4));
      expect(Placement.fromJson(sized.toJson()).size, const Size(1.2, 0.4));

      const unsized = Placement();
      expect(unsized.toJson().containsKey('w'), isFalse);
      expect(Placement.fromJson(unsized.toJson()).size, isNull);
    });

    test(
      'a half-written size degrades to the default rather than a zero box',
      () {
        final p = Placement.fromJson(<String, Object?>{'w': 1.2});
        expect(p.size, isNull);
      },
    );
  });

  test('placement round trips through json', () {
    const p = Placement(
      anchor: Anchor.topRight,
      offset: Offset(-0.25, -0.1),
      size: Size(0.8, 0.3),
    );
    final back = Placement.fromJson(p.toJson());
    expect(back.anchor, p.anchor);
    expect(back.offset, p.offset);
    expect(back.size, p.size);
  });

  test('an unknown anchor name degrades to centre rather than throwing', () {
    final back = Placement.fromJson(<String, Object?>{
      'anchor': 'someFutureAnchor',
    });
    expect(back.anchor, Anchor.center);
  });
}
