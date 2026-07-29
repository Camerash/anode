import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'component_instance.dart';
import 'design.dart';
import 'design_preset.dart';
import 'placement.dart';
import 'settings.dart';
import 'vfd_module.dart';

/// A user's instance of a design.
///
/// Editing a preset forks it into one of these, which the user then owns and
/// which is never auto-updated. This is copy-on-customize: the fork is a full
/// snapshot. Do NOT add delta-merging against updated presets — it sounds more
/// elegant and causes pain forever.
@immutable
class Dashboard implements Design {
  Dashboard({
    required this.id,
    required this.name,
    required List<ComponentInstance> components,
    this.primaryOrientation = DesignOrientation.landscape,
    List<VfdModule>? modules,
    Map<DesignOrientation, FrameSpec>? frameSpecs,
    Map<DesignOrientation, double>? frameAspects,
    DashboardSettings? settings,
    this.sourcePresetId,
    this.sourcePresetVersion,
    this.forkedAt,
  }) : components = List<ComponentInstance>.unmodifiable(components),
       modules = normaliseVfdModules(modules),
       frameSpecs = normaliseFrameSpecs(
         primaryOrientation,
         specs: frameSpecs,
         legacyAspects: frameAspects,
       ),
       settings = settings ?? DashboardSettings();

  /// Snapshots [preset] wholesale. Nothing is shared with the source; the
  /// preset's identity is recorded for provenance only.
  factory Dashboard.forkFrom(
    DesignPreset preset, {
    required String id,
    String? name,
    DateTime? at,
  }) => Dashboard(
    id: id,
    name: name ?? preset.name,
    primaryOrientation: preset.primaryOrientation,
    components: <ComponentInstance>[
      for (final c in preset.components)
        ComponentInstance(
          id: c.id,
          typeId: c.typeId,
          params: <String, Object?>{...c.params},
          placements: <DesignOrientation, Placement>{...c.placements},
          moduleId: c.moduleId,
          variant: c.variant,
          opticalOverrides: c.opticalOverrides,
          actionBinding: c.actionBinding,
        ),
    ],
    modules: <VfdModule>[...preset.modules],
    frameSpecs: <DesignOrientation, FrameSpec>{...preset.frameSpecs},
    settings: preset.defaults,
    sourcePresetId: preset.id,
    sourcePresetVersion: preset.version,
    forkedAt: at ?? DateTime.now(),
  );

  factory Dashboard.cloneFrom(
    Dashboard source, {
    required String id,
    required String name,
    DateTime? at,
  }) => Dashboard(
    id: id,
    name: name,
    primaryOrientation: source.primaryOrientation,
    components: <ComponentInstance>[...source.components],
    modules: <VfdModule>[...source.modules],
    frameSpecs: <DesignOrientation, FrameSpec>{...source.frameSpecs},
    settings: source.settings,
    sourcePresetId: source.sourcePresetId,
    sourcePresetVersion: source.sourcePresetVersion,
    forkedAt: at ?? DateTime.now(),
  );

  @override
  final String id;
  @override
  final String name;
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
  final DashboardSettings settings;

  /// Provenance only. The preset is never consulted again after the fork.
  final String? sourcePresetId;
  final int? sourcePresetVersion;
  final DateTime? forkedAt;

  @override
  bool hasAuthoredLayout(DesignOrientation orientation) =>
      frameSpecs.containsKey(orientation);

  @override
  DesignOrientation layoutForViewport(DesignOrientation orientation) =>
      hasAuthoredLayout(orientation) ? orientation : primaryOrientation;

  @override
  DashboardSettings get renderSettings => settings;

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

  Dashboard copyWith({
    String? id,
    String? name,
    DesignOrientation? primaryOrientation,
    List<ComponentInstance>? components,
    List<VfdModule>? modules,
    Map<DesignOrientation, FrameSpec>? frameSpecs,
    Map<DesignOrientation, double>? frameAspects,
    DashboardSettings? settings,
  }) => Dashboard(
    id: id ?? this.id,
    name: name ?? this.name,
    primaryOrientation: primaryOrientation ?? this.primaryOrientation,
    components: components ?? this.components,
    modules: modules ?? this.modules,
    frameSpecs:
        frameSpecs ??
        (frameAspects == null
            ? this.frameSpecs
            : normaliseFrameSpecs(
                primaryOrientation ?? this.primaryOrientation,
                legacyAspects: frameAspects,
              )),
    settings: settings ?? this.settings,
    sourcePresetId: sourcePresetId,
    sourcePresetVersion: sourcePresetVersion,
    forkedAt: forkedAt,
  );

