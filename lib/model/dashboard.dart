import 'package:flutter/foundation.dart';

import 'component_instance.dart';
import 'design.dart';
import 'design_layout.dart';
import 'design_preset.dart';
import 'placement.dart';
import 'settings.dart';
import 'vfd_module.dart';

@immutable
class Dashboard implements Design {
  Dashboard({
    required this.id,
    required this.name,
    required this.baseLayoutId,
    required List<DesignLayout> layouts,
    required List<ComponentInstance> components,
    this.screenSetup = const ScreenSetup.adapt(),
    List<VfdModule>? modules,
    DashboardSettings? settings,
    this.sourcePresetId,
    this.sourcePresetVersion,
    this.forkedAt,
  }) : layouts = normaliseDesignLayouts(layouts),
       components = List<ComponentInstance>.unmodifiable(components),
       modules = normaliseVfdModules(modules),
       settings = settings ?? DashboardSettings() {
    if (!this.layouts.any((layout) => layout.id == baseLayoutId)) {
      throw ArgumentError.value(baseLayoutId, 'baseLayoutId');
    }
  }

  factory Dashboard.forkFrom(
    DesignPreset preset, {
    required String id,
    String? name,
    DateTime? at,
  }) => Dashboard(
    id: id,
    name: name ?? preset.name,
    baseLayoutId: preset.baseLayoutId,
    layouts: preset.layouts,
    screenSetup: preset.screenSetup,
    components: <ComponentInstance>[
      for (final component in preset.components)
        ComponentInstance(
          id: component.id,
          typeId: component.typeId,
          params: <String, Object?>{...component.params},
          placements: <String, Placement>{...component.placements},
          moduleId: component.moduleId,
          variant: component.variant,
          opticalOverrides: component.opticalOverrides,
          actionBinding: component.actionBinding,
        ),
    ],
    modules: preset.modules,
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
  }) => source.copyWith(id: id, name: name, forkedAt: at ?? DateTime.now());

  @override
  final String id;
  @override
  final String name;
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
  final DashboardSettings settings;
  final String? sourcePresetId;
  final int? sourcePresetVersion;
  final DateTime? forkedAt;

  @override
  DashboardSettings get renderSettings => settings;

  @override
  VfdModule moduleFor(ComponentInstance component) => modules.firstWhere(
    (module) => module.id == component.moduleId,
    orElse: () => modules.first,
  );

  Dashboard copyWith({
    String? id,
    String? name,
    String? baseLayoutId,
    List<DesignLayout>? layouts,
    ScreenSetup? screenSetup,
    List<ComponentInstance>? components,
    List<VfdModule>? modules,
    DashboardSettings? settings,
    DateTime? forkedAt,
  }) => Dashboard(
    id: id ?? this.id,
    name: name ?? this.name,
    baseLayoutId: baseLayoutId ?? this.baseLayoutId,
    layouts: layouts ?? this.layouts,
    screenSetup: screenSetup ?? this.screenSetup,
    components: components ?? this.components,
    modules: modules ?? this.modules,
    settings: settings ?? this.settings,
    sourcePresetId: sourcePresetId,
    sourcePresetVersion: sourcePresetVersion,
    forkedAt: forkedAt ?? this.forkedAt,
  );

  Dashboard withComponent(ComponentInstance component) {
    final next = <ComponentInstance>[...components];
    final index = next.indexWhere((value) => value.id == component.id);
    if (index < 0) {
      next.add(component);
    } else {
      next[index] = component;
    }
    return copyWith(components: next);
  }

  Dashboard withoutComponent(String componentId) => copyWith(
    components: components.where((value) => value.id != componentId).toList(),
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
    return copyWith(
      modules: modules.where((module) => module.id != moduleId).toList(),
      components: <ComponentInstance>[
        for (final component in components)
          component.moduleId == moduleId
              ? component.copyWith(moduleId: kMainVfdModuleId)
              : component,
      ],
    );
  }

  Dashboard withLayout({
    required String id,
    required double aspect,
    required String sourceLayoutId,
  }) {
    if (layouts.any((layout) => layout.id == id)) return this;
    final source = layout(sourceLayoutId);
    final target = DesignLayout(
      id: id,
      frame: containingFrameForAspect(source.frame, aspect),
    );
    return copyWith(
      layouts: <DesignLayout>[...layouts, target],
      components: <ComponentInstance>[
        for (final component in components)
          if (component.placements[sourceLayoutId]
              case final Placement placement)
            component.withPlacement(id, placement)
          else
            component,
      ],
      modules: <VfdModule>[
        for (final module in modules)
          if (module.regionIn(sourceLayoutId) case final Placement region)
            module.copyWith(
              regions: <String, Placement>{...module.regions, id: region},
            )
          else
            module,
      ],
    );
  }

  Dashboard withLayoutAspect(String layoutId, double aspect) {
    if (!aspect.isFinite || aspect <= 0) return this;
    return copyWith(
      layouts: <DesignLayout>[
        for (final layout in layouts)
          if (layout.id == layoutId)
            DesignLayout(
              id: layout.id,
              frame: FrameSpec(
                width: layout.frame.height * aspect,
                height: layout.frame.height,
              ),
            )
          else
            layout,
      ],
    );
  }

  Dashboard withoutLayout(String layoutId) {
    if (layoutId == baseLayoutId || layouts.length == 1) return this;
    final nextSetup = screenSetup.lockedLayoutId == layoutId
        ? const ScreenSetup.adapt()
        : screenSetup;
    return copyWith(
      layouts: layouts.where((layout) => layout.id != layoutId).toList(),
      screenSetup: nextSetup,
      components: <ComponentInstance>[
        for (final component in components)
          component.withPlacement(layoutId, null),
      ],
      modules: <VfdModule>[
        for (final module in modules)
          module.copyWith(
            regions: <String, Placement>{...module.regions}..remove(layoutId),
          ),
      ],
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': kSchemaVersion,
    'id': id,
    'name': name,
    'baseLayoutId': baseLayoutId,
    'layouts': layouts.map((layout) => layout.toJson()).toList(),
    'screenSetup': screenSetup.toJson(),
    'components': components.map((component) => component.toJson()).toList(),
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
    return Dashboard(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      baseLayoutId: json['baseLayoutId'] as String? ?? '',
      layouts: parseDesignLayouts(json['layouts']),
      screenSetup: ScreenSetup.fromJson(json['screenSetup']),
      components: parseComponents(json['components']),
      modules: parseVfdModules(json['modules']),
      settings: DashboardSettings.fromJson(
        (json['settings'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
      sourcePresetId: json['sourcePresetId'] as String?,
      sourcePresetVersion: (json['sourcePresetVersion'] as num?)?.toInt(),
      forkedAt: switch (json['forkedAt']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
    );
  }
}
