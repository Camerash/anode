import 'package:flutter/foundation.dart';

import 'component_instance.dart';
import 'design.dart';
import 'design_preset.dart';
import 'placement.dart';
import 'settings.dart';

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
    required Set<DesignOrientation> supportedOrientations,
    required List<ComponentInstance> components,
    Map<DesignOrientation, double>? frameAspects,
    this.settings = const DashboardSettings(),
    this.sourcePresetId,
    this.sourcePresetVersion,
    this.forkedAt,
  })  : supportedOrientations =
            Set<DesignOrientation>.unmodifiable(supportedOrientations),
        components = List<ComponentInstance>.unmodifiable(components),
        frameAspects =
            normaliseFrameAspects(supportedOrientations, frameAspects);

  /// Snapshots [preset] wholesale. Nothing is shared with the source; the
  /// preset's identity is recorded for provenance only.
  factory Dashboard.forkFrom(
    DesignPreset preset, {
    required String id,
    String? name,
    DateTime? at,
  }) =>
      Dashboard(
        id: id,
        name: name ?? preset.name,
        supportedOrientations: <DesignOrientation>{
          ...preset.supportedOrientations
        },
        components: <ComponentInstance>[
          for (final c in preset.components)
            ComponentInstance(
              id: c.id,
              typeId: c.typeId,
              params: <String, Object?>{...c.params},
              placements: <DesignOrientation, Placement>{...c.placements},
            ),
        ],
        frameAspects: <DesignOrientation, double>{...preset.frameAspects},
        settings: preset.defaults,
        sourcePresetId: preset.id,
        sourcePresetVersion: preset.version,
        forkedAt: at ?? DateTime.now(),
      );

  @override
  final String id;
  @override
  final String name;
  @override
  final Set<DesignOrientation> supportedOrientations;
  @override
  final List<ComponentInstance> components;
  final Map<DesignOrientation, double> frameAspects;
  final DashboardSettings settings;

  /// Provenance only. The preset is never consulted again after the fork.
  final String? sourcePresetId;
  final int? sourcePresetVersion;
  final DateTime? forkedAt;

  @override
  bool supports(DesignOrientation orientation) =>
      supportedOrientations.contains(orientation);

  @override
  DashboardSettings get renderSettings => settings;

  @override
  double frameAspect(DesignOrientation orientation) =>
      frameAspects[orientation] ?? kDefaultFrameAspects[orientation]!;

  @override
  List<ComponentInstance> componentsIn(DesignOrientation orientation) =>
      components.where((c) => c.appearsIn(orientation)).toList();

  Dashboard copyWith({
    String? id,
    String? name,
    Set<DesignOrientation>? supportedOrientations,
    List<ComponentInstance>? components,
    Map<DesignOrientation, double>? frameAspects,
    DashboardSettings? settings,
  }) =>
      Dashboard(
        id: id ?? this.id,
        name: name ?? this.name,
        supportedOrientations:
            supportedOrientations ?? this.supportedOrientations,
        components: components ?? this.components,
        frameAspects: frameAspects ?? this.frameAspects,
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

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': kSchemaVersion,
        'id': id,
        'name': name,
        'supportedOrientations':
            supportedOrientations.map((o) => o.name).toList(),
        'frameAspects': frameAspectsToJson(frameAspects),
        'components': components.map((c) => c.toJson()).toList(),
        'settings': settings.toJson(),
        'sourcePresetId': sourcePresetId,
        'sourcePresetVersion': sourcePresetVersion,
        'forkedAt': forkedAt?.toIso8601String(),
      };

  factory Dashboard.fromJson(Map<String, Object?> json) => Dashboard(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        supportedOrientations: parseOrientations(json['supportedOrientations']),
        frameAspects: parseFrameAspects(json['frameAspects']),
        components: parseComponents(json['components']),
        settings: DashboardSettings.fromJson(
            (json['settings'] as Map?)?.cast<String, Object?>() ??
                const <String, Object?>{}),
        sourcePresetId: json['sourcePresetId'] as String?,
        sourcePresetVersion: (json['sourcePresetVersion'] as num?)?.toInt(),
        forkedAt: switch (json['forkedAt']) {
          final String s => DateTime.tryParse(s),
          _ => null,
        },
      );
}
