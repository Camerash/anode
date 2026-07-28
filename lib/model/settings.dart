import 'package:flutter/foundation.dart';

import 'optical_profile.dart';

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
  });

  final bool soundEnabled;
  final bool hapticsEnabled;
  final bool demoMode;

  GlobalSettings copyWith({
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? demoMode,
  }) => GlobalSettings(
    soundEnabled: soundEnabled ?? this.soundEnabled,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    demoMode: demoMode ?? this.demoMode,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'soundEnabled': soundEnabled,
    'hapticsEnabled': hapticsEnabled,
    'demoMode': demoMode,
  };

  factory GlobalSettings.fromJson(Map<String, Object?> json) => GlobalSettings(
    soundEnabled: json['soundEnabled'] as bool? ?? true,
    hapticsEnabled: json['hapticsEnabled'] as bool? ?? true,
    demoMode: json['demoMode'] as bool? ?? false,
  );
}
