import 'package:anode/app_state.dart';
import 'package:anode/data/design_repository.dart';
import 'package:anode/library/library_page.dart';
import 'package:anode/model/design_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/fixtures.dart';

void main() {
  testWidgets('preset edit visibly forks and opens dashboard editor', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final source = preset();
    final state = AnodeState.load(
      repository: DesignRepository(await SharedPreferences.getInstance()),
      presets: <DesignPreset>[source],
    );
    addTearDown(state.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: LibraryPage(state: state)));

    await tester.tap(find.text('EDIT'));
    await tester.pumpAndSettle();

    expect(state.dashboards, hasLength(1));
    expect(state.activeReference.kind, DesignKind.dashboard);
    expect(find.textContaining('FORKED FROM CLASSIC V1'), findsOneWidget);
    expect(find.text('ACK'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('Library and Settings avoid overflow on phone orientations', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final state = AnodeState.load(
      repository: DesignRepository(await SharedPreferences.getInstance()),
      presets: <DesignPreset>[preset()],
    );
    addTearDown(state.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in const <Size>[Size(320, 568), Size(874, 402)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryPage(key: ValueKey(size), state: state),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'Designs at $size');
      await tester.tap(find.text('SETTINGS'));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'Settings at $size');
    }
  });
}
