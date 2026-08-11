import 'package:flutter/foundation.dart';

import 'component_instance.dart';
import 'design.dart';
import 'design_layout.dart';
import 'settings.dart';
import 'vfd_module.dart';

/// Bumped when stored shape changes. Prototyping builds do not migrate data.
const int kSchemaVersion = 6;

@immutable
class DesignPreset implements Design {
  DesignPreset({
    required this.id,
    required this.name,
    required this.version,
    required this.baseLayoutId,
    required List<DesignLayout> layouts,
    required List<ComponentInstance> components,
    this.screenSetup = const ScreenSetup.adapt(),
    List<VfdModule>? modules,
    DashboardSettings? defaults,
  }) : layouts = normaliseDesignLayouts(layouts),
       components = List<ComponentInstance>.unmodifiable(components),
       modules = normaliseVfdModules(modules),
       defaults = defaults ?? DashboardSettings() {
    if (!this.layouts.any((layout) => layout.id == baseLayoutId)) {
      throw ArgumentError.value(baseLayoutId, 'baseLayoutId');
    }
  }

  @override
  final String id;
  @override
  final String name;
  final int version;
  @override
  final String baseLayoutId;
  @override
  final List<DesignLayout> layouts;
  @override
  final ScreenSetup screenSetup;
  @override
  final List<ComponentInstance> components;
  @override
  final List<VfdModule> modules;
  final DashboardSettings defaults;

  @override
  DashboardSettings get renderSettings => defaults;

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
    'baseLayoutId': baseLayoutId,
    'layouts': layouts.map((layout) => layout.toJson()).toList(),
    'screenSetup': screenSetup.toJson(),
    'components': components.map((component) => component.toJson()).toList(),
    'modules': modules.map((module) => module.toJson()).toList(),
    'defaults': defaults.toJson(),
  };

  factory DesignPreset.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != kSchemaVersion) {
      throw const FormatException('Unsupported design preset schema');
    }
    return DesignPreset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: (json['version'] as num?)?.toInt() ?? 1,
      baseLayoutId: json['baseLayoutId'] as String? ?? '',
      layouts: parseDesignLayouts(json['layouts']),
      screenSetup: ScreenSetup.fromJson(json['screenSetup']),
      components: parseComponents(json['components']),
      modules: parseVfdModules(json['modules']),
      defaults: DashboardSettings.fromJson(
        (json['defaults'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
    );
  }
}

List<DesignLayout> parseDesignLayouts(Object? raw) => <DesignLayout>[
  for (final value in (raw as List?) ?? const <Object?>[])
    if (value is Map) DesignLayout.fromJson(value.cast<String, Object?>()),
];

List<ComponentInstance> parseComponents(Object? raw) => <ComponentInstance>[
  for (final value in (raw as List?) ?? const <Object?>[])
    if (value is Map) ComponentInstance.fromJson(value.cast<String, Object?>()),
];
