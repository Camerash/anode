import 'package:flutter/foundation.dart';

enum ParamType { boolean, integer, number, option, text }

/// Declares one tunable on a component type.
///
/// [min] and [max] are not cosmetic. They are the ranges the editor builds its
/// controls from, and the quantisation ranges the renderer needs if component
/// parameters have to be packed as fixed point rather than floats.
@immutable
class ParamSpec {
  const ParamSpec({
    required this.key,
    required this.label,
    required this.type,
    required this.defaultValue,
    this.min,
    this.max,
    this.options = const <String>[],
  });

  final String key;
  final String label;
  final ParamType type;
  final Object? defaultValue;
  final double? min;
  final double? max;
  final List<String> options;

  /// Forces [raw] into something this spec allows, falling back to
  /// [defaultValue] rather than throwing. Stored dashboards outlive the code
  /// that wrote them; a bad value must not brick a layout.
  Object? coerce(Object? raw) {
    switch (type) {
      case ParamType.boolean:
        return raw is bool ? raw : defaultValue;
      case ParamType.integer:
        final n = raw is num ? raw.round() : null;
        if (n == null) return defaultValue;
        return _clamp(n.toDouble()).round();
      case ParamType.number:
        final n = raw is num ? raw.toDouble() : null;
        if (n == null) return defaultValue;
        return _clamp(n);
      case ParamType.option:
        return raw is String && options.contains(raw) ? raw : defaultValue;
      case ParamType.text:
        return raw is String ? raw : defaultValue;
    }
  }

  double _clamp(double v) {
    var out = v;
    if (min != null && out < min!) out = min!;
    if (max != null && out > max!) out = max!;
    return out;
  }
}
