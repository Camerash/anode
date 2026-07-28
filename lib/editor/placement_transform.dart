import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/placement.dart';

const double minimumAuthoredSize = 0.03;

/// Resizes from right and/or bottom edges. Opposite edges remain invariant,
/// including after minimum-size clamping.
Placement resizePlacementFromEdges({
  required Placement placement,
  required Size resolvedSize,
  required double frameAspect,
  double widthDelta = 0,
  double heightDelta = 0,
  double minimumSize = minimumAuthoredSize,
}) {
  final nextWidth = math.max(minimumSize, resolvedSize.width + widthDelta);
  final nextHeight = math.max(minimumSize, resolvedSize.height + heightDelta);
  final appliedWidth = nextWidth - resolvedSize.width;
  final appliedHeight = nextHeight - resolvedSize.height;
  final center = placement.resolve(frameAspect);
  final nextCenter = center + Offset(appliedWidth / 2, -appliedHeight / 2);
  return placement.copyWith(
    offset: nextCenter - placement.anchor.pointIn(frameAspect),
    size: Size(nextWidth, nextHeight),
  );
}

Placement nudgePlacement(Placement placement, {double dx = 0, double dy = 0}) =>
    placement.copyWith(offset: placement.offset + Offset(dx, dy));

Placement setResolvedPlacementAxis({
  required Placement placement,
  required double frameAspect,
  double? centerX,
  double? centerY,
  double? width,
  double? height,
  required Size resolvedSize,
}) {
  final center = placement.resolve(frameAspect);
  final nextCenter = Offset(centerX ?? center.dx, centerY ?? center.dy);
  return placement.copyWith(
    offset: nextCenter - placement.anchor.pointIn(frameAspect),
    size: Size(width ?? resolvedSize.width, height ?? resolvedSize.height),
  );
}
