import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'placement.dart';

enum ViewportOrientation {
  portrait,
  landscape;

  static ViewportOrientation fromSize(Size size) =>
      size.width >= size.height ? landscape : portrait;
}

enum ScreenBehavior { adapt, lock }

@immutable
class ScreenSetup {
  const ScreenSetup.adapt()
    : behavior = ScreenBehavior.adapt,
      lockedLayoutId = null,
      lockedOrientation = null;

  const ScreenSetup.lock({
    required String layoutId,
    required ViewportOrientation orientation,
  }) : behavior = ScreenBehavior.lock,
       lockedLayoutId = layoutId,
       lockedOrientation = orientation;

  final ScreenBehavior behavior;
  final String? lockedLayoutId;
  final ViewportOrientation? lockedOrientation;

  Map<String, Object?> toJson() => <String, Object?>{
    'behavior': behavior.name,
    if (lockedLayoutId != null) 'lockedLayoutId': lockedLayoutId,
    if (lockedOrientation != null) 'lockedOrientation': lockedOrientation!.name,
  };

  factory ScreenSetup.fromJson(Object? raw) {
    if (raw is! Map) return const ScreenSetup.adapt();
    final json = raw.cast<String, Object?>();
    if (json['behavior'] != ScreenBehavior.lock.name) {
      return const ScreenSetup.adapt();
    }
    final layoutId = json['lockedLayoutId'] as String?;
    final orientationName = json['lockedOrientation'] as String?;
    final orientation = ViewportOrientation.values
        .where((value) => value.name == orientationName)
        .firstOrNull;
    if (layoutId == null || layoutId.isEmpty || orientation == null) {
      return const ScreenSetup.adapt();
    }
    return ScreenSetup.lock(layoutId: layoutId, orientation: orientation);
  }
}

@immutable
class DesignLayout {
  const DesignLayout({required this.id, required this.frame});

  final String id;
  final FrameSpec frame;

  double get aspect => frame.referenceAspect;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'frame': frame.toJson(),
  };

  factory DesignLayout.fromJson(Map<String, Object?> json) => DesignLayout(
    id: json['id'] as String? ?? '',
    frame: FrameSpec.fromJson(
      (json['frame'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{},
      fallback: const FrameSpec.aspect(16 / 9),
    ),
  );
}

List<DesignLayout> normaliseDesignLayouts(Iterable<DesignLayout> raw) {
  final layouts = <DesignLayout>[];
  final ids = <String>{};
  for (final layout in raw) {
    if (layout.id.isEmpty || !layout.frame.isValid || !ids.add(layout.id)) {
      continue;
    }
    layouts.add(layout);
  }
  if (layouts.isEmpty) {
    throw ArgumentError.value(
      raw,
      'layouts',
      'At least one layout is required',
    );
  }
  return List<DesignLayout>.unmodifiable(layouts);
}

DesignLayout designLayoutById(
  List<DesignLayout> layouts,
  String id, {
  required String fallbackId,
}) => layouts.firstWhere(
  (layout) => layout.id == id,
  orElse: () => layouts.firstWhere((layout) => layout.id == fallbackId),
);

String nearestLayoutId(
  List<DesignLayout> layouts,
  Size viewport, {
  required String fallbackId,
}) {
  if (viewport.width <= 0 || viewport.height <= 0) return fallbackId;
  final target = viewport.width / viewport.height;
  var best = designLayoutById(layouts, fallbackId, fallbackId: fallbackId);
  var bestDistance = (math.log(best.aspect / target)).abs();
  for (final layout in layouts) {
    final distance = (math.log(layout.aspect / target)).abs();
    if (distance < bestDistance) {
      best = layout;
      bestDistance = distance;
    }
  }
  return best.id;
}

/// Creates a target frame that contains [source] without changing design-unit
/// scale. The new boundary grows on one axis; authored geometry stays fixed.
FrameSpec containingFrameForAspect(FrameSpec source, double targetAspect) {
  if (!targetAspect.isFinite || targetAspect <= 0) return source;
  if (targetAspect >= source.referenceAspect) {
    return FrameSpec(
      width: source.height * targetAspect,
      height: source.height,
    );
  }
  return FrameSpec(width: source.width, height: source.width / targetAspect);
}

String layoutShapeLabel(double aspect) {
  if (aspect > 1.05) return 'Wide';
  if (aspect < 0.95) return 'Tall';
  return 'Square';
}

String formatLayoutRatio(double aspect) {
  if (aspect >= 1) return '${aspect.toStringAsFixed(3)}:1';
  return '1:${(1 / aspect).toStringAsFixed(3)}';
}
