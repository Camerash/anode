import 'package:flutter/foundation.dart';

@immutable
class VfdLayers {
  const VfdLayers({
    this.bloom = true,
    this.unlitSegments = true,
    this.gridMesh = true,
    this.filamentWires = true,
    this.grain = true,
    this.phosphorDecay = true,
    this.tiltParallax = true,
  });

  final bool bloom;
  final bool unlitSegments;
  final bool gridMesh;
  final bool filamentWires;
  final bool grain;
  final bool phosphorDecay;
  final bool tiltParallax;

  static const List<String> keys = <String>[
    'bloom',
    'unlitSegments',
    'gridMesh',
    'filamentWires',
    'grain',
    'phosphorDecay',
    'tiltParallax',
  ];

  static const Map<String, String> labels = <String, String>{
    'bloom': 'Bloom halo',
    'unlitSegments': 'Unlit segments',
    'gridMesh': 'Grid mesh',
    'filamentWires': 'Filament wires',
    'grain': 'Grain',
    'phosphorDecay': 'Phosphor decay',
    'tiltParallax': 'Tilt parallax',
  };

  bool operator [](String key) => toJson()[key] ?? true;

  VfdLayers withKey(String key, bool value) {
    final j = toJson()..[key] = value;
    return VfdLayers.fromJson(j);
  }

  Map<String, bool> toJson() => <String, bool>{
        'bloom': bloom,
        'unlitSegments': unlitSegments,
        'gridMesh': gridMesh,
        'filamentWires': filamentWires,
        'grain': grain,
        'phosphorDecay': phosphorDecay,
        'tiltParallax': tiltParallax,
      };

  factory VfdLayers.fromJson(Map<String, dynamic> j) => VfdLayers(
        bloom: j['bloom'] as bool? ?? true,
        unlitSegments: j['unlitSegments'] as bool? ?? true,
        gridMesh: j['gridMesh'] as bool? ?? true,
        filamentWires: j['filamentWires'] as bool? ?? true,
        grain: j['grain'] as bool? ?? true,
        phosphorDecay: j['phosphorDecay'] as bool? ?? true,
        tiltParallax: j['tiltParallax'] as bool? ?? true,
      );
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
}
