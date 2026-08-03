import 'package:flutter/foundation.dart';

import 'optical_profile.dart';

enum EditorDockEdge { left, right, bottom }

@immutable
class EditorDockPlacement {
  const EditorDockPlacement({required this.edge, required this.alignment})
    : assert(alignment >= 0 && alignment <= 1);

  const EditorDockPlacement.portraitDefault()
    : edge = EditorDockEdge.left,
      alignment = 0.5;

  const EditorDockPlacement.landscapeDefault()
    : edge = EditorDockEdge.bottom,
      alignment = 0.5;

  final EditorDockEdge edge;
  final double alignment;

  EditorDockPlacement copyWith({EditorDockEdge? edge, double? alignment}) =>
      EditorDockPlacement(
        edge: edge ?? this.edge,
        alignment: (alignment ?? this.alignment).clamp(0.0, 1.0),
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'edge': edge.name,
    'alignment': alignment,
  };

  factory EditorDockPlacement.fromJson(
    Object? raw, {
    required EditorDockPlacement fallback,
  }) {
    if (raw == null) return fallback;
    if (raw is! Map) throw const FormatException('Invalid editor dock');
    final json = raw.cast<Object?, Object?>();
    final edge = EditorDockEdge.values.byName(json['edge'] as String);
    final alignment = (json['alignment'] as num).toDouble();
    return EditorDockPlacement(
      edge: edge,
      alignment: alignment.clamp(0.0, 1.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EditorDockPlacement &&
      other.edge == edge &&
      other.alignment == alignment;

  @override
  int get hashCode => Object.hash(edge, alignment);
}

@immutable
class EditorDockPreferences {
  const EditorDockPreferences({
    this.portrait = const EditorDockPlacement.portraitDefault(),
    this.landscape = const EditorDockPlacement.landscapeDefault(),
  });

  final EditorDockPlacement portrait;
  final EditorDockPlacement landscape;

  EditorDockPreferences copyWith({
    EditorDockPlacement? portrait,
    EditorDockPlacement? landscape,
  }) => EditorDockPreferences(
    portrait: portrait ?? this.portrait,
    landscape: landscape ?? this.landscape,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'portrait': portrait.toJson(),
    'landscape': landscape.toJson(),
  };

  factory EditorDockPreferences.fromJson(Object? raw) {
    if (raw == null) return const EditorDockPreferences();
    if (raw is! Map) throw const FormatException('Invalid editor dock');
    final json = raw.cast<Object?, Object?>();
    return EditorDockPreferences(
      portrait: EditorDockPlacement.fromJson(
        json['portrait'],
        fallback: const EditorDockPlacement.portraitDefault(),
      ),
      landscape: EditorDockPlacement.fromJson(
        json['landscape'],
        fallback: const EditorDockPlacement.landscapeDefault(),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EditorDockPreferences &&
      other.portrait == portrait &&
      other.landscape == landscape;

  @override
  int get hashCode => Object.hash(portrait, landscape);
}

/// Per-dashboard authored appearance.
@immutable
class DashboardSettings {
  DashboardSettings({
    this.brightness = 1,
    OpticalProfile? opticalProfile,
    this.prismStyle = const PrismStyle(),
  }) : opticalProfile = opticalProfile ?? OpticalProfile();

  final double brightness;
  final OpticalProfile opticalProfile;
  final PrismStyle prismStyle;

  String get phosphorName => opticalProfile.phosphorName;

  DashboardSettings copyWith({
    double? brightness,
    OpticalProfile? opticalProfile,
    PrismStyle? prismStyle,
    String? phosphorName,
  }) {
    final profile = opticalProfile ?? this.opticalProfile;
    return DashboardSettings(
      brightness: brightness ?? this.brightness,
      opticalProfile: phosphorName == null
          ? profile
          : profile.withPhosphor(phosphorName),
      prismStyle: prismStyle ?? this.prismStyle,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'brightness': brightness,
    'opticalProfile': opticalProfile.toJson(),
    'prismStyle': prismStyle.toJson(),
  };

  factory DashboardSettings.fromJson(Map<String, Object?> json) {
    final rawProfile = (json['opticalProfile'] as Map?)
        ?.cast<String, Object?>();
    // `phosphorName` is the Stage 2/3 shape. It maps to the fixed dashboard
    // baseline instead of whichever defaults a later build happens to choose.
    final profile = rawProfile == null
        ? OpticalProfile(
            phosphorName: json['phosphorName'] as String? ?? 'Cyan-green',
          )
        : OpticalProfile.fromJson(rawProfile);
    return DashboardSettings(
      brightness: (json['brightness'] as num?)?.toDouble() ?? 1,
      opticalProfile: profile,
      prismStyle: PrismStyle.fromJson(
        (json['prismStyle'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
    );
  }
}

/// App-wide user/device preferences. Authored optical values never live here.
@immutable
class GlobalSettings {
  const GlobalSettings({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.demoMode = false,
    this.editorDock = const EditorDockPreferences(),
  });

  final bool soundEnabled;
  final bool hapticsEnabled;
  final bool demoMode;
  final EditorDockPreferences editorDock;

  GlobalSettings copyWith({
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? demoMode,
    EditorDockPreferences? editorDock,
  }) => GlobalSettings(
    soundEnabled: soundEnabled ?? this.soundEnabled,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    demoMode: demoMode ?? this.demoMode,
    editorDock: editorDock ?? this.editorDock,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'soundEnabled': soundEnabled,
    'hapticsEnabled': hapticsEnabled,
    'demoMode': demoMode,
    'editorDock': editorDock.toJson(),
  };

  factory GlobalSettings.fromJson(Map<String, Object?> json) => GlobalSettings(
    soundEnabled: json['soundEnabled'] as bool? ?? true,
    hapticsEnabled: json['hapticsEnabled'] as bool? ?? true,
    demoMode: json['demoMode'] as bool? ?? false,
    editorDock: EditorDockPreferences.fromJson(json['editorDock']),
  );
}
