import 'dart:ui' as ui;

import 'package:anode/editor/editor_page.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/design.dart';
import 'package:anode/model/design_layout.dart';
import 'package:anode/model/dev_design.dart';
import 'package:anode/vfd/prism_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Design opens direct three-column square layout grid', (
    tester,
  ) async {
    _setView(tester, const Size(1200, 700));
    var dashboard = Dashboard.forkFrom(
      developmentPreset(),
      id: 'editor',
    ).withLayout(id: 'square', aspect: 1, sourceLayoutId: 'wide');

    await _pumpEditor(
      tester,
      dashboard,
      onChanged: (value) => dashboard = value,
    );
    await _openConsole(tester);

    expect(find.byKey(const ValueKey('add-layout')), findsOneWidget);
    expect(find.byKey(const ValueKey('screen-lock')), findsOneWidget);
    expect(find.byKey(const ValueKey('screen-layout-grid')), findsOneWidget);
    expect(find.byKey(const ValueKey('modify-layout')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-screen-setup')), findsNothing);
    expect(find.byKey(const ValueKey('close-screen-setup')), findsNothing);
    expect(find.byKey(const ValueKey('screen-layout-rail')), findsNothing);
    expect(
      find.byKey(const ValueKey('screen-behavior-selector')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('remove-layout')), findsNothing);

    final grid = tester.widget<GridView>(
      find.byKey(const ValueKey('screen-layout-grid')),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);

    final wideButton = tester.getRect(
      find.byKey(const ValueKey('layout-tile-wide')),
    );
    final squareButton = tester.getRect(
      find.byKey(const ValueKey('layout-tile-square')),
    );
    expect(wideButton.size, const Size.square(108));
    expect(squareButton.size, const Size.square(108));

    final gridRect = tester.getRect(
      find.byKey(const ValueKey('screen-layout-grid')),
    );
    final columnWidth = (gridRect.width - 16) / 3;
    expect(
      squareButton.center.dx - wideButton.center.dx,
      closeTo(columnWidth + 8, 0.01),
    );
    expect(
      gridRect.right - squareButton.center.dx,
      closeTo(columnWidth * 1.5 + 8, 0.01),
    );

    final frame = tester.getRect(
      find.byKey(const ValueKey('layout-ratio-frame-wide')),
    );
    expect(frame.size, const Size(60, 28));
  });

  testWidgets('Lock fixes selected layout and removal restores base', (
    tester,
  ) async {
    _setView(tester, const Size(1200, 700));
    var dashboard = Dashboard.forkFrom(
      developmentPreset(),
      id: 'editor',
    ).withLayout(id: 'square', aspect: 1, sourceLayoutId: 'wide');

    await _pumpEditor(
      tester,
      dashboard,
      onChanged: (value) => dashboard = value,
    );
    await _openConsole(tester);

    await tester.tap(find.byKey(const ValueKey('screen-layout-square')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('screen-lock')));
    await tester.pump();

    expect(dashboard.screenSetup.behavior, ScreenBehavior.lock);
    expect(dashboard.screenSetup.lockedLayoutId, 'square');
    final lock = tester.widget<PrismButton>(
      find.byKey(const ValueKey('screen-lock')),
    );
    expect(lock.value, isNull);
    expect(lock.lit, isTrue);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('screen-lock')))
          .flagsCollection
          .isToggled,
      ui.Tristate.isTrue,
    );
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('screen-layout-wide')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<PrismButton>(
            find.byKey(const ValueKey('screen-layout-square')),
          )
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('remove-layout')));
    await tester.pump();

    expect(dashboard.layouts.map((layout) => layout.id), <String>['wide']);
    expect(dashboard.screenSetup.behavior, ScreenBehavior.adapt);
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('screen-layout-wide')))
          .selected,
      isTrue,
    );
  });

  testWidgets('Add keeps lock and Modify updates locked orientation', (
    tester,
  ) async {
    _setView(tester, const Size(1200, 700));
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');

    await _pumpEditor(
      tester,
      dashboard,
      onChanged: (value) => dashboard = value,
    );
    await _openConsole(tester);

    await tester.tap(find.byKey(const ValueKey('screen-lock')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-layout')));
    await tester.pump();

    expect(find.byKey(const ValueKey('layout-aspect-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('new-layout-width')), findsOneWidget);
    expect(find.byKey(const ValueKey('new-layout-height')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('create-layout')));
    await tester.pump();

    expect(dashboard.layouts, hasLength(2));
    expect(dashboard.screenSetup.behavior, ScreenBehavior.lock);
    expect(dashboard.screenSetup.lockedLayoutId, 'wide');
    expect(
      tester
          .widget<PrismButton>(find.byKey(const ValueKey('screen-layout-wide')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<PrismButton>(
            find.byKey(const ValueKey('screen-layout-layout-1')),
          )
          .enabled,
      isFalse,
    );

    await tester.tap(find.byKey(const ValueKey('modify-layout')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('layout-preset-0')));
    await tester.pump();

    expect(find.byKey(const ValueKey('modify-layout-width')), findsOneWidget);
    expect(find.byKey(const ValueKey('apply-layout')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cancel-layout-draft')));
    await tester.pump();
    expect(dashboard.frameAspect('wide'), closeTo(2.6, 0.0001));

    await tester.tap(find.byKey(const ValueKey('modify-layout')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('layout-preset-0')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('apply-layout')));
    await tester.pump();

    expect(dashboard.frameAspect('wide'), closeTo(9 / 20, 0.0001));
    expect(
      dashboard.screenSetup.lockedOrientation,
      ViewportOrientation.portrait,
    );
  });

  testWidgets('Bottom Console uses three layout columns', (tester) async {
    _setView(tester, const Size(700, 1200));
    var dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');

    await _pumpEditor(
      tester,
      dashboard,
      onChanged: (value) => dashboard = value,
    );
    await _openConsole(tester);

    final grid = tester.widget<GridView>(
      find.byKey(const ValueKey('screen-layout-grid')),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
  });
}

void _setView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpEditor(
  WidgetTester tester,
  Dashboard dashboard, {
  required ValueChanged<Dashboard> onChanged,
}) => tester.pumpWidget(
  MaterialApp(
    home: EditorPage(dashboard: dashboard, onChanged: onChanged),
  ),
);

Future<void> _openConsole(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('editor-console')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 180));
}