  Dashboard withComponent(ComponentInstance component) {
    final next = <ComponentInstance>[...components];
    final i = next.indexWhere((c) => c.id == component.id);
    if (i == -1) {
      next.add(component);
    } else {
      next[i] = component;
    }
    return copyWith(components: next);
  }

  Dashboard withoutComponent(String componentId) => copyWith(
    components: components.where((c) => c.id != componentId).toList(),
  );

  Dashboard reorderComponent(int from, int to) {
    final next = <ComponentInstance>[...components];
    final moved = next.removeAt(from);
    next.insert(to.clamp(0, next.length), moved);
    return copyWith(components: next);
  }

  Dashboard withModule(VfdModule module) {
    final next = <VfdModule>[...modules];
    final index = next.indexWhere((value) => value.id == module.id);
    if (index < 0) {
      next.add(module);
    } else {
      next[index] = module;
    }
    return copyWith(modules: next);
  }

  Dashboard withoutModule(String moduleId) {
    if (moduleId == kMainVfdModuleId) return this;
    final nextComponents = <ComponentInstance>[
      for (final component in components)
        if (component.moduleId == moduleId)
          component.copyWith(moduleId: kMainVfdModuleId)
        else
          component,
    ];
    return copyWith(
      modules: modules.where((module) => module.id != moduleId).toList(),
      components: nextComponents,
    );
  }

  /// Creates an independently editable alternate layout whose initial visual
  /// appearance matches the contained primary layout.
  ///
  /// [extent] comes from [viewportFrameExtent], so the new envelope renders at
  /// the fit scale the primary already had and placements can be copied
  /// verbatim.
  Dashboard withBakedLayout(
    DesignOrientation orientation, {
    required Size extent,
  }) {
    final target = FrameSpec(width: extent.width, height: extent.height);
    if (hasAuthoredLayout(orientation) || !target.isValid) return this;
    final sourceOrientation = primaryOrientation;
    final bakedComponents = <ComponentInstance>[
      for (final component in components)
        if (component.appearsIn(sourceOrientation))
          component.withPlacement(
            orientation,
            component.placements[sourceOrientation]!,
          )
        else
          component,
    ];
    final bakedModules = <VfdModule>[
      for (final module in modules)
        if (module.regionIn(sourceOrientation) case final region?)
          module.copyWith(
            regions: <DesignOrientation, Placement>{
              ...module.regions,
              orientation: region,
            },
          )
        else
          module,
    ];
    return copyWith(
      frameSpecs: <DesignOrientation, FrameSpec>{
        ...frameSpecs,
        orientation: target,
      },
      components: bakedComponents,
      modules: bakedModules,
    );
  }

  Dashboard withoutLayout(DesignOrientation orientation) {
    if (orientation == primaryOrientation || !hasAuthoredLayout(orientation)) {
      return this;
    }
    final nextSpecs = <DesignOrientation, FrameSpec>{...frameSpecs}
      ..remove(orientation);
    return copyWith(
      frameSpecs: nextSpecs,
      components: <ComponentInstance>[
        for (final component in components)
          component.withPlacement(orientation, null),
      ],
      modules: <VfdModule>[
        for (final module in modules)
          module.copyWith(
            regions: <DesignOrientation, Placement>{...module.regions}
              ..remove(orientation),
          ),
      ],
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': kSchemaVersion,
    'id': id,
    'name': name,
    'primaryOrientation': primaryOrientation.name,
    'frameSpecs': frameSpecsToJson(frameSpecs),
    'components': components.map((c) => c.toJson()).toList(),
    'modules': modules.map((module) => module.toJson()).toList(),
    'settings': settings.toJson(),
    'sourcePresetId': sourcePresetId,
    'sourcePresetVersion': sourcePresetVersion,
    'forkedAt': forkedAt?.toIso8601String(),
  };

  factory Dashboard.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != kSchemaVersion) {
      throw const FormatException('Unsupported dashboard schema');
    }
    final specs = parseFrameSpecs(json['frameSpecs']);
    final legacyAspects = parseFrameAspects(json['frameAspects']);
    return Dashboard(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
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
      settings: DashboardSettings.fromJson(
        (json['settings'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
      sourcePresetId: json['sourcePresetId'] as String?,
      sourcePresetVersion: (json['sourcePresetVersion'] as num?)?.toInt(),
      forkedAt: switch (json['forkedAt']) {
        final String s => DateTime.tryParse(s),
        _ => null,
      },
    );
  }
}
