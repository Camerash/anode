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

    await tester.pumpWidget(MaterialApp(home: LibraryPage(state: state)));

    await tester.tap(find.text('EDIT'));
    await tester.pumpAndSettle();

    expect(state.dashboards, hasLength(1));
    expect(state.activeReference.kind, DesignKind.dashboard);
    expect(find.textContaining('Forked from Classic v1'), findsOneWidget);
    expect(find.text('USER COPY'), findsOneWidget);
  });
}
