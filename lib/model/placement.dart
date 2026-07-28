import 'dart:ui' show Offset, Size;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'component_type.dart';
import 'variant.dart';

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

@immutable
class FrameSpec {
  const FrameSpec({required this.referenceAspect});

  final double referenceAspect;

  FrameSpec copyWith({double? referenceAspect}) =>
      FrameSpec(referenceAspect: referenceAspect ?? this.referenceAspect);

  Map<String, Object?> toJson() => <String, Object?>{
    'referenceAspect': referenceAspect,
  };

  factory FrameSpec.fromJson(
    Map<String, Object?> json, {
    required double fallbackAspect,
  }) {
    final rawAspect = (json['referenceAspect'] as num?)?.toDouble();
    return FrameSpec(
      referenceAspect: rawAspect != null && rawAspect.isFinite && rawAspect > 0
          ? rawAspect
          : fallbackAspect,
    );
  }
}

/// Development defaults for payloads written before frame aspects were stored.
///
/// New designs explicitly author their primary and any optional alternate.
/// Tolerant defaults keep malformed/imported payloads usable.
const Map<DesignOrientation, double> kDefaultFrameAspects =
    <DesignOrientation, double>{
      DesignOrientation.portrait: 1 / 2.6,
      DesignOrientation.landscape: 2.6,
    };

