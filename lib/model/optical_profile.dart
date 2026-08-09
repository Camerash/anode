import 'package:flutter/foundation.dart';

import '../vfd/vfd_types.dart';

enum EffectScope { dashboard, module, component }

@immutable
class EffectSpec {
  const EffectSpec({
    required this.id,
    required this.label,
    String? controlLabel,
    String? pictogramId,
    required this.description,
    required this.scopes,
    this.defaultStrength = 1,
    this.maxStrength = 2,
    this.step = 0.01,
    this.precision = 2,
  }) : controlLabel = controlLabel ?? label,
       pictogramId = pictogramId ?? id;

  final String id;
  final String label;
  final String controlLabel;

  /// Presentation-only key for the hand-authored period line pictogram.
  final String pictogramId;
  final String description;
  final Set<EffectScope> scopes;
  final double defaultStrength;
  final double maxStrength;
  final double step;
  final int precision;

  bool supports(EffectScope scope) => scopes.contains(scope);

  double coerce(double value) => value.clamp(0, maxStrength);
}

abstract final class EffectIds {
  static const emission = 'emission';
  static const bloom = 'bloom';
  static const phosphorTexture = 'phosphorTexture';
  static const gridMesh = 'gridMesh';
  static const unlitPhosphor = 'unlitPhosphor';
  static const phosphorDecay = 'phosphorDecay';
  static const glassGrain = 'glassGrain';
  static const filamentWires = 'filamentWires';
  static const tiltParallax = 'tiltParallax';
}

abstract final class EffectSpecs {
  static const List<EffectSpec> all = <EffectSpec>[
    EffectSpec(
      id: EffectIds.emission,
      label: 'Emission',
      description: 'Set the light output of powered VFD segments.',
      scopes: <EffectScope>{
        EffectScope.dashboard,
        EffectScope.module,
        EffectScope.component,
      },
    ),
    EffectSpec(
      id: EffectIds.bloom,
      label: 'Bloom',
      description: 'Add a soft light halo around powered segments.',
      scopes: <EffectScope>{
        EffectScope.dashboard,
        EffectScope.module,
        EffectScope.component,
      },
    ),
    EffectSpec(
      id: EffectIds.phosphorTexture,
      label: 'Phosphor texture',
      controlLabel: 'Texture',
      description: 'Add small output differences across the phosphor layer.',
      scopes: <EffectScope>{
        EffectScope.dashboard,
        EffectScope.module,
        EffectScope.component,
      },
      defaultStrength: 0,
    ),
    EffectSpec(
      id: EffectIds.gridMesh,
      label: 'Grid',
      description: 'Show the control-grid mesh in the VFD light.',
      scopes: <EffectScope>{
        EffectScope.dashboard,
        EffectScope.module,
        EffectScope.component,
      },
    ),
    EffectSpec(
      id: EffectIds.unlitPhosphor,
      label: 'Unlit',
      controlLabel: 'Unlit',
      description: 'Show the phosphor layer in segments that have no power.',
      scopes: <EffectScope>{
        EffectScope.dashboard,
        EffectScope.module,
        EffectScope.component,
      },
    ),
    EffectSpec(
      id: EffectIds.phosphorDecay,
      label: 'Decay',
      description: 'Keep a short afterglow when a segment powers down.',
      scopes: <EffectScope>{
        EffectScope.dashboard,
        EffectScope.module,
        EffectScope.component,
      },
    ),
    EffectSpec(
      id: EffectIds.glassGrain,
      label: 'Glass grain',
      controlLabel: 'Grain',
      description: 'Add fine glass and sensor noise across the VFD module.',
      scopes: <EffectScope>{EffectScope.dashboard, EffectScope.module},
    ),
    EffectSpec(
      id: EffectIds.filamentWires,
      label: 'Filaments',
      controlLabel: 'Filament',
      description: 'Show the cathode wires across the VFD module.',
      scopes: <EffectScope>{EffectScope.dashboard, EffectScope.module},
    ),
    EffectSpec(
      id: EffectIds.tiltParallax,
      label: 'Parallax',
      description: 'Move the glass layer when the device tilts.',
      scopes: <EffectScope>{EffectScope.dashboard},
    ),
  ];

