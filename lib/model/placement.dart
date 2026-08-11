import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

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

  Map<String, Object?> toJson() => <String, Object?>{
    'width': width,
    'height': height,
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
    return fallback;
  }
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
