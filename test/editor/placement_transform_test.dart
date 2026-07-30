import 'package:anode/editor/placement_transform.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('30 px at 300 px scale adds 0.1 width and keeps left edge fixed', () {
    const placement = Placement(center: Offset.zero, size: Size(0.5, 0.2));
    final beforeLeft = placement.center.dx - placement.size.width / 2;
    final resized = resizePlacementFromEdges(
      placement: placement,
      widthDelta: 30 / 300,
    );

    expect(resized.size.width, closeTo(0.6, 1e-9));
    expect(
      resized.center.dx - resized.size.width / 2,
      closeTo(beforeLeft, 1e-9),
    );
  });

  test('bottom resize keeps top edge fixed', () {
    const placement = Placement(
      center: Offset(0.6, -0.1),
      size: Size(0.5, 0.2),
    );
    final beforeTop = placement.center.dy + placement.size.height / 2;
    final resized = resizePlacementFromEdges(
      placement: placement,
      heightDelta: 0.1,
    );

    expect(resized.size.height, closeTo(0.3, 1e-9));
    expect(
      resized.center.dy + resized.size.height / 2,
      closeTo(beforeTop, 1e-9),
    );
  });

  test('combined resize and minimum clamp preserve opposite edges', () {
    const placement = Placement(
      center: Offset(0.2, -0.1),
      size: Size(0.04, 0.04),
    );
    final left = placement.center.dx - 0.02;
    final top = placement.center.dy + 0.02;
    final resized = resizePlacementFromEdges(
      placement: placement,
      widthDelta: -1,
      heightDelta: -1,
    );

    expect(resized.size, const Size(0.03, 0.03));
    expect(resized.center.dx - 0.015, closeTo(left, 1e-9));
    expect(resized.center.dy + 0.015, closeTo(top, 1e-9));
  });

  test('nudge changes only requested axes', () {
    const placement = Placement(center: Offset(0.1, 0.2), size: Size(0.5, 0.2));
    final x = nudgePlacement(placement, dx: editorFineStep).center;
    final y = nudgePlacement(placement, dy: -editorFineStep).center;
    expect(x.dx, closeTo(0.105, 1e-12));
    expect(x.dy, 0.2);
    expect(y.dx, 0.1);
    expect(y.dy, closeTo(0.195, 1e-12));
  });

  test('one drag detent contains twenty fine-control steps', () {
    expect(editorSnapStep, editorFineStep * 20);
  });

  test('continuous movement preserves exact deltas', () {
    const placement = Placement(
      center: Offset(0.103, -0.207),
      size: Size(0.503, 0.203),
    );
    final moved = movePlacementBy(placement, dx: 0.0072, dy: -0.0031);

    expect(moved.center.dx, closeTo(0.1102, 1e-12));
    expect(moved.center.dy, closeTo(-0.2101, 1e-12));
  });

  test('snap quantizes delta relative to off-grid pointer-down geometry', () {
    const placement = Placement(
      center: Offset(0.103, -0.207),
      size: Size(0.503, 0.203),
    );
    final moved = movePlacementBy(
      placement,
      dx: 0.061,
      dy: -0.051,
      snapStep: editorSnapStep,
    );
    final resized = resizePlacementFromEdges(
      placement: placement,
      widthDelta: 0.061,
      heightDelta: 0.051,
      snapStep: editorSnapStep,
    );

    expect(moved.center.dx, closeTo(0.203, 1e-12));
    expect(moved.center.dy, closeTo(-0.307, 1e-12));
    expect(resized.size.width, closeTo(0.603, 1e-12));
    expect(resized.size.height, closeTo(0.303, 1e-12));
    expect(
      resized.center.dx - resized.size.width / 2,
      closeTo(placement.center.dx - placement.size.width / 2, 1e-12),
    );
    expect(
      resized.center.dy + resized.size.height / 2,
      closeTo(placement.center.dy + placement.size.height / 2, 1e-12),
    );
  });

  test('bring in contains each recoverable axis without resizing', () {
    const placement = Placement(center: Offset(-2, 0.8), size: Size(0.5, 0.2));
    final recovered = bringPlacementIntoFrame(placement, const Size(2.6, 1));

    expect(recovered.center, const Offset(-1.05, 0.4));
    expect(recovered.size, placement.size);
  });

  test('bring in centres an axis wider than its frame', () {
    const placement = Placement(center: Offset(2, -0.2), size: Size(3, 0.2));
    final recovered = bringPlacementIntoFrame(placement, const Size(2.6, 1));

    expect(recovered.center.dx, 0);
    expect(recovered.center.dy, -0.2);
  });
}
