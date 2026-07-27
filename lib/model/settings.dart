import 'package:flutter/foundation.dart';

import '../vfd/vfd_layers.dart';

/// Per-dashboard settings. Orientation support lives on the design itself, not
/// here, because it is a property of the authored layouts.
@immutable
class DashboardSettings {
  const DashboardSettings({
    this.brightness = 1.0,
    this.phosphorName = 'Cyan-green',
  });

  final double brightness;
  final String phosphorName;

  Phosphor get phosphor => Phosphor.byName(phosphorName);

  DashboardSettings copyWith({double? brightness, String? phosphorName}) =>
      DashboardSettings(
        brightness: brightness ?? this.brightness,
        phosphorName: phosphorName ?? this.phosphorName,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'brightness': brightness,
        'phosphorName': phosphorName,
      };

  factory DashboardSettings.fromJson(Map<String, Object?> json) =>
      DashboardSettings(
        brightness: (json['brightness'] as num?)?.toDouble() ?? 1.0,
        phosphorName: json['phosphorName'] as String? ?? 'Cyan-green',
      );
}

/// App-wide settings. The authenticity layer toggles are GLOBAL and never enter
/// a dashboard: they govern render fidelity and performance, not a design's
/// identity.
@immutable
class GlobalSettings {
  const GlobalSettings({
    this.layers = const VfdLayers(),
    this.demoMode = false,
  });

  final VfdLayers layers;
  final bool demoMode;

  GlobalSettings copyWith({VfdLayers? layers, bool? demoMode}) =>
      GlobalSettings(
        layers: layers ?? this.layers,
        demoMode: demoMode ?? this.demoMode,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'layers': layers.toJson(),
        'demoMode': demoMode,
      };

  factory GlobalSettings.fromJson(Map<String, Object?> json) => GlobalSettings(
        layers: VfdLayers.fromJson(
            (json['layers'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{}),
        demoMode: json['demoMode'] as bool? ?? false,
      );
}
