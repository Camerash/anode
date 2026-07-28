import 'package:anode/editor/placement_transform.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('30 px at 300 px scale adds 0.1 width and keeps left edge fixed', () {
    const placement = Placement(size: Size(0.5, 0.2));
    final beforeCenter = placement.resolve(2.6);
    final beforeLeft = beforeCenter.dx - placement.size!.width / 2;
    final resized = resizePlacementFromEdges(
      placement: placement,
      resolvedSize: placement.size!,
      frameAspect: 2.6,
      widthDelta: 30 / 300,
    );
    final afterCenter = resized.resolve(2.6);

    expect(resized.size!.width, closeTo(0.6, 1e-9));
    expect(afterCenter.dx - resized.size!.width / 2, closeTo(beforeLeft, 1e-9));
  });

  test('bottom resize keeps top edge fixed', () {
    const placement = Placement(
      anchor: Anchor.topRight,
      offset: Offset(-0.2, -0.1),
      size: Size(0.5, 0.2),
    );
    final beforeCenter = placement.resolve(2.6);
    final beforeTop = beforeCenter.dy + placement.size!.height / 2;
    final resized = resizePlacementFromEdges(
      placement: placement,
      resolvedSize: placement.size!,
      frameAspect: 2.6,
      heightDelta: 0.1,
    );
    final afterCenter = resized.resolve(2.6);

    expect(resized.size!.height, closeTo(0.3, 1e-9));
    expect(afterCenter.dy + resized.size!.height / 2, closeTo(beforeTop, 1e-9));
  });

  test('combined resize and minimum clamp preserve opposite edges', () {
    const placement = Placement(
      offset: Offset(0.2, -0.1),
      size: Size(0.04, 0.04),
    );
    final before = placement.resolve(1);
    final left = before.dx - 0.02;
    final top = before.dy + 0.02;
    final resized = resizePlacementFromEdges(
      placement: placement,
      resolvedSize: placement.size!,
      frameAspect: 1,
      widthDelta: -1,
      heightDelta: -1,
    );
    final after = resized.resolve(1);

    expect(resized.size, const Size(0.03, 0.03));
    expect(after.dx - 0.015, closeTo(left, 1e-9));
    expect(after.dy + 0.015, closeTo(top, 1e-9));
  });

  test('nudge changes only requested axes', () {
    const placement = Placement(offset: Offset(0.1, 0.2));
    final x = nudgePlacement(placement, dx: 0.005).offset;
    final y = nudgePlacement(placement, dy: -0.005).offset;
    expect(x.dx, closeTo(0.105, 1e-12));
    expect(x.dy, 0.2);
    expect(y.dx, 0.1);
    expect(y.dy, closeTo(0.195, 1e-12));
  });

  test('mixed span resize still updates fixed axis', () {
    const placement = Placement(
      size: Size(0.5, 0.2),
      horizontalSpan: AxisSpan(startInset: 0.2, endInset: 0.3),
    );
    final resolved = placement.resolveSizeForAspect(2.6, null);
    final beforeTop = placement.resolve(2.6).dy + resolved.height / 2;
    final resized = resizePlacementFromEdges(
      placement: placement,
      resolvedSize: resolved,
      frameAspect: 2.6,
      widthDelta: 0.1,
      heightDelta: 0.1,
    );
    final afterSize = resized.resolveSizeForAspect(2.6, null);

    expect(resized.horizontalSpan?.startInset, 0.2);
    expect(resized.horizontalSpan?.endInset, closeTo(0.2, 1e-9));
    expect(afterSize.width, closeTo(resolved.width + 0.1, 1e-9));
    expect(afterSize.height, closeTo(0.3, 1e-9));
    expect(
      resized.resolve(2.6).dy + afterSize.height / 2,
      closeTo(beforeTop, 1e-9),
    );
  });
}
