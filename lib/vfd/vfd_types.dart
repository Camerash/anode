import 'package:flutter/foundation.dart';

enum SpeedUnit {
  kph('KM/H', 1.0),
  mph('MPH', 0.621371);

  const SpeedUnit(this.label, this.fromKph);

  final String label;
  final double fromKph;

  double convert(double kph) => kph * fromKph;
}

@immutable
class Phosphor {
  const Phosphor(this.r, this.g, this.b, this.name);

  final double r;
  final double g;
  final double b;
  final String name;

  static const cyanGreen = Phosphor(0.30, 1.00, 0.72, 'Cyan-green');
  static const amber = Phosphor(1.00, 0.60, 0.11, 'Amber');
  static const red = Phosphor(1.00, 0.21, 0.12, 'Red');

  static const List<Phosphor> all = <Phosphor>[cyanGreen, amber, red];

  static Phosphor byName(String name) {
    for (final p in all) {
      if (p.name == name) return p;
    }
    return cyanGreen;
  }
}