Map<DesignOrientation, FrameSpec> normaliseFrameSpecs(
  DesignOrientation primary, {
  Map<DesignOrientation, FrameSpec>? specs,
  Map<DesignOrientation, double>? legacyAspects,
}) {
  final resolved = <DesignOrientation, FrameSpec>{
    for (final entry in (specs ?? const {}).entries)
      if (entry.value.referenceAspect.isFinite &&
          entry.value.referenceAspect > 0)
        entry.key: entry.value,
  };
  for (final entry in (legacyAspects ?? const {}).entries) {
    if (resolved.containsKey(entry.key) ||
        !entry.value.isFinite ||
        entry.value <= 0) {
      continue;
    }
    resolved[entry.key] = FrameSpec(referenceAspect: entry.value);
  }
  resolved.putIfAbsent(
    primary,
    () => FrameSpec(referenceAspect: kDefaultFrameAspects[primary]!),
  );
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
      fallbackAspect: kDefaultFrameAspects[orientation]!,
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
/// one unit tall. A frame of aspect `a` therefore spans x in [-a/2, a/2] and y
/// in [-0.5, 0.5].
enum Anchor {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight;

  static Anchor? byName(String name) {
    for (final a in Anchor.values) {
      if (a.name == name) return a;
    }
    return null;
  }

  /// The anchor's position in design units for a frame of [aspect].
  Offset pointIn(double aspect) {
    final half = aspect / 2;
    final dx = switch (this) {
      Anchor.topLeft || Anchor.centerLeft || Anchor.bottomLeft => -half,
      Anchor.topCenter || Anchor.center || Anchor.bottomCenter => 0.0,
      Anchor.topRight || Anchor.centerRight || Anchor.bottomRight => half,
    };
    final dy = switch (this) {
      Anchor.topLeft || Anchor.topCenter || Anchor.topRight => 0.5,
      Anchor.centerLeft || Anchor.center || Anchor.centerRight => 0.0,
      Anchor.bottomLeft || Anchor.bottomCenter || Anchor.bottomRight => -0.5,
    };
    return Offset(dx, dy);
  }
}

@immutable
class AxisSpan {
  const AxisSpan({this.startInset = 0, this.endInset = 0});

  final double startInset;
  final double endInset;

  Map<String, Object?> toJson() => <String, Object?>{
    'start': startInset,
    'end': endInset,
  };

  factory AxisSpan.fromJson(Map<String, Object?> json) => AxisSpan(
    startInset: (json['start'] as num?)?.toDouble() ?? 0,
    endInset: (json['end'] as num?)?.toDouble() ?? 0,
  );
}

/// Bakes a contained source-layout placement into a new fixed-aspect layout.
///
/// The resulting component occupies the same visual position it had while the
/// whole source frame was contain-fitted into the target frame. Span axes are
/// intentionally resolved to fixed extents: the new layout is now independently
/// authored.
Placement bakeContainedPlacement({
  required Placement placement,
  required Size resolvedSize,
  required double sourceAspect,
  required double targetAspect,
}) {
  final scale = math.min(1.0, targetAspect / sourceAspect);
  return Placement(
    offset: placement.resolve(sourceAspect) * scale,
    size: Size(resolvedSize.width * scale, resolvedSize.height * scale),
  );
}

/// Anchor plus offset, never absolute coordinates. A right-anchored component
/// stays welded to the authored frame edge when its fixed aspect is edited,
/// instead of drifting toward the middle.
@immutable
class Placement {
  const Placement({
    this.anchor = Anchor.center,
    this.offset = Offset.zero,
    this.size,
    this.horizontalSpan,
    this.verticalSpan,
  });

  final Anchor anchor;
  final Offset offset;

  /// Extent in design units, width and height independent. Null means take the
  /// type's default. Instrument faces are authored, not laid out, so a design
  /// routinely needs a wide short bar or a tall narrow digit block that no
  /// uniform scale of the default could produce.
  final Size? size;
  final AxisSpan? horizontalSpan;
  final AxisSpan? verticalSpan;

  Offset resolve(double aspect) {
    final fixed = anchor.pointIn(aspect) + offset;
    final horizontal = horizontalSpan;
    final vertical = verticalSpan;
    final dx = horizontal == null
        ? fixed.dx
        : (-aspect / 2 +
                  horizontal.startInset +
                  aspect / 2 -
                  horizontal.endInset) /
              2;
    final dy = vertical == null
        ? fixed.dy
        : (0.5 - vertical.startInset - 0.5 + vertical.endInset) / 2;
    return Offset(dx, dy);
  }

  Size resolveSize(ComponentTypeSpec? type, {VariantReference? variant}) =>
      size ??
      (type == null
          ? const Size(1, 1)
          : type.variant(variant ?? type.legacyVariant)?.recommendedSize ??
                type.defaultSize);

  Size resolveSizeForAspect(
    double aspect,
    ComponentTypeSpec? type, {
    VariantReference? variant,
  }) {
    final fixed = resolveSize(type, variant: variant);
    return Size(
      horizontalSpan == null
          ? fixed.width
          : (aspect - horizontalSpan!.startInset - horizontalSpan!.endInset)
                .clamp(0.03, double.infinity),
      verticalSpan == null
          ? fixed.height
          : (1 - verticalSpan!.startInset - verticalSpan!.endInset).clamp(
              0.03,
              double.infinity,
            ),
    );
  }

  Placement copyWith({Anchor? anchor, Offset? offset, Size? size}) => Placement(
    anchor: anchor ?? this.anchor,
    offset: offset ?? this.offset,
    size: size ?? this.size,
    horizontalSpan: horizontalSpan,
    verticalSpan: verticalSpan,
  );

  Placement withHorizontalSpan(AxisSpan? value) => Placement(
    anchor: anchor,
    offset: offset,
    size: size,
    horizontalSpan: value,
    verticalSpan: verticalSpan,
  );

  Placement withVerticalSpan(AxisSpan? value) => Placement(
    anchor: anchor,
    offset: offset,
    size: size,
    horizontalSpan: horizontalSpan,
    verticalSpan: value,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'anchor': anchor.name,
    'dx': offset.dx,
    'dy': offset.dy,
    if (size != null) 'w': size!.width,
    if (size != null) 'h': size!.height,
    if (horizontalSpan != null) 'horizontalSpan': horizontalSpan!.toJson(),
    if (verticalSpan != null) 'verticalSpan': verticalSpan!.toJson(),
  };

  factory Placement.fromJson(Map<String, Object?> json) {
    final w = (json['w'] as num?)?.toDouble();
    final h = (json['h'] as num?)?.toDouble();
    return Placement(
      anchor: Anchor.byName(json['anchor'] as String? ?? '') ?? Anchor.center,
      offset: Offset(
        (json['dx'] as num?)?.toDouble() ?? 0,
        (json['dy'] as num?)?.toDouble() ?? 0,
      ),
      size: (w == null || h == null) ? null : Size(w, h),
      horizontalSpan: json['horizontalSpan'] is Map
          ? AxisSpan.fromJson(
              (json['horizontalSpan'] as Map).cast<String, Object?>(),
            )
          : null,
      verticalSpan: json['verticalSpan'] is Map
          ? AxisSpan.fromJson(
              (json['verticalSpan'] as Map).cast<String, Object?>(),
            )
          : null,
    );
  }
}
