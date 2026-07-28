import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'param_spec.dart';

@immutable
class VariantReference {
  const VariantReference({required this.id, this.revision = 1});

  final String id;
  final int revision;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'revision': revision,
  };

  factory VariantReference.fromJson(Map<String, Object?> json) =>
      VariantReference(
        id: json['id'] as String? ?? 'legacy',
        revision: (json['revision'] as num?)?.toInt() ?? 1,
      );

  @override
  bool operator ==(Object other) =>
      other is VariantReference && other.id == id && other.revision == revision;

  @override
  int get hashCode => Object.hash(id, revision);
}

@immutable
class ComponentVariantSpec {
  const ComponentVariantSpec({
    required this.reference,
    required this.displayName,
    required this.recommendedSize,
    this.params = const <ParamSpec>[],
    this.deprecated = false,
    this.rendererCode = 0,
  });

  final VariantReference reference;
  final String displayName;
  final Size recommendedSize;
  final List<ParamSpec> params;
  final bool deprecated;

  /// Runtime-only packing code. Never persist this value.
  final int rendererCode;
}
