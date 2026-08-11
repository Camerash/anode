import 'package:anode/editor/editor_page.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/dev_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('advanced layout controls stay behind Screen setup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 700);
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
    await tester.tap(find.byKey(const ValueKey('editor-console')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.byKey(const ValueKey('open-screen-setup')), findsOneWidget);
    expect(find.byKey(const ValueKey('screen-layout-rail')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('open-screen-setup')));
    await tester.pump();

    expect(find.byKey(const ValueKey('screen-layout-rail')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('screen-behavior-selector')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('add-layout')));
    await tester.pump();

    expect(find.byKey(const ValueKey('layout-aspect-map')), findsOneWidget);
    expect(find.byKey(const ValueKey('new-layout-width')), findsOneWidget);
    expect(find.byKey(const ValueKey('new-layout-height')), findsOneWidget);
    expect(dashboard.layouts, hasLength(1));
  });
}
