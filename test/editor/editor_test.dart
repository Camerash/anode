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

  testWidgets('canvas fits authored aspect for each orientation', (
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
    expect(_canvasAspect(tester), closeTo(1 / 2.6, 0.001));
  });

  testWidgets('drawer overlays canvas and selection does not open it', (
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
    final drawerClosed = tester.getTopLeft(
      find.byKey(const ValueKey('mechanical-drawer')),
    );

    await tester.tap(find.byKey(const ValueKey('canvas-speed')));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('mechanical-drawer'))),
      drawerClosed,
    );

    await tester.tap(find.byKey(const ValueKey('mechanical-drawer-latch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      tester.getSize(find.byKey(const ValueKey('editor-canvas'))),
      canvasBefore,
    );
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
    final leftBefore = landscape.resolve(2.6).dx - resolvedBefore.width / 2;
    await tester.drag(
      find.byKey(const ValueKey('resize-width')),
      const Offset(30, 0),
    );
    await tester.pump();
    landscape =
        dashboard.components.first.placements[DesignOrientation.landscape]!;
    expect(landscape.size!.width, closeTo(resolvedBefore.width + 0.1, 0.002));
    expect(
      landscape.resolve(2.6).dx - landscape.size!.width / 2,
      closeTo(leftBefore, 0.002),
    );
    expect(
      dashboard.components.first.placements[DesignOrientation.portrait],
      same(portraitBefore),
    );
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

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

double _canvasAspect(WidgetTester tester) {
  final size = tester.getSize(find.byKey(const ValueKey('editor-canvas')));
  return size.width / size.height;
}
