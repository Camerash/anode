import 'package:flutter/foundation.dart';

import 'component_instance.dart';
import 'component_type.dart';
import 'design.dart';
import 'placement.dart';
import 'settings.dart';
import 'vfd_module.dart';

/// Bumped when the stored shape changes in a way older builds cannot read.
const int kSchemaVersion = 2;

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
    Map<DesignOrientation, double>? frameAspects,
    DashboardSettings? defaults,
  }) : supportedOrientations = Set<DesignOrientation>.unmodifiable(
         supportedOrientations,
       ),
       components = List<ComponentInstance>.unmodifiable(components),
       modules = normaliseVfdModules(modules),
       frameAspects = normaliseFrameAspects(
         supportedOrientations,
         frameAspects,
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
  final Map<DesignOrientation, double> frameAspects;
  final DashboardSettings defaults;

  @override
  DashboardSettings get renderSettings => defaults;

  @override
  bool supports(DesignOrientation orientation) =>
      supportedOrientations.contains(orientation);

  @override
  double frameAspect(DesignOrientation orientation) =>
      frameAspects[orientation] ?? kDefaultFrameAspects[orientation]!;

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
    'frameAspects': frameAspectsToJson(frameAspects),
    'components': components.map((c) => c.toJson()).toList(),
    'modules': modules.map((module) => module.toJson()).toList(),
    'defaults': defaults.toJson(),
  };

  factory DesignPreset.fromJson(Map<String, Object?> json) => DesignPreset(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    version: (json['version'] as num?)?.toInt() ?? 1,
    supportedOrientations: parseOrientations(json['supportedOrientations']),
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

/// Components whose type the registry does not know are dropped rather than
/// throwing. A build that no longer ships a component type must still be able
/// to open a dashboard that used it.
List<ComponentInstance> parseComponents(Object? raw) {
  final out = <ComponentInstance>[];
  for (final v in (raw as List?) ?? const <Object?>[]) {
    final instance = ComponentInstance.fromJson(
      (v as Map).cast<String, Object?>(),
    );
    if (ComponentTypes.byId(instance.typeId) == null) continue;
    out.add(instance);
  }
  return out;
}
