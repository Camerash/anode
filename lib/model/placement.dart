import 'dart:ui' show Offset, Size;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A design always has one primary layout and may author one opposite-
/// orientation override.
enum DesignOrientation {
  portrait,
  landscape;

  static DesignOrientation? byName(String name) {
    for (final o in DesignOrientation.values) {
      if (o.name == name) return o;
    }
    return null;
  }
}

/// The authored extent of one physical tube face, in design units.
///
/// A design unit is frame-independent — it is a physical unit of the tube face,
/// roughly the height of the module in the reference photographs. It is NOT
/// "the height of the frame". Every optical constant in `vfd.frag` (halo
/// falloff, control-grid pitch, filament diameter, phosphor coating grain,
/// segment edge softness) is expressed in these units, so if the meaning of a
/// unit varied with the shape of the frame, changing a frame's aspect would
/// silently rescale the whole optical stack. It did, once.
@immutable
class FrameSpec {
  const FrameSpec({required this.width, required this.height});

  /// A frame one unit tall, which is what every layout authored before frames
  /// carried an explicit extent implicitly was.
  const FrameSpec.aspect(double aspect) : width = aspect, height = 1;

  final double width;
  final double height;

  double get referenceAspect => width / height;
  Size get extent => Size(width, height);

  bool get isValid =>
      width.isFinite && width > 0 && height.isFinite && height > 0;

  FrameSpec copyWith({double? width, double? height}) =>
      FrameSpec(width: width ?? this.width, height: height ?? this.height);

  /// `referenceAspect` is written as well as the extent. It is redundant for
  /// this build and lets an older one degrade to an aspect-only frame instead
  /// of falling back to a default it never authored.
  Map<String, Object?> toJson() => <String, Object?>{
    'width': width,
    'height': height,
    'referenceAspect': referenceAspect,
  };

  factory FrameSpec.fromJson(
    Map<String, Object?> json, {
    required FrameSpec fallback,
  }) {
    final width = (json['width'] as num?)?.toDouble();
    final height = (json['height'] as num?)?.toDouble();
    if (width != null && height != null) {
      final spec = FrameSpec(width: width, height: height);
      if (spec.isValid) return spec;
    }
    final aspect = (json['referenceAspect'] as num?)?.toDouble();
    if (aspect != null && aspect.isFinite && aspect > 0) {
      return FrameSpec.aspect(aspect);
    }
    return fallback;
  }
}

/// Development defaults for payloads written before frame extents were stored.
///
/// New designs explicitly author their primary and any optional alternate.
/// Tolerant defaults keep malformed/imported payloads usable, so their numbers
/// must not drift: changing one would rescale every legacy payload that fell
/// back to it.
const Map<DesignOrientation, FrameSpec> kDefaultFrameSpecs =
    <DesignOrientation, FrameSpec>{
      DesignOrientation.portrait: FrameSpec.aspect(1 / 2.6),
      DesignOrientation.landscape: FrameSpec.aspect(2.6),
    };

/// The extent an explicitly created alternate layout takes, such that the
/// design renders at exactly the fit scale it already had.
///
/// [deviceSafe] is the device's own safe rect. Its axes are swapped when
/// [target] disagrees with the device's current orientation, because the
/// viewport selector is independent of how the phone happens to be held.
///
/// Both `CREATE` and the read-only preview of an unauthored orientation call
/// this, which is what makes "no runtime visual jump" structural rather than
/// something a test has to keep honest.
Size viewportFrameExtent(
  DesignOrientation target,
  Size deviceSafe,
  FrameSpec primary,
) {
  final viewport =
      (deviceSafe.height >= deviceSafe.width) ==
          (target == DesignOrientation.portrait)
      ? deviceSafe
      : Size(deviceSafe.height, deviceSafe.width);
  final scale = math.min(
    viewport.width / primary.width,
    viewport.height / primary.height,
  );
  if (!scale.isFinite || scale <= 0) return primary.extent;
  return Size(viewport.width / scale, viewport.height / scale);
}

Map<DesignOrientation, FrameSpec> normaliseFrameSpecs(
  DesignOrientation primary, {
  Map<DesignOrientation, FrameSpec>? specs,
  Map<DesignOrientation, double>? legacyAspects,
}) {
  final resolved = <DesignOrientation, FrameSpec>{
    for (final entry in (specs ?? const {}).entries)
      if (entry.value.isValid) entry.key: entry.value,
  };
  for (final entry in (legacyAspects ?? const {}).entries) {
    if (resolved.containsKey(entry.key) ||
        !entry.value.isFinite ||
        entry.value <= 0) {
      continue;
    }
    resolved[entry.key] = FrameSpec.aspect(entry.value);
  }
  resolved.putIfAbsent(primary, () => kDefaultFrameSpecs[primary]!);
  return Map<DesignOrientation, FrameSpec>.unmodifiable(resolved);
}

Map<String, Object?> frameSpecsToJson(
  Map<DesignOrientation, FrameSpec> specs,
) => <String, Object?>{
  for (final entry in specs.entries) entry.key.name: entry.value.toJson(),
};

Map<DesignOrientation, FrameSpec> parseFrameSpecs(Object? raw) {
  final values = <DesignOrientation, FrameSpec>{};
  for (final entry
      in ((raw as Map?)?.cast<String, Object?>() ?? const {}).entries) {
    final orientation = DesignOrientation.byName(entry.key);
    if (orientation == null || entry.value is! Map) continue;
    values[orientation] = FrameSpec.fromJson(
      (entry.value as Map).cast<String, Object?>(),
      fallback: kDefaultFrameSpecs[orientation]!,
    );
  }
  return values;
}

Map<DesignOrientation, double> parseFrameAspects(Object? raw) {
  final values = <DesignOrientation, double>{};
  for (final entry
      in ((raw as Map?)?.cast<String, Object?>() ?? const {}).entries) {
    final orientation = DesignOrientation.byName(entry.key);
    final value = (entry.value as num?)?.toDouble();
    if (orientation == null || value == null) continue;
    values[orientation] = value;
  }
  return values;
}

/// Design space is the shader's space: y-up, origin at the centre of the frame,
/// measured in frame-independent design units.
///
/// Frames are fixed authored extents and runtime mismatch is handled only by
/// contain-fit. Centre and size are therefore the complete placement contract:
/// editor chrome and renderer consume these exact values.
@immutable
class Placement {
  const Placement({required this.center, required this.size});

  final Offset center;
  final Size size;

  Placement copyWith({Offset? center, Size? size}) =>
      Placement(center: center ?? this.center, size: size ?? this.size);

  Map<String, Object?> toJson() => <String, Object?>{
    'x': center.dx,
    'y': center.dy,
    'w': size.width,
    'h': size.height,
  };

  factory Placement.fromJson(
    Map<String, Object?> json, {
    Size fallbackSize = const Size(1, 1),
  }) {
    double coordinate(Object? raw) {
      final value = raw is num ? raw.toDouble() : 0.0;
      return value.isFinite ? value : 0;
    }

    double dimension(Object? raw, double fallback) {
      final value = raw is num ? raw.toDouble() : fallback;
      return value.isFinite && value > 0 ? value : fallback;
    }

    return Placement(
      center: Offset(coordinate(json['x']), coordinate(json['y'])),
      size: Size(
        dimension(json['w'], fallbackSize.width),
        dimension(json['h'], fallbackSize.height),
      ),
    );
  }
}
