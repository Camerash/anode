import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/placement.dart';

const double minimumAuthoredSize = 0.03;

/// Resizes from right and/or bottom edges. Opposite edges remain invariant,
/// including after minimum-size clamping.
Placement resizePlacementFromEdges({
  required Placement placement,
  required Size resolvedSize,
  required Size frame,
  double widthDelta = 0,
  double heightDelta = 0,
  double minimumSize = minimumAuthoredSize,
}) {
  final horizontal = placement.horizontalSpan;
  final vertical = placement.verticalSpan;
  final center = placement.resolve(frame);
  var nextCenter = center;
  var nextWidth = resolvedSize.width;
  var nextHeight = resolvedSize.height;
  AxisSpan? nextHorizontal = horizontal;
  AxisSpan? nextVertical = vertical;

  if (horizontal == null) {
    nextWidth = math.max(minimumSize, resolvedSize.width + widthDelta);
    nextCenter += Offset((nextWidth - resolvedSize.width) / 2, 0);
  } else {
    nextHorizontal = AxisSpan(
      startInset: horizontal.startInset,
      endInset: math.min(
        horizontal.endInset - widthDelta,
        frame.width - horizontal.startInset - minimumSize,
      ),
    );
  }

  if (vertical == null) {
    nextHeight = math.max(minimumSize, resolvedSize.height + heightDelta);
    nextCenter += Offset(0, -(nextHeight - resolvedSize.height) / 2);
  } else {
    nextVertical = AxisSpan(
      startInset: vertical.startInset,
      endInset: math.min(
        vertical.endInset - heightDelta,
        frame.height - vertical.startInset - minimumSize,
      ),
    );
  }

  return placement
      .copyWith(
        offset: nextCenter - placement.anchor.pointIn(frame),
        size: Size(nextWidth, nextHeight),
      )
      .withHorizontalSpan(nextHorizontal)
      .withVerticalSpan(nextVertical);
}

Placement nudgePlacement(Placement placement, {double dx = 0, double dy = 0}) {
  final horizontal = placement.horizontalSpan;
  final vertical = placement.verticalSpan;
  return placement
      .copyWith(offset: placement.offset + Offset(dx, dy))
      .withHorizontalSpan(
        horizontal == null
            ? null
            : AxisSpan(
                startInset: horizontal.startInset + dx,
                endInset: horizontal.endInset - dx,
              ),
      )
      .withVerticalSpan(
        vertical == null
            ? null
            : AxisSpan(
                startInset: vertical.startInset - dy,
                endInset: vertical.endInset + dy,
              ),
      );
}

Placement setResolvedPlacementAxis({
  required Placement placement,
  required Size frame,
  double? centerX,
  double? centerY,
  double? width,
  double? height,
  required Size resolvedSize,
}) {
  final center = placement.resolve(frame);
  final nextCenter = Offset(centerX ?? center.dx, centerY ?? center.dy);
  return placement.copyWith(
    offset: nextCenter - placement.anchor.pointIn(frame),
    size: Size(width ?? resolvedSize.width, height ?? resolvedSize.height),
  );
}
