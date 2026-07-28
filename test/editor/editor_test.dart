import 'package:anode/editor/editor_canvas.dart';
import 'package:anode/editor/editor_page.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/dev_design.dart';
import 'package:anode/model/placement.dart';
import 'package:anode/model/vfd_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('canvas fits authored aspect for each orientation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');

    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(dashboard: dashboard, onChanged: (_) {}),
      ),
    );

    expect(_canvasAspect(tester), closeTo(2.6, 0.001));
    await tester.tap(find.text('PORTRAIT'));
    await tester.pump();
    expect(_canvasAspect(tester), closeTo(1 / 2.6, 0.001));
  });

  testWidgets('phone landscape keeps canvas and component tools side by side', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(874, 402);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');

    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          dashboard: dashboard,
          forkedFrom: 'development scaffold',
          onChanged: (_) {},
        ),
      ),
    );

    final canvasRight = tester
        .getTopRight(find.byKey(const ValueKey('editor-canvas')))
        .dx;
    final toolsLeft = tester.getTopLeft(find.text('COMPONENTS')).dx;
    expect(toolsLeft, greaterThan(canvasRight));
  });

  testWidgets('drag and resize update displayed orientation only', (
    tester,
  ) async {
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Center(
                child: SizedBox(
                  width: 780,
                  height: 300,
                  child: EditorCanvas(
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
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    final portraitBefore =
        dashboard.components.first.placements[DesignOrientation.portrait];
    await tester.drag(
      find.byKey(const ValueKey('canvas-speed')),
      const Offset(30, -15),
    );
    await tester.pump();

    var landscape =
        dashboard.components.first.placements[DesignOrientation.landscape]!;
    expect(landscape.offset.dx, closeTo(0.1, 0.01));
    expect(landscape.offset.dy, closeTo(0.16, 0.01));
    expect(
      dashboard.components.first.placements[DesignOrientation.portrait],
      same(portraitBefore),
    );

    await tester.drag(
      find.byKey(const ValueKey('resize-width')),
      const Offset(30, 0),
    );
    await tester.pump();

    landscape =
        dashboard.components.first.placements[DesignOrientation.landscape]!;
    expect(landscape.size!.width, closeTo(1.235, 0.01));
    expect(landscape.size!.height, closeTo(0.588, 0.001));
  });

  testWidgets('add menu is generated from component registry', (tester) async {
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');

    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          dashboard: dashboard,
          onChanged: (value) => dashboard = value,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Add component'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Outside temperature'));
    await tester.pumpAndSettle();

    expect(
      dashboard.components.where((value) => value.typeId == 'outsideTemp'),
      hasLength(1),
    );
    expect(find.text('Parameters'), findsOneWidget);
    expect(find.text('celsius'), findsOneWidget);
  });

  testWidgets('secondary module region drags in displayed orientation', (
    tester,
  ) async {
    var dashboard = Dashboard(
      id: 'modules',
      name: 'Modules',
      supportedOrientations: <DesignOrientation>{
        DesignOrientation.landscape,
        DesignOrientation.portrait,
      },
      components: const [],
      modules: <VfdModule>[
        VfdModule(
          id: 'secondary',
          name: 'Secondary',
          regions: const <DesignOrientation, Placement>{
            DesignOrientation.landscape: Placement(size: Size(0.8, 0.4)),
            DesignOrientation.portrait: Placement(
              offset: Offset(0, 0.2),
              size: Size(0.4, 0.8),
            ),
          },
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 780,
            height: 300,
            child: EditorCanvas(
              dashboard: dashboard,
              orientation: DesignOrientation.landscape,
              selectedId: null,
              selectedModuleId: 'secondary',
              onSelect: (_) {},
              onPlacementChanged: (_, _) {},
              onModulePlacementChanged: (id, placement) {
                final module = dashboard.modules.firstWhere(
                  (value) => value.id == id,
                );
                dashboard = dashboard.withModule(
                  module.copyWith(
                    regions: <DesignOrientation, Placement>{
                      ...module.regions,
                      DesignOrientation.landscape: placement,
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey('module-secondary')),
      const Offset(30, -15),
    );
    await tester.pump();

    expect(
      dashboard.modules.last.regions[DesignOrientation.landscape]!.offset,
      const Offset(0.1, 0.05),
    );
    expect(
      dashboard.modules.last.regions[DesignOrientation.portrait]!.offset,
      const Offset(0, 0.2),
    );
  });

  testWidgets('reset applies recommended size explicitly', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');

    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          dashboard: dashboard,
          onChanged: (value) => dashboard = value,
        ),
      ),
    );

    await tester.tap(find.text('SPEED DIGITS'));
    await tester.pump();
    await tester.ensureVisible(find.text('RESET TO VARIANT SIZE'));
    await tester.tap(find.text('RESET TO VARIANT SIZE'));
    await tester.pump();

    expect(
      dashboard.components.first.placements[DesignOrientation.landscape]!.size,
      const Size(1.035, 0.588),
    );
  });
}

double _canvasAspect(WidgetTester tester) {
  final size = tester.getSize(find.byKey(const ValueKey('editor-canvas')));
  return size.width / size.height;
}