  static EffectSpec? byId(String id) {
    for (final spec in all) {
      if (spec.id == id) return spec;
    }
    return null;
  }

  static List<EffectSpec> forScope(EffectScope scope) => <EffectSpec>[
    for (final spec in all)
      if (spec.supports(scope)) spec,
  ];

  static EffectSpec storageSpec(String id) =>
      byId(id) ??
      EffectSpec(
        id: id,
        label: id,
        controlLabel: id,
        pictogramId: 'unknown',
        description: 'This effect is not available in this Anode version.',
        scopes: const <EffectScope>{
          EffectScope.dashboard,
          EffectScope.module,
          EffectScope.component,
        },
      );
}

@immutable
class EffectSetting {
  const EffectSetting({required this.strength, required this.resumeStrength});

  factory EffectSetting.at(double strength, EffectSpec spec) {
    final value = spec.coerce(strength);
    return EffectSetting(
      strength: value,
      resumeStrength: value > 0
          ? value
          : spec.defaultStrength.clamp(0.01, spec.maxStrength),
    );
  }

  final double strength;
  final double resumeStrength;

  bool get enabled => strength > 0;

  EffectSetting withStrength(double value, EffectSpec spec) {
    final next = spec.coerce(value);
    return EffectSetting(
      strength: next,
      resumeStrength: next > 0 ? next : resumeStrength,
    );
  }

  EffectSetting toggled(EffectSpec spec) => enabled
      ? EffectSetting(strength: 0, resumeStrength: strength)
      : withStrength(resumeStrength, spec);

  Map<String, Object?> toJson() => <String, Object?>{
    'strength': strength,
    'resumeStrength': resumeStrength,
  };

  factory EffectSetting.fromJson(Object? raw, EffectSpec spec) {
    if (raw is num) return EffectSetting.at(raw.toDouble(), spec);
    final json =
        (raw as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    final strength = spec.coerce(
      (json['strength'] as num?)?.toDouble() ?? spec.defaultStrength,
    );
    final resume = spec.coerce(
      (json['resumeStrength'] as num?)?.toDouble() ??
          (strength > 0 ? strength : spec.defaultStrength),
    );
    return EffectSetting(
      strength: strength,
      resumeStrength: resume > 0
          ? resume
          : spec.defaultStrength.clamp(0.01, spec.maxStrength),
    );
  }
}

@immutable
class OpticalOverrides {
  OpticalOverrides({
    this.phosphorName,
    Map<String, EffectSetting> effects = const <String, EffectSetting>{},
  }) : effects = Map<String, EffectSetting>.unmodifiable(effects);

  final String? phosphorName;
  final Map<String, EffectSetting> effects;

  bool get isEmpty => phosphorName == null && effects.isEmpty;
  bool overrides(String effectId) => effects.containsKey(effectId);

  OpticalOverrides withPhosphor(String? value) =>
      OpticalOverrides(phosphorName: value, effects: effects);

  OpticalOverrides withEffect(String id, EffectSetting? value) {
    final next = <String, EffectSetting>{...effects};
    if (value == null) {
      next.remove(id);
    } else {
      next[id] = value;
    }
    return OpticalOverrides(phosphorName: phosphorName, effects: next);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    if (phosphorName != null) 'phosphorName': phosphorName,
    'effects': <String, Object?>{
      for (final entry in effects.entries) entry.key: entry.value.toJson(),
    },
  };

