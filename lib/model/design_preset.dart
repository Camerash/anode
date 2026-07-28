import 'package:flutter/foundation.dart';

import 'component_instance.dart';
import 'design.dart';
import 'placement.dart';
import 'settings.dart';
import 'vfd_module.dart';

/// Bumped when the stored shape changes in a way older builds cannot read.
const int kSchemaVersion = 3;

/// A shipped design: immutable, versioned, and never edited in place. Editing
/// one forks it into a [Dashboard].
@immutable
class DesignPreset implements Design {
  DesignPreset({
    required this.id,
    required this.name,
    required this.version,
    required Set<DesignOrientation> supportedOrientations,
    required List<ComponentInstance> components,
    List<VfdModule>? modules,
    Map<DesignOrientation, FrameSpec>? frameSpecs,
    Map<DesignOrientation, double>? frameAspects,
    DashboardSettings? defaults,
  }) : supportedOrientations = Set<DesignOrientation>.unmodifiable(
         supportedOrientations,
       ),
       components = List<ComponentInstance>.unmodifiable(components),
       modules = normaliseVfdModules(modules),
       frameSpecs = normaliseFrameSpecs(
         supportedOrientations,
         specs: frameSpecs,
         legacyAspects: frameAspects,
       ),
       defaults = defaults ?? DashboardSettings();

  @override
  final String id;
  @override
  final String name;
  final int version;
  @override
  final Set<DesignOrientation> supportedOrientations;
  @override
  final List<ComponentInstance> components;
  @override
  final List<VfdModule> modules;
  @override
  final Map<DesignOrientation, FrameSpec> frameSpecs;
  Map<DesignOrientation, double> get frameAspects =>
      Map<DesignOrientation, double>.unmodifiable(<DesignOrientation, double>{
        for (final entry in frameSpecs.entries)
          entry.key: entry.value.referenceAspect,
      });
  final DashboardSettings defaults;

  @override
  DashboardSettings get renderSettings => defaults;

  @override
  bool supports(DesignOrientation orientation) =>
      supportedOrientations.contains(orientation);

  @override
  FrameSpec frameSpec(DesignOrientation orientation) =>
      frameSpecs[orientation] ??
      FrameSpec(referenceAspect: kDefaultFrameAspects[orientation]!);

  @override
  double frameAspect(DesignOrientation orientation, {double? viewportAspect}) =>
      frameSpec(orientation).resolve(viewportAspect: viewportAspect);

  @override
  List<ComponentInstance> componentsIn(DesignOrientation orientation) =>
      components.where((c) => c.appearsIn(orientation)).toList();

  @override
  VfdModule moduleFor(ComponentInstance component) => modules.firstWhere(
    (module) => module.id == component.moduleId,
    orElse: () => modules.first,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': kSchemaVersion,
    'id': id,
    'name': name,
    'version': version,
    'supportedOrientations': supportedOrientations.map((o) => o.name).toList(),
    'frameSpecs': frameSpecsToJson(frameSpecs),
    'components': components.map((c) => c.toJson()).toList(),
    'modules': modules.map((module) => module.toJson()).toList(),
    'defaults': defaults.toJson(),
  };

  factory DesignPreset.fromJson(Map<String, Object?> json) => DesignPreset(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    version: (json['version'] as num?)?.toInt() ?? 1,
    supportedOrientations: parseOrientations(json['supportedOrientations']),
    frameSpecs: parseFrameSpecs(json['frameSpecs']),
    frameAspects: parseFrameAspects(json['frameAspects']),
    components: parseComponents(json['components']),
    modules: parseVfdModules(json['modules']),
    defaults: DashboardSettings.fromJson(
      (json['defaults'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{},
    ),
  );
}

Set<DesignOrientation> parseOrientations(Object? raw) {
  final out = <DesignOrientation>{};
  for (final v in (raw as List?) ?? const <Object?>[]) {
    final o = DesignOrientation.byName(v as String? ?? '');
    if (o != null) out.add(o);
  }
  return out.isEmpty ? <DesignOrientation>{DesignOrientation.landscape} : out;
}

/// Unknown types survive so imported designs from newer builds round-trip
/// without data loss. Rendering skips them and the editor presents their stable
/// type id as unavailable.
List<ComponentInstance> parseComponents(Object? raw) {
  final out = <ComponentInstance>[];
  for (final v in (raw as List?) ?? const <Object?>[]) {
    final instance = ComponentInstance.fromJson(
      (v as Map).cast<String, Object?>(),
    );
    out.add(instance);
  }
  return out;
}
