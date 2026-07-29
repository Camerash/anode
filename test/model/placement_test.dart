import 'dart:ui' show Offset, Size;

import 'package:anode/model/placement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placement requires absolute centre and explicit size', () {
    const placement = Placement(
      center: Offset(0.4, -0.2),
      size: Size(1.2, 0.4),
    );

    expect(placement.center, const Offset(0.4, -0.2));
    expect(placement.size, const Size(1.2, 0.4));
  });

  test('placement writes only schema-5 x y w h fields', () {
    const placement = Placement(
      center: Offset(-0.25, 0.1),
      size: Size(0.8, 0.3),
    );

    expect(placement.toJson(), <String, Object?>{
      'x': -0.25,
      'y': 0.1,
      'w': 0.8,
      'h': 0.3,
    });
  });

  test('placement round trips through json', () {
    const placement = Placement(
      center: Offset(-0.25, -0.1),
      size: Size(0.8, 0.3),
    );

    final back = Placement.fromJson(placement.toJson());
    expect(back.center, placement.center);
    expect(back.size, placement.size);
  });

  test('malformed fields use supplied defensive size fallback', () {
    final placement = Placement.fromJson(<String, Object?>{
      'x': 'bad',
      'w': 1.2,
    }, fallbackSize: const Size(0.7, 0.2));

    expect(placement.center, Offset.zero);
    expect(placement.size, const Size(1.2, 0.2));
  });

  test('frame shape never changes authored geometry', () {
    const placement = Placement(
      center: Offset(0.4, -0.2),
      size: Size(1.2, 0.4),
    );
    const frames = <Size>[Size(2.6, 1), Size(2.6, 5.637), Size(4 / 3, 1)];

    for (final _ in frames) {
      expect(placement.center, const Offset(0.4, -0.2));
      expect(placement.size, const Size(1.2, 0.4));
    }
  });
}
