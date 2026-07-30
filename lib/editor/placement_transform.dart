import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/placement.dart';

const double minimumAuthoredSize = 0.03;
const double editorSnapStep = 0.5;
const double editorFineStep = 0.005;

double snapDesignDelta(double value, double? step) {
  if (step == null || step <= 0) return value;
  return (value / step).round() * step;
}

Placement movePlacementBy(
  Placement placement, {
  double dx = 0,
  double dy = 0,
  double? snapStep,
}) => placement.copyWith(
  center:
      placement.center +
      Offset(snapDesignDelta(dx, snapStep), snapDesignDelta(dy, snapStep)),
);

/// Resizes from right and/or bottom edges. Opposite edges remain invariant,
/// including after minimum-size clamping.
Placement resizePlacementFromEdges({
  required Placement placement,
  double widthDelta = 0,
  double heightDelta = 0,
  double minimumSize = minimumAuthoredSize,
  double? snapStep,
}) {
  final snappedWidthDelta = snapDesignDelta(widthDelta, snapStep);
  final snappedHeightDelta = snapDesignDelta(heightDelta, snapStep);
  final nextWidth = math.max(
    minimumSize,
    placement.size.width + snappedWidthDelta,
  );
  final nextHeight = math.max(
    minimumSize,
    placement.size.height + snappedHeightDelta,
  );
  final appliedWidth = nextWidth - placement.size.width;
  final appliedHeight = nextHeight - placement.size.height;
  return placement.copyWith(
    center: placement.center + Offset(appliedWidth / 2, -appliedHeight / 2),
    size: Size(nextWidth, nextHeight),
  );
}

Placement nudgePlacement(Placement placement, {double dx = 0, double dy = 0}) {
  return placement.copyWith(center: placement.center + Offset(dx, dy));
}

/// Recovers an off-frame item without changing its size. Oversized axes centre
/// because no centre can place that axis wholly inside the authored frame.
Placement bringPlacementIntoFrame(Placement placement, Size frame) {
  double containedCenter(double center, double itemExtent, double frameExtent) {
    final travel = (frameExtent - itemExtent) / 2;
    if (travel <= 0) return 0;
    return center.clamp(-travel, travel);
  }

  return placement.copyWith(
    center: Offset(
      containedCenter(placement.center.dx, placement.size.width, frame.width),
      containedCenter(placement.center.dy, placement.size.height, frame.height),
    ),
  );
}
