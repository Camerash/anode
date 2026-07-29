import 'dart:ui' show Offset, Size;

import 'package:anode/model/component_type.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Representative authored frame extents. Height is no longer pinned to one
  // unit: an alternate baked from a landscape primary is several units tall.
  const frames = <String, Size>{
    'authored 2.6:1': Size(2.6, 1),
    'phone landscape 18:9': Size(2.0, 1),
    'phone landscape 16:9': Size(16 / 9, 1),
    'iPad 4:3': Size(4 / 3, 1),
    'baked portrait alternate': Size(2.6, 5.637),
  };

  group('anchor points', () {
    test('centre is the origin at every extent', () {
      for (final frame in frames.values) {
        expect(Anchor.center.pointIn(frame), Offset.zero);
      }
    });

    test('y is up: top is positive, bottom negative, half the frame', () {
      for (final frame in frames.values) {
        expect(Anchor.topCenter.pointIn(frame).dy, frame.height / 2);
        expect(Anchor.bottomCenter.pointIn(frame).dy, -frame.height / 2);
      }
    });

    test('edges track both frame axes', () {
      expect(Anchor.centerRight.pointIn(const Size(2.6, 1)).dx, closeTo(1.3, 1e-9));
      expect(Anchor.centerLeft.pointIn(const Size(2.6, 1)).dx, closeTo(-1.3, 1e-9));
      expect(
        Anchor.centerRight.pointIn(const Size(4 / 3, 1)).dx,
        closeTo(2 / 3, 1e-9),
      );
      // A frame taller than one unit moves the vertical anchors with it.
      expect(
        Anchor.bottomCenter.pointIn(const Size(2.6, 5.637)).dy,
        closeTo(-2.8185, 1e-9),
      );
    });
  });

  group('resolution', () {
    test('a right-anchored component stays welded to the right edge', () {
      const p = Placement(anchor: Anchor.centerRight, offset: Offset(-0.2, 0));
      for (final entry in frames.entries) {
        final frame = entry.value;
        final distanceFromRightEdge = frame.width / 2 - p.resolve(frame).dx;
        expect(
          distanceFromRightEdge,
          closeTo(0.2, 1e-9),
          reason: 'drifted at ${entry.key}',
        );
      }
    });

    test('a centre-anchored component does not move with the frame', () {
      const p = Placement(offset: Offset(0.1, 0.11));
      final positions = frames.values.map(p.resolve).toSet();
      expect(positions, hasLength(1));
    });

    test('offsets are added to the anchor, not multiplied by it', () {
      const p = Placement(anchor: Anchor.bottomLeft, offset: Offset(0.3, 0.05));
      expect(
        p.resolve(const Size(2.6, 1)),
        const Offset(-1.3 + 0.3, -0.5 + 0.05),
      );
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

  group('span axis sizing', () {
    test('horizontal span tracks frame width while preserving insets', () {
      const placement = Placement(
        size: Size(0.4, 0.2),
        horizontalSpan: AxisSpan(startInset: 0.2, endInset: 0.3),
      );

      expect(
        placement.resolveSizeIn(const Size(2.6, 1), null),
        const Size(2.1, 0.2),
      );
      expect(
        placement.resolveSizeIn(const Size(1.6, 1), null),
        const Size(1.1, 0.2),
      );
      expect(placement.resolve(const Size(2.6, 1)).dx, closeTo(-0.05, 1e-9));
    });

    test('vertical span tracks frame height while preserving insets', () {
      const placement = Placement(
        size: Size(0.4, 0.2),
        verticalSpan: AxisSpan(startInset: 0.1, endInset: 0.25),
      );

      expect(
        placement.resolveSizeIn(const Size(2.6, 1), null),
        const Size(0.4, 0.65),
      );
      expect(placement.resolve(const Size(2.6, 1)).dy, closeTo(0.075, 1e-9));

      // Frame height is no longer implicitly 1, so the span has to follow it.
      expect(
        placement.resolveSizeIn(const Size(2.6, 4), null),
        const Size(0.4, 3.65),
      );
    });

    test('span axes survive json independently', () {
      const placement = Placement(
        horizontalSpan: AxisSpan(startInset: 0.2, endInset: 0.3),
      );
      final back = Placement.fromJson(placement.toJson());

      expect(back.horizontalSpan?.startInset, 0.2);
      expect(back.horizontalSpan?.endInset, 0.3);
      expect(back.verticalSpan, isNull);
    });
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