  factory OpticalOverrides.fromJson(Map<String, Object?> json) {
    final effects = <String, EffectSetting>{};
    for (final entry
        in ((json['effects'] as Map?)?.cast<String, Object?>() ?? const {})
            .entries) {
      final spec = EffectSpecs.storageSpec(entry.key);
      effects[entry.key] = EffectSetting.fromJson(entry.value, spec);
    }
    return OpticalOverrides(
      phosphorName: json['phosphorName'] as String?,
      effects: effects,
    );
  }
}

@immutable
class OpticalProfile {
  OpticalProfile({
    this.phosphorName = 'Cyan-green',
    Map<String, EffectSetting> effects = const <String, EffectSetting>{},
  }) : effects = Map<String, EffectSetting>.unmodifiable(effects);

  final String phosphorName;
  final Map<String, EffectSetting> effects;

  Phosphor get phosphor => Phosphor.byName(phosphorName);

  EffectSetting effect(String id) {
    final stored = effects[id];
    if (stored != null) return stored;
    final spec = EffectSpecs.byId(id);
    if (spec == null) {
      return const EffectSetting(strength: 0, resumeStrength: 1);
    }
    return EffectSetting.at(spec.defaultStrength, spec);
  }

  OpticalProfile withPhosphor(String value) =>
      OpticalProfile(phosphorName: value, effects: effects);

  OpticalProfile withEffect(String id, EffectSetting value) => OpticalProfile(
    phosphorName: phosphorName,
    effects: <String, EffectSetting>{...effects, id: value},
  );

  OpticalProfile apply(OpticalOverrides overrides) => OpticalProfile(
    phosphorName: overrides.phosphorName ?? phosphorName,
    effects: <String, EffectSetting>{...effects, ...overrides.effects},
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'phosphorName': phosphorName,
    'effects': <String, Object?>{
      for (final entry in effects.entries) entry.key: entry.value.toJson(),
    },
  };

  factory OpticalProfile.fromJson(Map<String, Object?> json) {
    final effects = <String, EffectSetting>{};
    for (final entry
        in ((json['effects'] as Map?)?.cast<String, Object?>() ?? const {})
            .entries) {
      final spec = EffectSpecs.storageSpec(entry.key);
      effects[entry.key] = EffectSetting.fromJson(entry.value, spec);
    }
    return OpticalProfile(
      phosphorName: json['phosphorName'] as String? ?? 'Cyan-green',
      effects: effects,
    );
  }
}

@immutable
class PrismStyle {
  const PrismStyle({
    this.bevelDepth = 0.12,
    this.faceOpacity = 0.78,
    this.inactiveLuminosity = 0.18,
    this.activeLuminosity = 1,
  });

  final double bevelDepth;
  final double faceOpacity;
  final double inactiveLuminosity;
  final double activeLuminosity;

  PrismStyle copyWith({
    double? bevelDepth,
    double? faceOpacity,
    double? inactiveLuminosity,
    double? activeLuminosity,
  }) => PrismStyle(
    bevelDepth: bevelDepth ?? this.bevelDepth,
    faceOpacity: faceOpacity ?? this.faceOpacity,
    inactiveLuminosity: inactiveLuminosity ?? this.inactiveLuminosity,
    activeLuminosity: activeLuminosity ?? this.activeLuminosity,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'bevelDepth': bevelDepth,
    'faceOpacity': faceOpacity,
    'inactiveLuminosity': inactiveLuminosity,
    'activeLuminosity': activeLuminosity,
  };

  factory PrismStyle.fromJson(Map<String, Object?> json) => PrismStyle(
    bevelDepth: ((json['bevelDepth'] as num?)?.toDouble() ?? 0.12).clamp(
      0,
      0.4,
    ),
    faceOpacity: ((json['faceOpacity'] as num?)?.toDouble() ?? 0.78).clamp(
      0,
      1,
    ),
    inactiveLuminosity:
        ((json['inactiveLuminosity'] as num?)?.toDouble() ?? 0.18).clamp(0, 1),
    activeLuminosity: ((json['activeLuminosity'] as num?)?.toDouble() ?? 1)
        .clamp(0, 2),
  );
}
