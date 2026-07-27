import 'package:flutter/foundation.dart';

import 'component_type.dart';
import 'placement.dart';

/// One component placed in a design.
///
/// A missing placement for an orientation means the component does not exist in
/// that orientation. That is what makes per-orientation layouts authored rather
/// than reflowed: a design can legitimately show a gauge in landscape and drop
/// it entirely in portrait.
@immutable
class ComponentInstance {
  ComponentInstance({
    required this.id,
    required this.typeId,
    Map<String, Object?> params = const <String, Object?>{},
    Map<DesignOrientation, Placement> placements =
        const <DesignOrientation, Placement>{},
  })  : params = Map<String, Object?>.unmodifiable(params),
        placements =
            Map<DesignOrientation, Placement>.unmodifiable(placements);

  final String id;
  final String typeId;
  final Map<String, Object?> params;
  final Map<DesignOrientation, Placement> placements;

  ComponentTypeSpec? get type => ComponentTypes.byId(typeId);

  bool appearsIn(DesignOrientation orientation) =>
      placements.containsKey(orientation);

  /// Params with defaults filled in and known values coerced. Falls back to the
  /// stored map for a type the registry does not know.
  Map<String, Object?> get effectiveParams =>
      type?.normalise(params) ?? Map<String, Object?>.from(params);

  ComponentInstance copyWith({
    String? id,
    String? typeId,
    Map<String, Object?>? params,
    Map<DesignOrientation, Placement>? placements,
  }) =>
      ComponentInstance(
        id: id ?? this.id,
        typeId: typeId ?? this.typeId,
        params: params ?? this.params,
        placements: placements ?? this.placements,
      );

  ComponentInstance withParam(String key, Object? value) =>
      copyWith(params: <String, Object?>{...params, key: value});

  ComponentInstance withPlacement(
    DesignOrientation orientation,
    Placement? placement,
  ) {
    final next = <DesignOrientation, Placement>{...placements};
    if (placement == null) {
      next.remove(orientation);
    } else {
      next[orientation] = placement;
    }
    return copyWith(placements: next);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'typeId': typeId,
        'params': params,
        'placements': <String, Object?>{
          for (final e in placements.entries) e.key.name: e.value.toJson(),
        },
      };

  factory ComponentInstance.fromJson(Map<String, Object?> json) {
    final rawPlacements =
        json['placements'] as Map<String, Object?>? ?? const <String, Object?>{};
    final placements = <DesignOrientation, Placement>{};
    for (final e in rawPlacements.entries) {
      final orientation = DesignOrientation.byName(e.key);
      if (orientation == null) continue; // unknown orientation: ignore
      placements[orientation] =
          Placement.fromJson((e.value as Map).cast<String, Object?>());
    }
    return ComponentInstance(
      id: json['id'] as String? ?? '',
      typeId: json['typeId'] as String? ?? '',
      params: (json['params'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{},
      placements: placements,
    );
  }
}
