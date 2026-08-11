import 'package:flutter/foundation.dart';

import 'optical_profile.dart';
import 'placement.dart';
import 'variant.dart';

const String kMainVfdModuleId = 'main';

@immutable
class FilamentVariantSpec {
  const FilamentVariantSpec({
    required this.reference,
    required this.displayName,
    required this.rendererCode,
    this.deprecated = false,
  });

  final VariantReference reference;
  final String displayName;
  final int rendererCode;
  final bool deprecated;
}

abstract final class FilamentVariants {
  static const List<FilamentVariantSpec> all = <FilamentVariantSpec>[
    FilamentVariantSpec(
      reference: VariantReference(id: 'filament.straight', revision: 1),
      displayName: 'Straight tri-wire',
      rendererCode: 0,
    ),
  ];

  static FilamentVariantSpec? byReference(VariantReference reference) {
    for (final variant in all) {
      if (variant.reference == reference) return variant;
    }
    return null;
  }
}

@immutable
class VfdModule {
  VfdModule({
    required this.id,
    required this.name,
    Map<String, Placement> regions = const <String, Placement>{},
    this.filamentVariant = const VariantReference(
      id: 'filament.straight',
      revision: 1,
    ),
    OpticalOverrides? opticalOverrides,
  }) : regions = Map<String, Placement>.unmodifiable(regions),
       opticalOverrides = opticalOverrides ?? OpticalOverrides();

  factory VfdModule.main() => VfdModule(id: kMainVfdModuleId, name: 'Main VFD');

  final String id;
  final String name;
  final Map<String, Placement> regions;
  final VariantReference filamentVariant;
  final OpticalOverrides opticalOverrides;

  Placement? regionIn(String layoutId) => regions[layoutId];

  VfdModule copyWith({
    String? id,
    String? name,
    Map<String, Placement>? regions,
    VariantReference? filamentVariant,
    OpticalOverrides? opticalOverrides,
  }) => VfdModule(
    id: id ?? this.id,
    name: name ?? this.name,
    regions: regions ?? this.regions,
    filamentVariant: filamentVariant ?? this.filamentVariant,
    opticalOverrides: opticalOverrides ?? this.opticalOverrides,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'regions': <String, Object?>{
      for (final entry in regions.entries) entry.key: entry.value.toJson(),
    },
    'filamentVariant': filamentVariant.toJson(),
    'opticalOverrides': opticalOverrides.toJson(),
  };

  factory VfdModule.fromJson(Map<String, Object?> json) {
    final regions = <String, Placement>{};
    for (final entry
        in ((json['regions'] as Map?)?.cast<String, Object?>() ?? const {})
            .entries) {
      if (entry.key.isEmpty || entry.value is! Map) continue;
      regions[entry.key] = Placement.fromJson(
        (entry.value as Map).cast<String, Object?>(),
      );
    }
    return VfdModule(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'VFD module',
      regions: regions,
      filamentVariant: VariantReference.fromJson(
        (json['filamentVariant'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
      opticalOverrides: OpticalOverrides.fromJson(
        (json['opticalOverrides'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
    );
  }
}

List<VfdModule> normaliseVfdModules(Iterable<VfdModule>? raw) {
  final byId = <String, VfdModule>{};
  for (final module in raw ?? const <VfdModule>[]) {
    if (module.id.isEmpty || byId.containsKey(module.id)) continue;
    byId[module.id] = module;
  }
  byId.putIfAbsent(kMainVfdModuleId, VfdModule.main);
  return List<VfdModule>.unmodifiable(<VfdModule>[
    byId.remove(kMainVfdModuleId)!,
    ...byId.values,
  ]);
}

List<VfdModule> parseVfdModules(Object? raw) {
  final modules = <VfdModule>[];
  for (final value in (raw as List?) ?? const <Object?>[]) {
    if (value is! Map) continue;
    modules.add(VfdModule.fromJson(value.cast<String, Object?>()));
  }
  return normaliseVfdModules(modules);
}
