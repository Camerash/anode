import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'component_instance.dart';
import 'design.dart';
import 'placement.dart';
import 'settings.dart';
import 'vfd_module.dart';

/// Bumped when the stored shape changes in a way older builds cannot read.
const int kSchemaVersion = 4;

/// A shipped design: immutable, versioned, and never edited in place. Editing
/// one forks it into a [Dashboard].
@immutable
class DesignPreset implements Design {
  DesignPreset({
    required this.id,
    required this.name,
    required this.version,
    required List<ComponentInstance> components,
    this.primaryOrientation = DesignOrientation.landscape,
    List<VfdModule>? modules,
    Map<DesignOrientation, FrameSpec>? frameSpecs,
    Map<DesignOrientation, double>? frameAspects,
    DashboardSettings? defaults,
  }) : components = List<ComponentInstance>.unmodifiable(components),
       modules = normaliseVfdModules(modules),
       frameSpecs = normaliseFrameSpecs(
         primaryOrientation,
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
  final DesignOrientation primaryOrientation;
  @override
  Set<DesignOrientation> get authoredOrientations =>
      Set<DesignOrientation>.unmodifiable(frameSpecs.keys);
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
  bool hasAuthoredLayout(DesignOrientation orientation) =>
      frameSpecs.containsKey(orientation);

  @override
  DesignOrientation layoutForViewport(DesignOrientation orientation) =>
      hasAuthoredLayout(orientation) ? orientation : primaryOrientation;

  @override
  FrameSpec frameSpec(DesignOrientation orientation) =>
      frameSpecs[orientation] ?? frameSpecs[primaryOrientation]!;

  @override
  double frameAspect(DesignOrientation orientation) =>
      frameSpec(orientation).referenceAspect;

  @override
  Size frameExtent(DesignOrientation orientation) =>
      frameSpec(orientation).extent;

  @override
  List<ComponentInstance> componentsIn(DesignOrientation orientation) =>
      components
          .where((c) => c.appearsIn(layoutForViewport(orientation)))
          .toList();

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
    'primaryOrientation': primaryOrientation.name,
    'frameSpecs': frameSpecsToJson(frameSpecs),
    'components': components.map((c) => c.toJson()).toList(),
    'modules': modules.map((module) => module.toJson()).toList(),
    'defaults': defaults.toJson(),
  };

  factory DesignPreset.fromJson(Map<String, Object?> json) {
    final specs = parseFrameSpecs(json['frameSpecs']);
    final legacyAspects = parseFrameAspects(json['frameAspects']);
    return DesignPreset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
      primaryOrientation: parsePrimaryOrientation(
        json['primaryOrientation'],
        specs: specs,
        legacyAspects: legacyAspects,
        legacySupported: json['supportedOrientations'],
      ),
      frameSpecs: specs,
      frameAspects: legacyAspects,
      components: parseComponents(json['components']),
      modules: parseVfdModules(json['modules']),
      defaults: DashboardSettings.fromJson(
        (json['defaults'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
    );
  }
}

DesignOrientation parsePrimaryOrientation(
  Object? raw, {
  required Map<DesignOrientation, FrameSpec> specs,
  required Map<DesignOrientation, double> legacyAspects,
  Object? legacySupported,
}) {
  final explicit = DesignOrientation.byName(raw as String? ?? '');
  if (explicit != null) return explicit;
  if (specs.containsKey(DesignOrientation.landscape) ||
      legacyAspects.containsKey(DesignOrientation.landscape)) {
    return DesignOrientation.landscape;
  }
  for (final value in (legacySupported as List?) ?? const <Object?>[]) {
    final parsed = DesignOrientation.byName(value as String? ?? '');
    if (parsed != null) return parsed;
  }
  return specs.keys.firstOrNull ??
      legacyAspects.keys.firstOrNull ??
      DesignOrientation.landscape;
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
