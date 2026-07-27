import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

import 'component_type.dart';

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
  });

  final Anchor anchor;
  final Offset offset;

  /// Extent in design units, width and height independent. Null means take the
  /// type's default. Instrument faces are authored, not laid out, so a design
  /// routinely needs a wide short bar or a tall narrow digit block that no
  /// uniform scale of the default could produce.
  final Size? size;

  Offset resolve(double aspect) => anchor.pointIn(aspect) + offset;

  Size resolveSize(ComponentTypeSpec? type) =>
      size ?? type?.defaultSize ?? const Size(1, 1);

  Placement copyWith({Anchor? anchor, Offset? offset, Size? size}) => Placement(
        anchor: anchor ?? this.anchor,
        offset: offset ?? this.offset,
        size: size ?? this.size,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'anchor': anchor.name,
        'dx': offset.dx,
        'dy': offset.dy,
        if (size != null) 'w': size!.width,
        if (size != null) 'h': size!.height,
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
    );
  }
}
