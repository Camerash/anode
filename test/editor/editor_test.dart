import 'dart:math' as math;

import 'package:anode/editor/editor_canvas.dart';
import 'package:anode/editor/editor_page.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/dev_design.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('preview falls back to primary until alternate is authored', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1200, 900));
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          dashboard: dashboard,
          onChanged: (value) => dashboard = value,
        ),
      ),
    );

    expect(_canvasAspect(tester), closeTo(2.6, 0.001));
    await tester.tap(find.byKey(const ValueKey('orientation-portrait')));
    await tester.pump();
    // The fallback preview draws the device envelope the runtime would fill,
    // not the inherited landscape frame, so the boundary takes the portrait
    // viewport shape of a 1200x900 window turned on its side.
    expect(_canvasAspect(tester), closeTo(900 / 1200, 0.001));
  });

  testWidgets('drawer pushes canvas and selection does not open it', (
    tester,
  ) async {
    await _setViewport(tester, const Size(874, 402));
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(dashboard: dashboard, onChanged: (_) {}),
      ),
    );

    final canvasBefore = tester.getSize(
      find.byKey(const ValueKey('editor-canvas')),
    );
    final workspace = find.byKey(const ValueKey('mechanical-push-drawer'));
    final drawerClosed = tester.getTopLeft(workspace);

    await tester.tap(find.byKey(const ValueKey('canvas-speed')));
    await tester.pump();
    expect(tester.getTopLeft(workspace), drawerClosed);
    expect(
      tester.getSize(find.byKey(const ValueKey('editor-canvas'))),
      canvasBefore,
    );

    await tester.tap(find.byKey(const ValueKey('mechanical-drawer-latch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      tester.getSize(find.byKey(const ValueKey('editor-canvas'))).width,
      lessThan(canvasBefore.width),
    );
  });

  testWidgets('portrait service bay pushes upward without reshaping frame', (
    tester,
  ) async {
    await _setViewport(tester, const Size(393, 852));
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(dashboard: dashboard, onChanged: (_) {}),
      ),
    );

    expect(find.text('INHERITED · READ ONLY'), findsOneWidget);
    final frame = find.byKey(const ValueKey('editor-canvas'));
    final before = tester.getCenter(frame);
    await tester.tap(find.byKey(const ValueKey('mechanical-drawer-latch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final after = tester.getCenter(frame);

    expect(after.dy, lessThan(before.dy));
    expect(_canvasAspect(tester), closeTo(393 / 852, 0.002));
  });

  testWidgets('drag and edge resize update displayed orientation only', (
    tester,
  ) async {
    await _setViewport(tester, const Size(900, 500));
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 828,
            height: 348,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return EditorCanvas(
                  dashboard: dashboard,
                  orientation: DesignOrientation.landscape,
                  deviceSafeSize: const Size(900, 500),
                  selectedId: 'speed',
                  onSelect: (_) {},
                  onPlacementChanged: (id, placement) {
                    final component = dashboard.components.firstWhere(
                      (value) => value.id == id,
                    );
                    rebuild(() {
                      dashboard = dashboard.withComponent(
                        component.withPlacement(
                          DesignOrientation.landscape,
                          placement,
                        ),
                      );
                    });
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('resize-both'))),
      const Size(44, 44),
    );

    final componentBefore = dashboard.components.first;
    final landscapeBefore =
        componentBefore.placements[DesignOrientation.landscape]!;
    final portraitBefore =
        componentBefore.placements[DesignOrientation.portrait];
    await tester.drag(
      find.byKey(const ValueKey('canvas-speed')),
      const Offset(30, -15),
    );
    await tester.pump();

    var landscape =
        dashboard.components.first.placements[DesignOrientation.landscape]!;
    expect(
      landscape.offset.dx,
      closeTo(landscapeBefore.offset.dx + 0.1, 0.002),
    );
    expect(
      landscape.offset.dy,
      closeTo(landscapeBefore.offset.dy + 0.05, 0.002),
    );

    final resolvedBefore = landscape.resolveSize(
      ComponentTypes.byId(dashboard.components.first.typeId),
      variant: dashboard.components.first.effectiveVariant,
    );
    final leftBefore =
        landscape.resolve(const Size(2.6, 1)).dx - resolvedBefore.width / 2;
    await tester.drag(
      find.byKey(const ValueKey('resize-width')),
      const Offset(30, 0),
    );
    await tester.pump();
    landscape =
        dashboard.components.first.placements[DesignOrientation.landscape]!;
    expect(landscape.size!.width, closeTo(resolvedBefore.width + 0.1, 0.002));
    expect(
      landscape.resolve(const Size(2.6, 1)).dx - landscape.size!.width / 2,
      closeTo(leftBefore, 0.002),
    );
    expect(
      dashboard.components.first.placements[DesignOrientation.portrait],
      same(portraitBefore),
    );
  });

  testWidgets('first resize remains linear across repeated gesture updates', (
    tester,
  ) async {
    await _setViewport(tester, const Size(900, 500));
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 828,
            height: 348,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return EditorCanvas(
                  dashboard: dashboard,
                  orientation: DesignOrientation.landscape,
                  deviceSafeSize: const Size(900, 500),
                  selectedId: 'speed',
                  onSelect: (_) {},
                  onPlacementChanged: (id, placement) {
                    final component = dashboard.components.firstWhere(
                      (value) => value.id == id,
                    );
                    rebuild(() {
                      dashboard = dashboard.withComponent(
                        component.withPlacement(
                          DesignOrientation.landscape,
                          placement,
                        ),
                      );
                    });
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    final component = dashboard.components.first;
    final placement = component.placements[DesignOrientation.landscape]!;
    final initial = placement.resolveSize(
      ComponentTypes.byId(component.typeId),
      variant: component.effectiveVariant,
    );
    final handle = find.byKey(const ValueKey('resize-width'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();
    await gesture.up();

    final resized =
        dashboard.components.first.placements[DesignOrientation.landscape]!;
    expect(resized.size!.width, closeTo(initial.width + 0.1, 0.002));
  });

  testWidgets('component remains draggable through dimmed off-frame area', (
    tester,
  ) async {
    await _setViewport(tester, const Size(900, 500));
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    final component = dashboard.components.first;
    final initial = component.placements[DesignOrientation.landscape]!;
    dashboard = dashboard.withComponent(
      component.withPlacement(
        DesignOrientation.landscape,
        initial.copyWith(offset: const Offset(-1, 0)),
      ),
    );
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 828,
            height: 348,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return EditorCanvas(
                  dashboard: dashboard,
                  orientation: DesignOrientation.landscape,
                  deviceSafeSize: const Size(900, 500),
                  selectedId: component.id,
                  onSelect: (_) {},
                  onPlacementChanged: (id, placement) {
                    rebuild(() {
                      dashboard = dashboard.withComponent(
                        dashboard.components
                            .firstWhere((value) => value.id == id)
                            .withPlacement(
                              DesignOrientation.landscape,
                              placement,
                            ),
                      );
                    });
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    final componentRect = tester.getRect(
      find.byKey(ValueKey('canvas-${component.id}')),
    );
    final frameRect = tester.getRect(
      find.byKey(const ValueKey('editor-canvas')),
    );
    final outsidePoint = Offset(
      math.max(componentRect.left + 8, frameRect.left - 12),
      componentRect.center.dy,
    );
    expect(outsidePoint.dx, lessThan(frameRect.left));

    await tester.dragFrom(outsidePoint, const Offset(30, 0));
    await tester.pump();
    final moved =
        dashboard.components.first.placements[DesignOrientation.landscape]!;
    expect(moved.offset.dx, closeTo(-0.9, 0.002));
  });

  testWidgets('portrait preview contains inherited landscape layout', (
    tester,
  ) async {
    await _setViewport(tester, const Size(393, 852));
    final dashboard = Dashboard.forkFrom(
      developmentPreset(),
      id: 'primary-only',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(dashboard: dashboard, onChanged: (_) {}),
      ),
    );

    // The preview boundary is the device envelope, dimmed and read-only. It is
    // the same envelope CREATE bakes, so pressing CREATE changes nothing on
    // screen.
    expect(_canvasAspect(tester), closeTo(393 / 852, 0.002));
    expect(find.text('INHERITED · READ ONLY'), findsOneWidget);
  });

  testWidgets('creating and resetting portrait alternate is explicit', (
    tester,
  ) async {
    const viewport = Size(393, 852);
    await _setViewport(tester, viewport);
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'primary-only');

    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          dashboard: dashboard,
          onChanged: (value) => dashboard = value,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('mechanical-drawer-latch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.tap(find.byKey(const ValueKey('create-layout')));
    await tester.pump();

    final expectedAspect = viewport.width / viewport.height;
    final sourcePlacement = developmentPreset()
        .components
        .first
        .placements[DesignOrientation.landscape]!;
    final bakedPlacement =
        dashboard.components.first.placements[DesignOrientation.portrait]!;
    final bakedExtent = dashboard.frameExtent(DesignOrientation.portrait);
    expect(dashboard.hasAuthoredLayout(DesignOrientation.portrait), isTrue);
    expect(
      dashboard.frameAspect(DesignOrientation.portrait),
      closeTo(expectedAspect, 0.001),
    );
    // The envelope grows; the geometry inside it is untouched. Nothing is
    // rescaled, so a design unit still means the same thing and the optical
    // stack does not move either.
    expect(bakedExtent.width, closeTo(2.6, 1e-9));
    expect(
      bakedPlacement.resolve(bakedExtent),
      _offsetCloseTo(sourcePlacement.resolve(const Size(2.6, 1))),
    );
    expect(_canvasAspect(tester), closeTo(expectedAspect, 0.001));

    await tester.tap(find.byKey(const ValueKey('remove-layout')));
    await tester.pump();

    expect(dashboard.hasAuthoredLayout(DesignOrientation.portrait), isFalse);
    expect(
      dashboard.layoutForViewport(DesignOrientation.portrait),
      DesignOrientation.landscape,
    );
    // Back to the read-only device envelope, which is what it was before.
    expect(_canvasAspect(tester), closeTo(393 / 852, 0.001));
  });


  group('canvas gestures', () {
    testWidgets('tap selects; an unselected component is not moved by a drag', (
      tester,
    ) async {
      final harness = await _pumpCanvas(tester, selectedId: null);

      await tester.tap(find.byKey(const ValueKey('canvas-speed')));
      await tester.pump();
      expect(harness.selected, 'speed');
      expect(harness.placementOf('speed'), same(harness.initialSpeedPlacement));

      // Still unselected as far as the canvas is concerned (the harness does
      // not feed selection back), so this drag must pan rather than nudge.
      final before = tester.getRect(
        find.byKey(const ValueKey('editor-canvas')),
      );
      await tester.drag(
        find.byKey(const ValueKey('canvas-speed')),
        const Offset(40, 0),
      );
      await tester.pump();
      expect(harness.placementOf('speed'), same(harness.initialSpeedPlacement));
      expect(
        tester.getRect(find.byKey(const ValueKey('editor-canvas'))).left,
        closeTo(before.left + 40, 0.001),
      );
    });

    testWidgets('a drag on empty substrate pans the camera', (tester) async {
      await _pumpCanvas(tester, selectedId: null);
      final frame = find.byKey(const ValueKey('editor-canvas'));
      final before = tester.getRect(frame);

      await tester.dragFrom(const Offset(20, 20), const Offset(35, 25));
      await tester.pump();

      final after = tester.getRect(frame);
      expect(after.left, closeTo(before.left + 35, 0.001));
      expect(after.top, closeTo(before.top + 25, 0.001));
    });

    testWidgets('FIT restores camera identity without writing placement', (
      tester,
    ) async {
      final harness = await _pumpCanvas(tester, selectedId: null);
      final frame = find.byKey(const ValueKey('editor-canvas'));
      final before = tester.getRect(frame);

      await tester.dragFrom(const Offset(20, 20), const Offset(40, 30));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('canvas-fit')));
      await tester.pump();

      expect(tester.getRect(frame).left, closeTo(before.left, 0.001));
      expect(harness.placementOf('speed'), same(harness.initialSpeedPlacement));
    });

    testWidgets('a second pointer promotes an element drag to the camera', (
      tester,
    ) async {
      final harness = await _pumpCanvas(tester, selectedId: 'speed');
      final start = tester.getCenter(find.byKey(const ValueKey('canvas-speed')));

      final first = await tester.startGesture(start);
      await first.moveBy(const Offset(20, 0));
      await tester.pump();
      final promoted = harness.placementOf('speed');
      expect(promoted, isNot(same(harness.initialSpeedPlacement)));

      final second = await tester.startGesture(start + const Offset(90, 0));
      await first.moveBy(const Offset(40, 0));
      await tester.pump();
      await second.moveBy(const Offset(40, 0));
      await tester.pump();
      // Frozen where it was when the second finger landed.
      expect(harness.placementOf('speed'), same(promoted));

      await first.up();
      await second.up();
      await tester.pump();
      expect(harness.placementOf('speed'), same(promoted));
    });

    testWidgets('handles stay 44px and on the border at any camera scale', (
      tester,
    ) async {
      await _pumpCanvas(tester, selectedId: 'speed');
      final handle = find.byKey(const ValueKey('resize-both'));
      final box = find.byKey(const ValueKey('canvas-speed'));
      expect(tester.getSize(handle), const Size(44, 44));
      expect(
        tester.getCenter(handle),
        _offsetCloseTo(tester.getRect(box).bottomRight, 0.001),
      );

      final centre = tester.getCenter(box);
      final first = await tester.startGesture(centre - const Offset(60, 0));
      final second = await tester.startGesture(centre + const Offset(60, 0));
      await first.moveBy(const Offset(-60, 0));
      await second.moveBy(const Offset(60, 0));
      await tester.pump();

      expect(tester.getSize(handle), const Size(44, 44));
      expect(
        tester.getCenter(handle),
        _offsetCloseTo(tester.getRect(box).bottomRight, 0.001),
      );
      await first.up();
      await second.up();
    });
  });

  testWidgets('full screen renders the frame at the runtime fit', (
    tester,
  ) async {
    const viewport = Size(393, 852);
    await _setViewport(tester, viewport);
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(dashboard: dashboard, onChanged: (_) {}),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('canvas-full')));
    await tester.pump();

    // No rail, no bay: the boundary is the whole route, so the render inside it
    // is at exactly the scale the cluster route would use.
    expect(find.byKey(const ValueKey('editor-workspace')), findsNothing);
    final frame = tester.getRect(find.byKey(const ValueKey('editor-canvas')));
    expect(frame.width, closeTo(viewport.width, 0.001));
    expect(frame.height, closeTo(viewport.height, 0.001));
  });

  testWidgets('add selector is generated from component registry', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1200, 900));
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          dashboard: dashboard,
          onChanged: (value) => dashboard = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('mechanical-drawer-latch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.tap(find.text('ADD PART'));
    await tester.pump();
    await tester.tap(find.text('OUTSIDE TEMPERATURE'));
    await tester.pump();

    expect(
      dashboard.components.where((value) => value.typeId == 'outsideTemp'),
      hasLength(1),
    );
  });

  testWidgets('authored frame exposes registration and exact aspect readout', (
    tester,
  ) async {
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: EditorCanvas(
          dashboard: dashboard,
          orientation: DesignOrientation.landscape,
          deviceSafeSize: const Size(900, 500),
          selectedId: null,
          onSelect: (_) {},
          onPlacementChanged: (_, _) {},
        ),
      ),
    );

    expect(find.text('LANDSCAPE · 2.600:1'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('editor has no overflow at required responsive sizes', (
    tester,
  ) async {
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    for (final size in const <Size>[
      Size(320, 568),
      Size(393, 852),
      Size(874, 402),
      Size(1024, 1366),
      Size(1440, 900),
    ]) {
      await _setViewport(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          home: EditorPage(
            key: ValueKey(size),
            dashboard: dashboard,
            onChanged: (_) {},
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'closed at $size');
      await tester.tap(find.byKey(const ValueKey('mechanical-drawer-latch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(tester.takeException(), isNull, reason: 'open at $size');
    }
  });
}

class _CanvasHarness {
  _CanvasHarness(this.dashboard);
  Dashboard dashboard;
  String? selected;
  late final Placement initialSpeedPlacement =
      dashboard.components.firstWhere((c) => c.id == 'speed').placements[
          DesignOrientation.landscape]!;

  Placement placementOf(String id) => dashboard.components
      .firstWhere((component) => component.id == id)
      .placements[DesignOrientation.landscape]!;
}

/// A bare canvas with no chrome, so gesture assertions are not confounded by
/// the rail or the service bay.
Future<_CanvasHarness> _pumpCanvas(
  WidgetTester tester, {
  required String? selectedId,
}) async {
  await _setViewport(tester, const Size(900, 500));
  final harness = _CanvasHarness(
    Dashboard.forkFrom(developmentPreset(), id: 'editor'),
  );
  harness.initialSpeedPlacement;
  late StateSetter rebuild;
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return EditorCanvas(
            dashboard: harness.dashboard,
            orientation: DesignOrientation.landscape,
            deviceSafeSize: const Size(900, 500),
            selectedId: selectedId,
            onSelect: (id) => harness.selected = id,
            onPlacementChanged: (id, placement) => rebuild(() {
              harness.dashboard = harness.dashboard.withComponent(
                harness.dashboard.components
                    .firstWhere((component) => component.id == id)
                    .withPlacement(DesignOrientation.landscape, placement),
              );
            }),
          );
        },
      ),
    ),
  );
  return harness;
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Matcher _offsetCloseTo(Offset expected, [double delta = 1e-9]) => isA<Offset>()
    .having((value) => value.dx, 'dx', closeTo(expected.dx, delta))
    .having((value) => value.dy, 'dy', closeTo(expected.dy, delta));

double _canvasAspect(WidgetTester tester) {
  final size = tester.getSize(find.byKey(const ValueKey('editor-canvas')));
  return size.width / size.height;
}
