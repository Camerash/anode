import 'dart:ui' show Size;

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
/// A missing placement for a layout means the component does not exist there.
@immutable
class ComponentInstance {
  ComponentInstance({
    required this.id,
    required this.typeId,
    Map<String, Object?> params = const <String, Object?>{},
    Map<String, Placement> placements = const <String, Placement>{},
    this.moduleId = kMainVfdModuleId,
    this.variant,
    OpticalOverrides? opticalOverrides,
    this.actionBinding,
  }) : params = Map<String, Object?>.unmodifiable(params),
       placements = Map<String, Placement>.unmodifiable(placements),
       opticalOverrides = opticalOverrides ?? OpticalOverrides();

  final String id;
  final String typeId;
  final Map<String, Object?> params;
  final Map<String, Placement> placements;
  final String moduleId;
  final VariantReference? variant;
  final OpticalOverrides opticalOverrides;
  final ActionBinding? actionBinding;

  ComponentTypeSpec? get type => ComponentTypes.byId(typeId);
  VariantReference get effectiveVariant =>
      variant ?? type?.legacyVariant ?? const VariantReference(id: 'legacy');

  bool appearsIn(String layoutId) => placements.containsKey(layoutId);

  /// Params with defaults filled in and known values coerced. Falls back to the
  /// stored map for a type the registry does not know.
  Map<String, Object?> get effectiveParams =>
      type?.normalise(params, variant: effectiveVariant) ??
      Map<String, Object?>.from(params);

  ComponentInstance copyWith({
    String? id,
    String? typeId,
    Map<String, Object?>? params,
    Map<String, Placement>? placements,
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

  ComponentInstance withPlacement(String layoutId, Placement? placement) {
    final next = <String, Placement>{...placements};
    if (placement == null) {
      next.remove(layoutId);
    } else {
      next[layoutId] = placement;
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
      for (final e in placements.entries) e.key: e.value.toJson(),
    },
  };

  factory ComponentInstance.fromJson(Map<String, Object?> json) {
    final typeId = json['typeId'] as String? ?? '';
    final variant = json['variant'] is Map
        ? VariantReference.fromJson(
            (json['variant'] as Map).cast<String, Object?>(),
          )
        : null;
    final type = ComponentTypes.byId(typeId);
    final fallbackSize =
        type?.variant(variant ?? type.legacyVariant)?.recommendedSize ??
        type?.defaultSize ??
        const Size(1, 1);
    final rawPlacements =
        json['placements'] as Map<String, Object?>? ??
        const <String, Object?>{};
    final placements = <String, Placement>{};
    for (final e in rawPlacements.entries) {
      if (e.key.isEmpty || e.value is! Map) continue;
      placements[e.key] = Placement.fromJson(
        (e.value as Map).cast<String, Object?>(),
        fallbackSize: fallbackSize,
      );
    }
    return ComponentInstance(
      id: json['id'] as String? ?? '',
      typeId: typeId,
      params:
          (json['params'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{},
      moduleId: json['moduleId'] as String? ?? kMainVfdModuleId,
      variant: variant,
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
