import 'package:flutter/foundation.dart';

import 'action_binding.dart';
import 'component_type.dart';
import 'optical_profile.dart';
import 'placement.dart';
import 'variant.dart';
import 'vfd_module.dart';

const Object _unsetComponentField = Object();

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
    this.moduleId = kMainVfdModuleId,
    this.variant,
    OpticalOverrides? opticalOverrides,
    this.actionBinding,
  }) : params = Map<String, Object?>.unmodifiable(params),
       placements = Map<DesignOrientation, Placement>.unmodifiable(placements),
       opticalOverrides = opticalOverrides ?? OpticalOverrides();

  final String id;
  final String typeId;
  final Map<String, Object?> params;
  final Map<DesignOrientation, Placement> placements;
  final String moduleId;
  final VariantReference? variant;
  final OpticalOverrides opticalOverrides;
  final ActionBinding? actionBinding;

  ComponentTypeSpec? get type => ComponentTypes.byId(typeId);
  VariantReference get effectiveVariant =>
      variant ?? type?.legacyVariant ?? const VariantReference(id: 'legacy');

  bool appearsIn(DesignOrientation orientation) =>
      placements.containsKey(orientation);

  /// Params with defaults filled in and known values coerced. Falls back to the
  /// stored map for a type the registry does not know.
  Map<String, Object?> get effectiveParams =>
      type?.normalise(params, variant: effectiveVariant) ??
      Map<String, Object?>.from(params);

  ComponentInstance copyWith({
    String? id,
    String? typeId,
    Map<String, Object?>? params,
    Map<DesignOrientation, Placement>? placements,
    String? moduleId,
    Object? variant = _unsetComponentField,
    OpticalOverrides? opticalOverrides,
    Object? actionBinding = _unsetComponentField,
  }) => ComponentInstance(
    id: id ?? this.id,
    typeId: typeId ?? this.typeId,
    params: params ?? this.params,
    placements: placements ?? this.placements,
    moduleId: moduleId ?? this.moduleId,
    variant: identical(variant, _unsetComponentField)
        ? this.variant
        : variant as VariantReference?,
    opticalOverrides: opticalOverrides ?? this.opticalOverrides,
    actionBinding: identical(actionBinding, _unsetComponentField)
        ? this.actionBinding
        : actionBinding as ActionBinding?,
  );

  ComponentInstance withParam(String key, Object? value) =>
      copyWith(params: <String, Object?>{...params, key: value});

  ComponentInstance withOpticalOverrides(OpticalOverrides value) =>
      copyWith(opticalOverrides: value);

  ComponentInstance withAction(ActionBinding? value) =>
      copyWith(actionBinding: value);

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
    'moduleId': moduleId,
    if (variant != null) 'variant': variant!.toJson(),
    'opticalOverrides': opticalOverrides.toJson(),
    if (actionBinding != null) 'actionBinding': actionBinding!.toJson(),
    'placements': <String, Object?>{
      for (final e in placements.entries) e.key.name: e.value.toJson(),
    },
  };

  factory ComponentInstance.fromJson(Map<String, Object?> json) {
    final rawPlacements =
        json['placements'] as Map<String, Object?>? ??
        const <String, Object?>{};
    final placements = <DesignOrientation, Placement>{};
    for (final e in rawPlacements.entries) {
      final orientation = DesignOrientation.byName(e.key);
      if (orientation == null) continue; // unknown orientation: ignore
      placements[orientation] = Placement.fromJson(
        (e.value as Map).cast<String, Object?>(),
      );
    }
    return ComponentInstance(
      id: json['id'] as String? ?? '',
      typeId: json['typeId'] as String? ?? '',
      params:
          (json['params'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{},
      moduleId: json['moduleId'] as String? ?? kMainVfdModuleId,
      variant: json['variant'] is Map
          ? VariantReference.fromJson(
              (json['variant'] as Map).cast<String, Object?>(),
            )
          : null,
      opticalOverrides: OpticalOverrides.fromJson(
        (json['opticalOverrides'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
      actionBinding: json['actionBinding'] is Map
          ? ActionBinding.fromJson(
              (json['actionBinding'] as Map).cast<String, Object?>(),
            )
          : null,
      placements: placements,
    );
  }
}
