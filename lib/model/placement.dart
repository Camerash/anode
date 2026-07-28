import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

import 'component_type.dart';
import 'variant.dart';

/// Layouts are authored per orientation, never reflowed from one another.
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

double orientViewportAspect(
  double viewportAspect,
  DesignOrientation orientation,
) {
  if (!viewportAspect.isFinite || viewportAspect <= 0) {
    return kDefaultFrameAspects[orientation]!;
  }
  return switch (orientation) {
    DesignOrientation.portrait =>
      viewportAspect <= 1 ? viewportAspect : 1 / viewportAspect,
    DesignOrientation.landscape =>
      viewportAspect >= 1 ? viewportAspect : 1 / viewportAspect,
  };
}

enum FrameAspectMode {
  fixed,
  adaptive;

  static FrameAspectMode? byName(String name) {
    for (final mode in values) {
      if (mode.name == name) return mode;
    }
    return null;
  }
}

@immutable
class FrameSpec {
  const FrameSpec({
    required this.referenceAspect,
    this.mode = FrameAspectMode.fixed,
  });

  final double referenceAspect;
  final FrameAspectMode mode;

  double resolve({double? viewportAspect}) {
    if (mode == FrameAspectMode.adaptive &&
        viewportAspect != null &&
        viewportAspect.isFinite &&
        viewportAspect > 0) {
      return viewportAspect;
    }
    return referenceAspect;
  }

  FrameSpec copyWith({double? referenceAspect, FrameAspectMode? mode}) =>
      FrameSpec(
        referenceAspect: referenceAspect ?? this.referenceAspect,
        mode: mode ?? this.mode,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
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
      mode:
          FrameAspectMode.byName(json['mode'] as String? ?? '') ??
          FrameAspectMode.fixed,
    );
  }
}

/// Development defaults for payloads written before frame aspects were stored.
///
/// New designs author both values explicitly. Keeping tolerant defaults lets
/// existing dashboards survive the additive schema change.
const Map<DesignOrientation, double> kDefaultFrameAspects =
    <DesignOrientation, double>{
      DesignOrientation.portrait: 1 / 2.6,
      DesignOrientation.landscape: 2.6,
    };

Map<DesignOrientation, FrameSpec> normaliseFrameSpecs(
  Set<DesignOrientation> supported, {
  Map<DesignOrientation, FrameSpec>? specs,
  Map<DesignOrientation, double>? legacyAspects,
}) => Map<DesignOrientation, FrameSpec>.unmodifiable(<
  DesignOrientation,
  FrameSpec
>{
  for (final orientation in supported)
    orientation:
        specs?[orientation] ??
        FrameSpec(
          referenceAspect:
              legacyAspects?[orientation] ?? kDefaultFrameAspects[orientation]!,
        ),
});

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

Map<DesignOrientation, double> normaliseFrameAspects(
  Set<DesignOrientation> supported,
  Map<DesignOrientation, double>? raw,
) => Map<DesignOrientation, double>.unmodifiable(<DesignOrientation, double>{
  for (final orientation in supported)
    orientation: switch (raw?[orientation]) {
      final value? when value.isFinite && value > 0 => value,
      _ => kDefaultFrameAspects[orientation]!,
    },
});

Map<String, Object?> frameAspectsToJson(
  Map<DesignOrientation, double> aspects,
) => <String, Object?>{
  for (final entry in aspects.entries) entry.key.name: entry.value,
};

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

/// Anchor plus offset, never absolute coordinates. This is what absorbs the
/// aspect spread from 18:9 through 4:3 within one authored orientation: a
/// right-anchored component stays welded to the right edge as the frame widens,
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
