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
  final viewport = (deviceSafe.height >= deviceSafe.width) ==
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
/// measured in the frame-independent design units described on [FrameSpec]. A
/// frame of extent `(w, h)` therefore spans x in [-w/2, w/2] and y in
/// [-h/2, h/2].
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

  /// The anchor's position in design units for a frame of extent [frame].
  Offset pointIn(Size frame) {
    final halfWidth = frame.width / 2;
    final halfHeight = frame.height / 2;
    final dx = switch (this) {
      Anchor.topLeft || Anchor.centerLeft || Anchor.bottomLeft => -halfWidth,
      Anchor.topCenter || Anchor.center || Anchor.bottomCenter => 0.0,
      Anchor.topRight || Anchor.centerRight || Anchor.bottomRight => halfWidth,
    };
    final dy = switch (this) {
      Anchor.topLeft || Anchor.topCenter || Anchor.topRight => halfHeight,
      Anchor.centerLeft || Anchor.center || Anchor.centerRight => 0.0,
      Anchor.bottomLeft ||
      Anchor.bottomCenter ||
      Anchor.bottomRight => -halfHeight,
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

/// Bakes a source-layout placement into a newly created alternate layout.
///
/// Geometry is copied verbatim. The target frame is sized by
/// [viewportFrameExtent] so that it renders at the fit scale the design already
/// had, which is what makes creating an alternate produce no visual jump — in
/// the geometry OR in the optical layer, since a design unit means the same
/// thing in both frames.
///
/// Span axes are deliberately frozen to fixed extents. A `verticalSpan` copied
/// verbatim would resolve against the taller new envelope and stretch to fill
/// it, which is exactly the jump this is here to avoid.
Placement bakeContainedPlacement({
  required Placement placement,
  required Size resolvedSize,
  required Size sourceFrame,
  required Size targetFrame,
}) {
  final centre = placement.resolve(sourceFrame);
  return Placement(
    anchor: placement.anchor,
    offset: centre - placement.anchor.pointIn(targetFrame),
    size: resolvedSize,
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

  Offset resolve(Size frame) {
    final fixed = anchor.pointIn(frame) + offset;
    final horizontal = horizontalSpan;
    final vertical = verticalSpan;
    final halfWidth = frame.width / 2;
    final halfHeight = frame.height / 2;
    final dx = horizontal == null
        ? fixed.dx
        : (-halfWidth +
                  horizontal.startInset +
                  halfWidth -
                  horizontal.endInset) /
              2;
    final dy = vertical == null
        ? fixed.dy
        : (halfHeight - vertical.startInset - halfHeight + vertical.endInset) /
              2;
    return Offset(dx, dy);
  }

  Size resolveSize(ComponentTypeSpec? type, {VariantReference? variant}) =>
      size ??
      (type == null
          ? const Size(1, 1)
          : type.variant(variant ?? type.legacyVariant)?.recommendedSize ??
                type.defaultSize);

  Size resolveSizeIn(
    Size frame,
    ComponentTypeSpec? type, {
    VariantReference? variant,
  }) {
    final fixed = resolveSize(type, variant: variant);
    return Size(
      horizontalSpan == null
          ? fixed.width
          : (frame.width -
                    horizontalSpan!.startInset -
                    horizontalSpan!.endInset)
                .clamp(0.03, double.infinity),
      verticalSpan == null
          ? fixed.height
          : (frame.height - verticalSpan!.startInset - verticalSpan!.endInset)
                .clamp(0.03, double.infinity),
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
