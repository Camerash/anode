import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:anode/editor/editor_canvas.dart';
import 'package:anode/editor/editor_page.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/dev_design.dart';
import 'package:anode/model/placement.dart';
import 'package:anode/model/settings.dart';
import 'package:anode/platform/physical_interface_orientation.dart';
import 'package:anode/vfd/prism_widgets.dart';
import 'package:anode/vfd/vfd_widgets.dart';
import 'package:flutter/gestures.dart';
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

    expect(_canvasAspect(tester), closeTo(1200 / 900, 0.001));
    expect(
      _canvasAspect(tester, key: const ValueKey('editor-authored-frame')),
      closeTo(2.6, 0.001),
    );
    await tester.tap(find.byKey(const ValueKey('editor-console')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
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

    await tester.tap(find.byKey(const ValueKey('editor-console')));
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
    final dockBefore = tester.getCenter(
      find.byKey(const ValueKey('editor-command-dock')),
    );
    await tester.tap(find.byKey(const ValueKey('editor-console')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final add = tester.widget<PrismButton>(
      find.byKey(const ValueKey('console-add')),
    );
    expect(add.enabled, isFalse);
    expect(add.onPressed, isNull);
    final after = tester.getCenter(frame);
    final dockAfter = tester.getCenter(
      find.byKey(const ValueKey('editor-command-dock')),
    );

    expect(after.dy, lessThan(before.dy));
    expect(_canvasAspect(tester), closeTo(393 / 852, 0.002));
    expect(dockAfter.dy, lessThan(dockBefore.dy));
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
                  deviceViewportSize: const Size(900, 500),
                  selectedId: 'speed',
                  snapEnabled: false,
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
    final designUnitPx = tester
        .getSize(find.byKey(const ValueKey('editor-authored-frame')))
        .height;
    await tester.drag(
      find.byKey(const ValueKey('canvas-speed')),
      const Offset(30, -15),
    );
    await tester.pump();

    var landscape =
        dashboard.components.first.placements[DesignOrientation.landscape]!;
    expect(
      landscape.center.dx,
      closeTo(landscapeBefore.center.dx + 30 / designUnitPx, 0.002),
    );
    expect(
      landscape.center.dy,
      closeTo(landscapeBefore.center.dy + 15 / designUnitPx, 0.002),
    );

    final resolvedBefore = landscape.size;
    final leftBefore = landscape.center.dx - resolvedBefore.width / 2;
    await tester.drag(
      find.byKey(const ValueKey('resize-width')),
      const Offset(30, 0),
    );
    await tester.pump();
    landscape =
        dashboard.components.first.placements[DesignOrientation.landscape]!;
    expect(
      landscape.size.width,
      closeTo(resolvedBefore.width + 30 / designUnitPx, 0.002),
    );
    expect(
      landscape.center.dx - landscape.size.width / 2,
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
                  deviceViewportSize: const Size(900, 500),
                  selectedId: 'speed',
                  snapEnabled: false,
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
    final initial = placement.size;
    final designUnitPx = tester
        .getSize(find.byKey(const ValueKey('editor-authored-frame')))
        .height;
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
    expect(
      resized.size.width,
      closeTo(initial.width + 30 / designUnitPx, 0.002),
    );
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
        initial.copyWith(center: const Offset(-1, 0)),
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
                  deviceViewportSize: const Size(900, 500),
                  selectedId: component.id,
                  snapEnabled: false,
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
      find.byKey(const ValueKey('editor-authored-frame')),
    );
    final outsidePoint = Offset(
      math.max(componentRect.left + 8, frameRect.left - 12),
      componentRect.center.dy,
    );
    expect(outsidePoint.dx, lessThan(frameRect.left));
    final designUnitPx = tester
        .getSize(find.byKey(const ValueKey('editor-authored-frame')))
        .height;

    await tester.dragFrom(outsidePoint, const Offset(30, 0));
    await tester.pump();
    final moved =
        dashboard.components.first.placements[DesignOrientation.landscape]!;
    expect(moved.center.dx, closeTo(-1 + 30 / designUnitPx, 0.002));
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
    await tester.tap(find.byKey(const ValueKey('editor-console')));
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
    expect(bakedPlacement.center, _offsetCloseTo(sourcePlacement.center));
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

      await tester.dragFrom(const Offset(140, 20), const Offset(35, 25));
      await tester.pump();

      final after = tester.getRect(frame);
      expect(after.left, closeTo(before.left + 35, 0.001));
      expect(after.top, closeTo(before.top + 25, 0.001));
    });

    testWidgets('CENTER restores camera identity after pan and zoom-out', (
      tester,
    ) async {
      final harness = await _pumpCanvas(tester, selectedId: null);
      final frame = find.byKey(const ValueKey('editor-canvas'));
      final before = tester.getRect(frame);

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: before.center,
          scrollDelta: const Offset(0, 300),
        ),
      );
      await tester.pump();
      expect(tester.getRect(frame).width, closeTo(before.width * 0.5, 0.001));

      await tester.dragFrom(const Offset(140, 20), const Offset(40, 30));
      await tester.pump();
      harness.controller.centerCamera();
      await tester.pump();

      expect(tester.getRect(frame), before);
      expect(harness.placementOf('speed'), same(harness.initialSpeedPlacement));
    });

    testWidgets('a second pointer promotes an element drag to the camera', (
      tester,
    ) async {
      final harness = await _pumpCanvas(tester, selectedId: 'speed');
      final start = tester.getCenter(
        find.byKey(const ValueKey('canvas-speed')),
      );

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

  testWidgets('editor starts with full viewport runtime fit', (tester) async {
    const viewport = Size(393, 852);
    await _setViewport(tester, viewport);
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(dashboard: dashboard, onChanged: (_) {}),
      ),
    );

    expect(find.byKey(const ValueKey('editor-workspace')), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-full')), findsNothing);
    final frame = tester.getRect(find.byKey(const ValueKey('editor-canvas')));
    expect(frame.left, closeTo(0, 0.001));
    expect(frame.top, closeTo(0, 0.001));
    expect(frame.size, viewport);
  });

  testWidgets('full-width header owns its band and dock stays compact', (
    tester,
  ) async {
    const viewport = Size(874, 402);
    await _setViewport(tester, viewport);
    final dashboard = Dashboard.forkFrom(
      developmentPreset(),
      id: 'long-header',
      name: 'A dashboard name long enough to require truncation',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(dashboard: dashboard, onChanged: (_) {}),
      ),
    );

    final layer = tester.getRect(
      find.byKey(const ValueKey('editor-header-layer')),
    );
    final commandDock = find.byKey(const ValueKey('editor-command-dock'));
    expect(layer, const Rect.fromLTWH(0, 0, 874, 48));
    expect(
      tester
          .widget<PrismPanel>(find.byKey(const ValueKey('editor-header-layer')))
          .surfaceOpacity,
      0.94,
    );
    expect(tester.widget<PrismPanel>(commandDock).surfaceOpacity, 0.90);
    expect(
      tester.getRect(commandDock).bottom,
      lessThanOrEqualTo(viewport.height),
    );
    expect(find.text('HISTORY'), findsNothing);
    expect(find.text('BUILD'), findsNothing);
    expect(find.text('VIEW'), findsNothing);
    expect(find.text('SNAP'), findsOneWidget);
    expect(find.text('CENTER'), findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-add')), findsNothing);
    expect(
      find.descendant(
        of: commandDock,
        matching: find.byKey(const ValueKey('orientation-portrait')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: commandDock,
        matching: find.byKey(const ValueKey('orientation-landscape')),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('canvas-snap')))
          .symbol,
      isNull,
    );
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('canvas-center')))
          .symbol,
      isNull,
    );
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('canvas-center')))
          .role,
      PrismRole.micro,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('canvas-undo'))).bottom,
      tester.getRect(find.byKey(const ValueKey('canvas-center'))).bottom,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('canvas-center'))).height,
      36,
    );

    final title = tester.widget<VfdLegend>(
      find.descendant(
        of: find.byKey(const ValueKey('editor-title')),
        matching: find.byType(VfdLegend),
      ),
    );
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(title.text, dashboard.name);
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('editor-console')))
          .label,
      'Console',
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('editor-console'))).right,
      closeTo(viewport.width - 4, 0.001),
    );

    final frame = find.byKey(const ValueKey('editor-canvas'));
    final before = tester.getRect(frame);
    final gesture = await tester.startGesture(
      Offset(viewport.width / 2, layer.center.dy),
    );
    await gesture.moveBy(const Offset(30, 20));
    await gesture.up();
    await tester.pump();
    final after = tester.getRect(frame);
    expect(after, before);
  });

  testWidgets('dock handle snaps continuously and persists on release', (
    tester,
  ) async {
    const viewport = Size(874, 402);
    await _setViewport(tester, viewport);
    EditorDockPreferences? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          dashboard: Dashboard.forkFrom(developmentPreset(), id: 'editor'),
          dockPreferences: const EditorDockPreferences(),
          onDockPreferencesChanged: (value) => changed = value,
          onChanged: (_) {},
        ),
      ),
    );

    final dock = find.byKey(const ValueKey('editor-command-dock'));
    expect(tester.getRect(dock).bottom, viewport.height);
    final handle = find.byKey(const ValueKey('editor-dock-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveTo(const Offset(8, 230));
    await tester.pump();
    expect(changed, isNull);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));

    expect(changed, isNotNull);
    expect(changed!.landscape.edge, EditorDockEdge.left);
    expect(changed!.landscape.alignment, closeTo(0.52, 0.08));
    expect(tester.getRect(dock).left, 0);
    expect(
      tester.getRect(find.byKey(const ValueKey('canvas-undo'))).top,
      lessThan(tester.getRect(find.byKey(const ValueKey('canvas-center'))).top),
    );

    changed = null;
    await tester.drag(
      find.byKey(const ValueKey('canvas-snap')),
      const Offset(120, 0),
    );
    await tester.pump();
    expect(changed, isNull);
  });

  testWidgets('portrait editor surfaces bleed while chrome stays safe', (
    tester,
  ) async {
    const viewport = Size(393, 852);
    const safeInsets = EdgeInsets.fromLTRB(0, 59, 0, 34);
    await _setViewport(tester, viewport);
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: viewport,
            padding: safeInsets,
            viewPadding: safeInsets,
          ),
          child: EditorPage(dashboard: dashboard, onChanged: (_) {}),
        ),
      ),
    );

    final header = tester.getRect(
      find.byKey(const ValueKey('editor-header-layer')),
    );
    final environment = tester.getRect(
      find.byKey(const ValueKey('editor-canvas-environment')),
    );
    expect(header, const Rect.fromLTWH(0, 0, 393, 107));
    expect(
      tester.getRect(find.byKey(const ValueKey('editor-back'))).top,
      greaterThanOrEqualTo(safeInsets.top),
    );
    expect(environment.left, 0);
    expect(environment.top, 0);
    expect(environment.right, viewport.width);
    expect(environment.bottom, viewport.height);
    expect(
      tester.getRect(find.byKey(const ValueKey('editor-console'))).top,
      greaterThanOrEqualTo(safeInsets.top),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('editor-console'))).right,
      closeTo(viewport.width - 4, 0.001),
    );
    final dock = tester.getRect(
      find.byKey(const ValueKey('editor-command-dock')),
    );
    final undo = tester.getRect(find.byKey(const ValueKey('canvas-undo')));
    final center = tester.getRect(find.byKey(const ValueKey('canvas-center')));
    expect(dock.left, 0);
    expect(undo.left, greaterThanOrEqualTo(safeInsets.left));
    expect(undo.top, lessThan(center.top));

    final frame = tester.getRect(find.byKey(const ValueKey('editor-canvas')));
    expect(frame.left, closeTo(0, 0.001));
    expect(frame.top, closeTo(0, 0.001));
    expect(frame.size, viewport);
    expect(
      tester.getRect(find.byKey(const ValueKey('canvas-undo'))).top,
      greaterThanOrEqualTo(header.bottom),
    );
    expect(
      center.bottom,
      lessThanOrEqualTo(viewport.height - safeInsets.bottom),
    );
    expect(find.byKey(const ValueKey('canvas-full')), findsNothing);
  });

  testWidgets('landscape editor assigns safe space to the physical pane', (
    tester,
  ) async {
    const viewport = Size(874, 402);
    const safeInsets = EdgeInsets.fromLTRB(59, 0, 59, 21);
    await _setViewport(tester, viewport);
    final leftDashboard = Dashboard.forkFrom(
      developmentPreset(),
      id: 'editor-left-island',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: viewport,
            padding: safeInsets,
            viewPadding: safeInsets,
          ),
          child: EditorPage(
            key: const ValueKey('left-island-editor'),
            dashboard: leftDashboard,
            interfaceOrientation: PhysicalInterfaceOrientation.landscapeLeft,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(
      tester.getRect(find.byKey(const ValueKey('editor-header-layer'))),
      const Rect.fromLTWH(0, 0, 874, 48),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('editor-back'))).left,
      greaterThanOrEqualTo(safeInsets.left),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('canvas-undo'))).left,
      greaterThanOrEqualTo(safeInsets.left),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('canvas-center'))).right,
      lessThanOrEqualTo(viewport.width - safeInsets.right),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('editor-console'))).right,
      closeTo(viewport.width - safeInsets.right - 4, 0.001),
    );
    final landscapeDock = tester.getRect(
      find.byKey(const ValueKey('editor-command-dock')),
    );
    expect(landscapeDock.bottom, viewport.height);
    expect(
      tester.getRect(find.byKey(const ValueKey('canvas-center'))).bottom,
      lessThanOrEqualTo(viewport.height - safeInsets.bottom),
    );

    final closedLeftBoundary = tester.getRect(
      find.byKey(const ValueKey('editor-canvas')),
    );
    expect(closedLeftBoundary.left, closeTo(0, 0.001));
    expect(closedLeftBoundary.top, closeTo(0, 0.001));
    expect(closedLeftBoundary.size, viewport);
    final closedLeftFrame = tester.getRect(
      find.byKey(const ValueKey('editor-authored-frame')),
    );
    final latch = find.byKey(const ValueKey('editor-console'));
    await tester.tap(latch);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final travellingLeftFrame = tester.getRect(
      find.byKey(const ValueKey('editor-authored-frame')),
    );
    expect(travellingLeftFrame.width, lessThan(closedLeftFrame.width));

    await tester.pump(const Duration(milliseconds: 90));
    expect(
      tester.getRect(find.byKey(const ValueKey('orientation-landscape'))).right,
      lessThanOrEqualTo(viewport.width),
    );
    final openLeftFrame = tester.getRect(
      find.byKey(const ValueKey('editor-authored-frame')),
    );
    final openLeftBoundary = tester.getRect(
      find.byKey(const ValueKey('editor-canvas')),
    );
    expect(openLeftFrame.width, lessThan(travellingLeftFrame.width));
    expect(openLeftFrame.left, greaterThanOrEqualTo(safeInsets.left));
    expect(openLeftBoundary.left, greaterThanOrEqualTo(safeInsets.left));
    expect(openLeftBoundary.right, lessThan(viewport.width));
    expect(
      tester.getRect(find.byKey(const ValueKey('editor-command-dock'))).right,
      lessThanOrEqualTo(openLeftBoundary.right),
    );

    final drawerEnvironment = tester.getRect(
      find.byKey(const ValueKey('mechanical-push-drawer')),
    );
    final drawerContent = tester.getRect(
      find.byKey(const ValueKey('mechanical-drawer-safe-content')),
    );
    final header = tester.getRect(
      find.byKey(const ValueKey('editor-header-layer')),
    );
    expect(drawerEnvironment.right, viewport.width);
    expect(drawerEnvironment.bottom, viewport.height);
    expect(drawerContent.top, greaterThanOrEqualTo(header.bottom));
    expect(drawerContent.right, lessThanOrEqualTo(viewport.width));
    expect(drawerContent.bottom, closeTo(viewport.height, 0.001));
    final lookTab = find.byKey(const ValueKey('editor-service-section-look'));
    expect(tester.getRect(lookTab).right, lessThanOrEqualTo(viewport.width));
    await tester.tap(lookTab);
    await tester.pump();
    expect(
      tester
          .getRect(find.byKey(const ValueKey('mechanical-drawer-safe-content')))
          .right,
      lessThanOrEqualTo(viewport.width),
    );
    expect(
      _canvasAspect(tester, key: const ValueKey('editor-authored-frame')),
      closeTo(leftDashboard.frameAspect(DesignOrientation.landscape), 0.001),
    );

    final rightDashboard = Dashboard.forkFrom(
      developmentPreset(),
      id: 'editor-right-island',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: viewport,
            padding: safeInsets,
            viewPadding: safeInsets,
          ),
          child: EditorPage(
            key: const ValueKey('right-island-editor'),
            dashboard: rightDashboard,
            interfaceOrientation: PhysicalInterfaceOrientation.landscapeRight,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    final closedRightFrame = tester.getRect(
      find.byKey(const ValueKey('editor-authored-frame')),
    );
    expect(closedRightFrame, closedLeftFrame);
    expect(
      tester.getRect(find.byKey(const ValueKey('editor-canvas'))),
      closedLeftBoundary,
    );

    await tester.tap(latch);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    final openRightFrame = tester.getRect(
      find.byKey(const ValueKey('editor-authored-frame')),
    );
    expect(openRightFrame.left, lessThan(openLeftFrame.left));
    expect(openRightFrame.left, lessThan(safeInsets.left));
    expect(
      _canvasAspect(tester, key: const ValueKey('editor-authored-frame')),
      closeTo(rightDashboard.frameAspect(DesignOrientation.landscape), 0.001),
    );

    final designTab = find.byKey(
      const ValueKey('editor-service-section-design'),
    );
    expect(
      tester.getRect(designTab).right,
      lessThanOrEqualTo(viewport.width - safeInsets.right),
    );
    await tester.tap(find.byKey(const ValueKey('editor-service-section-look')));
    await tester.pump();
    expect(
      tester
          .getRect(find.byKey(const ValueKey('editor-service-section-look')))
          .right,
      lessThanOrEqualTo(viewport.width - safeInsets.right),
    );
  });

  testWidgets('safe chrome never clamps authored elements or resize handles', (
    tester,
  ) async {
    const safeInsets = EdgeInsets.fromLTRB(80, 60, 80, 40);
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    final speed = dashboard.components.firstWhere(
      (component) => component.id == 'speed',
    );
    const edgePlacement = Placement(
      center: Offset(-1.15, 0),
      size: Size(0.4, 0.25),
    );
    dashboard = dashboard.withComponent(
      speed.withPlacement(DesignOrientation.landscape, edgePlacement),
    );
    Placement? resized;
    await _setViewport(tester, const Size(900, 500));
    await tester.pumpWidget(
      MaterialApp(
        home: EditorCanvas(
          dashboard: dashboard,
          orientation: DesignOrientation.landscape,
          deviceViewportSize: const Size(900, 500),
          frameInset: EdgeInsets.zero,
          selectedId: 'speed',
          onSelect: (_) {},
          onPlacementChanged: (_, placement) => resized = placement,
        ),
      ),
    );

    final element = tester.getRect(find.byKey(const ValueKey('canvas-speed')));
    expect(element.left, lessThan(safeInsets.left));

    final handle = find.byKey(const ValueKey('resize-width'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.up();
    expect(resized, isNotNull);
    expect(resized!.size.width, greaterThan(edgePlacement.size.width));
  });

  testWidgets('landscape dock owns only its physical unsafe edge', (
    tester,
  ) async {
    const viewport = Size(874, 402);
    const safeInsets = EdgeInsets.fromLTRB(59, 0, 59, 21);
    const dockPreferences = EditorDockPreferences(
      landscape: EditorDockPlacement(edge: EditorDockEdge.left, alignment: 0.5),
    );

    Future<Rect> pumpFor(PhysicalInterfaceOrientation orientation) async {
      await _setViewport(tester, viewport);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: viewport,
              padding: safeInsets,
              viewPadding: safeInsets,
            ),
            child: EditorPage(
              dashboard: Dashboard.forkFrom(
                developmentPreset(),
                id: 'dock-$orientation',
              ),
              interfaceOrientation: orientation,
              dockPreferences: dockPreferences,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      return tester.getRect(find.byKey(const ValueKey('canvas-undo')));
    }

    final leftIsland = await pumpFor(
      PhysicalInterfaceOrientation.landscapeLeft,
    );
    final rightIsland = await pumpFor(
      PhysicalInterfaceOrientation.landscapeRight,
    );
    expect(leftIsland.left, closeTo(safeInsets.left + 2, 0.001));
    expect(rightIsland.left, closeTo(2, 0.001));
  });

  testWidgets('ADD catalogue direct drag shows ghost and places a part', (
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

    await tester.tap(find.byKey(const ValueKey('editor-console')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.tap(find.byKey(const ValueKey('console-add')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('SEGMENTED NUMERIC SPEED READOUT.'), findsOneWidget);

    final source = find.byKey(const ValueKey('add-outsideTemp'));
    await tester.tap(source);
    await tester.pump();
    expect(find.text('PREVIEW · OUTSIDE TEMPERATURE'), findsOneWidget);
    final target = tester.getCenter(
      find.byKey(const ValueKey('editor-authored-frame')),
    );
    final drag = await tester.startGesture(tester.getCenter(source));
    await drag.moveTo(target);
    await tester.pump();
    expect(find.byKey(const ValueKey('add-drop-ghost')), findsOneWidget);
    final panelPosition = tester.getCenter(source);
    await drag.moveTo(panelPosition);
    await tester.pump();
    expect(find.byKey(const ValueKey('add-drop-ghost')), findsOneWidget);
    final ghostCenter = tester.getCenter(
      find.byKey(const ValueKey('add-drop-ghost')),
    );
    expect(ghostCenter.dx, closeTo(panelPosition.dx, 0.01));
    expect(ghostCenter.dy, closeTo(panelPosition.dy, 0.01));
    await drag.moveTo(target);
    await drag.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('add-drop-ghost')), findsNothing);

    final added = dashboard.components
        .where((value) => value.typeId == 'outsideTemp')
        .single;

    final committedRect = tester.getRect(
      find.byKey(ValueKey('canvas-${added.id}')),
    );
    expect(committedRect.center.dx, closeTo(target.dx, 0.01));
    expect(committedRect.center.dy, closeTo(target.dy, 0.01));

    final center = added.placements[DesignOrientation.landscape]!.center;
    expect(center.dx / 0.1, closeTo((center.dx / 0.1).round(), 1e-9));
    expect(center.dy / 0.1, closeTo((center.dy / 0.1).round(), 1e-9));
  });

  testWidgets('ADD catalogue returns to prior Console section', (tester) async {
    await _setViewport(tester, const Size(900, 500));
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(dashboard: dashboard, onChanged: (_) {}),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('editor-console')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.tap(find.byKey(const ValueKey('editor-service-section-look')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('console-add')));
    await tester.pump();
    expect(find.byKey(const ValueKey('add-catalogue-close')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-catalogue-close')));
    await tester.pump();
    expect(
      tester
          .widget<PrismButton>(
            find.byKey(const ValueKey('editor-service-section-look')),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets('PART exposes scalar controls inline and variant in panel', (
    tester,
  ) async {
    await _setViewport(tester, const Size(900, 500));
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          dashboard: dashboard,
          onChanged: (value) => dashboard = value,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('canvas-speed')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-console')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.byKey(const ValueKey('part-control-variant')), findsOneWidget);
    expect(find.byKey(const ValueKey('part-control-module')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('part-control-param:digits')),
      findsOneWidget,
    );
    expect(
      tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('part-controls-speed')),
      ),
      isNotNull,
    );
    final removeRect = tester.getRect(find.byKey(const ValueKey('remove-arm')));
    final controlsRect = tester.getRect(
      find.byKey(const ValueKey('part-controls-speed')),
    );
    expect(removeRect.bottom, lessThanOrEqualTo(controlsRect.top));
    expect(removeRect.right, greaterThan(controlsRect.center.dx));
    expect(
      tester
          .getRect(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('part-controls-speed')),
                  matching: find.byType(PrismPanel),
                )
                .first,
          )
          .bottom,
      closeTo(500, 0.001),
    );
    expect(find.byKey(const ValueKey('pager-detent-rail')), findsNothing);
    expect(find.byKey(const ValueKey('param-digits-cell-strip')), findsNothing);
    expect(find.text('SPEED DIGITS'), findsWidgets);
    expect(find.byKey(const ValueKey('part-control-back')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('param-digits-decrement')));
    await tester.pump();
    expect(
      dashboard.components
          .where((component) => component.id == 'speed')
          .single
          .effectiveParams['digits'],
      2,
    );
    expect(find.byKey(const ValueKey('part-control-back')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('part-control-variant')));
    await tester.pump();
    expect(find.byKey(const ValueKey('part-control-back')), findsOneWidget);
    expect(find.text('VARIANT'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('part-control-back')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('canvas-bar')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('param-cells-cell-strip')),
      findsOneWidget,
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
          deviceViewportSize: const Size(900, 500),
          selectedId: null,
          onSelect: (_) {},
          onPlacementChanged: (_, _) {},
        ),
      ),
    );

    expect(find.text('LANDSCAPE · 2.600:1'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('selection frame keeps component name out of canvas chrome', (
    tester,
  ) async {
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: EditorCanvas(
          dashboard: dashboard,
          orientation: DesignOrientation.landscape,
          deviceViewportSize: const Size(900, 500),
          selectedId: 'speed',
          onSelect: (_) {},
          onPlacementChanged: (_, _) {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('canvas-speed')), findsOneWidget);
    expect(find.text('SPEED DIGITS'), findsNothing);
  });

  testWidgets('device viewport never changes authored frame geometry', (
    tester,
  ) async {
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: EditorCanvas(
          dashboard: dashboard,
          orientation: DesignOrientation.landscape,
          deviceViewportSize: const Size(900, 500),
          selectedId: null,
          onSelect: (_) {},
          onPlacementChanged: (_, _) {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('device-safe-guide')), findsNothing);
    expect(_canvasAspect(tester), closeTo(900 / 500, 0.001));
    expect(
      _canvasAspect(tester, key: const ValueKey('editor-authored-frame')),
      closeTo(2.6, 0.001),
    );
  });

  testWidgets(
    'selected part removal is immediate and editor undo/redo restores it',
    (tester) async {
      await _setViewport(tester, const Size(900, 500));
      var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
      await tester.pumpWidget(
        MaterialApp(
          home: EditorPage(
            dashboard: dashboard,
            onChanged: (value) => dashboard = value,
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('canvas-speed')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('editor-console')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));

      expect(find.text('RACK'), findsNothing);
      final arm = find.byKey(const ValueKey('remove-arm'));
      expect(arm, findsOneWidget);
      final remove = tester.widget<PrismButton>(arm);
      expect(remove.palette.lit, const Color(0xFFFF4A3D));
      expect(remove.lit, isTrue);

      final undo = find.byKey(const ValueKey('canvas-undo'));
      final redo = find.byKey(const ValueKey('canvas-redo'));
      expect(tester.widget<PrismButton>(undo).symbol, PrismSymbol.undo);
      expect(tester.widget<PrismButton>(redo).symbol, PrismSymbol.redo);
      expect(tester.widget<PrismButton>(undo).enabled, isFalse);
      expect(tester.widget<PrismButton>(redo).enabled, isFalse);
      expect(tester.widget<PrismButton>(undo).lit, isFalse);
      expect(tester.widget<PrismButton>(redo).lit, isFalse);

      await tester.tap(arm);
      await tester.pump();
      expect(dashboard.components.where((item) => item.id == 'speed'), isEmpty);
      expect(tester.widget<PrismButton>(undo).enabled, isTrue);
      expect(tester.widget<PrismButton>(undo).lit, isTrue);

      await tester.tap(undo);
      await tester.pump();
      expect(
        dashboard.components.where((item) => item.id == 'speed'),
        hasLength(1),
      );
      expect(tester.widget<PrismButton>(redo).enabled, isTrue);
      expect(tester.widget<PrismButton>(redo).lit, isTrue);
      expect(redo.hitTestable(), findsOneWidget);

      await tester.tap(redo);
      await tester.pump();
      expect(dashboard.components.where((item) => item.id == 'speed'), isEmpty);

      await tester.tap(undo);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('canvas-speed')),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('remove-arm')));
      await tester.pump();
      expect(tester.widget<PrismButton>(redo).enabled, isFalse);
    },
  );

  testWidgets('one move gesture creates one undo history entry', (
    tester,
  ) async {
    await _setViewport(tester, const Size(900, 500));
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          dashboard: dashboard,
          onChanged: (value) => dashboard = value,
        ),
      ),
    );

    final speed = find.byKey(const ValueKey('canvas-speed'));
    await tester.tap(speed, warnIfMissed: false);
    await tester.pump();
    final before = dashboard.components
        .where((item) => item.id == 'speed')
        .single
        .placements[DesignOrientation.landscape]!;

    final drag = await tester.startGesture(tester.getCenter(speed));
    await drag.moveBy(const Offset(18, 0));
    await tester.pump();
    await drag.moveBy(const Offset(18, 0));
    await tester.pump();
    await drag.moveBy(const Offset(18, 0));
    await tester.pump();
    await drag.up();
    await tester.pump();

    final moved = dashboard.components
        .where((item) => item.id == 'speed')
        .single
        .placements[DesignOrientation.landscape]!;
    expect(moved.center, isNot(before.center));

    final undo = find.byKey(const ValueKey('canvas-undo'));
    expect(tester.widget<PrismButton>(undo).enabled, isTrue);
    expect(tester.widget<PrismButton>(undo).lit, isTrue);
    await tester.tap(undo);
    await tester.pump();
    final restored = dashboard.components
        .where((item) => item.id == 'speed')
        .single
        .placements[DesignOrientation.landscape]!;
    expect(restored.center, before.center);
    expect(restored.size, before.size);
  });

  testWidgets('SNAP defaults active and toggle mutates no placement', (
    tester,
  ) async {
    await _setViewport(tester, const Size(900, 500));
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    final before = dashboard.toJson().toString();
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(dashboard: dashboard, onChanged: (_) {}),
      ),
    );

    final snap = find.byKey(const ValueKey('canvas-snap'));
    expect(
      tester.getSemantics(snap).flagsCollection.isToggled,
      Tristate.isTrue,
    );
    await tester.tap(snap);
    await tester.pump();
    expect(
      tester.getSemantics(snap).flagsCollection.isToggled,
      Tristate.isFalse,
    );
    expect(dashboard.toJson().toString(), before);

    await tester.tap(find.byKey(const ValueKey('editor-console')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.tap(find.byKey(const ValueKey('orientation-portrait')));
    await tester.pump();
    expect(find.byKey(const ValueKey('canvas-full')), findsNothing);
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('canvas-center')))
          .label,
      'Center',
    );
    expect(
      tester.getSemantics(snap).flagsCollection.isToggled,
      Tristate.isFalse,
    );
  });

  testWidgets('PLACE keeps D-pad and both size axes on one surface', (
    tester,
  ) async {
    await _setViewport(tester, const Size(900, 500));
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          dashboard: dashboard,
          onChanged: (value) => dashboard = value,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('canvas-speed')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-console')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.tap(
      find.byKey(const ValueKey('editor-service-section-place')),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('placement-dpad')), findsOneWidget);
    expect(find.byKey(const ValueKey('placement-W-minus')), findsOneWidget);
    expect(find.byKey(const ValueKey('placement-W-plus')), findsOneWidget);
    expect(find.byKey(const ValueKey('placement-H-minus')), findsOneWidget);
    expect(find.byKey(const ValueKey('placement-H-plus')), findsOneWidget);
    expect(find.byKey(const ValueKey('placement-center')), findsOneWidget);
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('placement-y+')))
          .shape,
      PrismShape.triangleUp,
    );
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('placement-x-')))
          .shape,
      PrismShape.triangleLeft,
    );
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('placement-x+')))
          .shape,
      PrismShape.triangleRight,
    );
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('placement-y-')))
          .shape,
      PrismShape.triangleDown,
    );
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('placement-center')))
          .shape,
      PrismShape.rectangular,
    );
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('placement-center')))
          .symbol,
      PrismSymbol.center,
    );
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('placement-center')))
          .square,
      isTrue,
    );
    final dpad = tester.getRect(find.byKey(const ValueKey('placement-dpad')));
    expect(dpad.width, closeTo(dpad.height, 0.001));
    expect(find.byKey(const ValueKey('prism-symbol-center')), findsOneWidget);
    expect(find.text('Move up'), findsNothing);

    final before =
        dashboard.components.first.placements[DesignOrientation.landscape]!;
    await tester.tap(find.byKey(const ValueKey('placement-x+')));
    await tester.pump();
    final after =
        dashboard.components.first.placements[DesignOrientation.landscape]!;
    expect(after.center.dx, closeTo(before.center.dx + 0.005, 1e-12));
    expect(after.center.dy, before.center.dy);

    await tester.tap(find.byKey(const ValueKey('placement-center')));
    await tester.pump();
    final centred =
        dashboard.components.first.placements[DesignOrientation.landscape]!;
    expect(centred.center, Offset.zero);
  });

  testWidgets('drawer edge follows window shape, never preview orientation', (
    tester,
  ) async {
    Future<Size> openFor(Size viewport, DesignOrientation preview) async {
      await _setViewport(tester, viewport);
      final dashboard = Dashboard.forkFrom(
        developmentPreset(),
        id: 'editor-${viewport.width}',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EditorPage(
            key: ValueKey(viewport),
            dashboard: dashboard,
            onChanged: (_) {},
          ),
        ),
      );
      final content = find.byKey(const ValueKey('mechanical-drawer-content'));
      final before = tester.getSize(content);
      await tester.tap(find.byKey(const ValueKey('editor-console')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      await tester.tap(find.byKey(ValueKey('orientation-${preview.name}')));
      await tester.pump();
      final after = tester.getSize(content);
      return Size(before.width - after.width, before.height - after.height);
    }

    final portrait = await openFor(
      const Size(393, 852),
      DesignOrientation.landscape,
    );
    expect(portrait.height, greaterThan(0));
    expect(portrait.width, closeTo(0, 0.001));

    final landscape = await openFor(
      const Size(874, 402),
      DesignOrientation.portrait,
    );
    expect(landscape.width, greaterThan(0));
    expect(landscape.height, closeTo(0, 0.001));

    final square = await openFor(
      const Size(600, 600),
      DesignOrientation.portrait,
    );
    expect(square.width, greaterThan(0));
    expect(square.height, closeTo(0, 0.001));
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
      await tester.tap(find.byKey(const ValueKey('editor-console')));
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
  final EditorCanvasController controller = EditorCanvasController();
  late final Placement initialSpeedPlacement = dashboard.components
      .firstWhere((c) => c.id == 'speed')
      .placements[DesignOrientation.landscape]!;

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
            deviceViewportSize: const Size(900, 500),
            controller: harness.controller,
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

double _canvasAspect(
  WidgetTester tester, {
  Key key = const ValueKey('editor-canvas'),
}) {
  final size = tester.getSize(find.byKey(key));
  return size.width / size.height;
}
