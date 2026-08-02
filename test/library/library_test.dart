import 'package:anode/app_state.dart';
import 'package:anode/data/design_repository.dart';
import 'package:anode/library/library_page.dart';
import 'package:anode/model/design_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/fixtures.dart';

void main() {
  testWidgets('template clone prompts for a name and opens dashboard editor', (
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

    expect(find.text('EDIT'), findsNothing);
    await tester.tap(find.text('CLONE'));
    await tester.pumpAndSettle();

    expect(find.text('CLONE CLASSIC?'), findsOneWidget);
    expect(state.dashboards, isEmpty);

    await tester.tap(find.text('CLONE'));
    await tester.pumpAndSettle();

    expect(state.dashboards, hasLength(1));
    expect(state.activeReference.kind, DesignKind.dashboard);
    expect(state.dashboards.single.name, 'Classic copy');
    expect(find.text('CLASSIC COPY'), findsOneWidget);
    expect(find.textContaining('FORKED FROM'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('user design exposes edit and clone actions', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final source = preset();
    final repository = DesignRepository(await SharedPreferences.getInstance());
    final state = AnodeState.load(
      repository: repository,
      presets: <DesignPreset>[source],
    );
    addTearDown(state.dispose);
    state.forkPreset(source, name: 'My design');
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryPage(state: state, initialSection: LibrarySection.designs),
      ),
    );

    expect(find.text('EDIT'), findsOneWidget);
    expect(find.text('CLONE'), findsOneWidget);
    await tester.tap(find.text('EDIT'));
    await tester.pumpAndSettle();
    expect(find.text('MY DESIGN'), findsOneWidget);
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

  testWidgets('Library surfaces bleed while production chrome stays safe', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const viewport = Size(874, 402);
    const safeInsets = EdgeInsets.fromLTRB(59, 0, 113, 21);
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AnodeState.load(
      repository: DesignRepository(await SharedPreferences.getInstance()),
      presets: <DesignPreset>[preset()],
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: viewport,
            padding: safeInsets,
            viewPadding: safeInsets,
          ),
          child: LibraryPage(state: state),
        ),
      ),
    );

    expect(
      tester.getRect(find.byKey(const ValueKey('library-header-surface'))),
      const Rect.fromLTWH(0, 0, 874, 48),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('library-back'))).left,
      greaterThanOrEqualTo(safeInsets.left),
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('library-section-selector')))
          .right,
      lessThanOrEqualTo(viewport.width - safeInsets.right),
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('library-content-environment')))
          .right,
      viewport.width,
    );
    expect(
      tester
          .getRect(find.byKey(const ValueKey('library-content-environment')))
          .bottom,
      viewport.height,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('library-safe-content'))).right,
      lessThanOrEqualTo(viewport.width - safeInsets.right),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('library-safe-content'))).bottom,
      lessThanOrEqualTo(viewport.height - safeInsets.bottom),
    );

    await tester.tap(find.text('SETTINGS'));
    await tester.pump();
    expect(
      tester.getRect(find.byKey(const ValueKey('library-safe-content'))).left,
      greaterThanOrEqualTo(safeInsets.left),
    );
  });

  testWidgets('clone prompt background bleeds and dialog remains safe', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const viewport = Size(393, 852);
    const safeInsets = EdgeInsets.fromLTRB(0, 59, 0, 34);
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AnodeState.load(
      repository: DesignRepository(await SharedPreferences.getInstance()),
      presets: <DesignPreset>[preset()],
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: viewport,
            padding: safeInsets,
            viewPadding: safeInsets,
          ),
          child: LibraryPage(state: state),
        ),
      ),
    );
    await tester.tap(find.text('CLONE'));
    await tester.pumpAndSettle();

    final environment = tester.getRect(
      find.byKey(const ValueKey('clone-prompt-environment')),
    );
    final dialog = tester.getRect(
      find.byKey(const ValueKey('clone-prompt-safe-content')),
    );
    expect(environment, Rect.fromLTWH(0, 0, viewport.width, viewport.height));
    expect(dialog.left, greaterThanOrEqualTo(safeInsets.left));
    expect(dialog.top, greaterThanOrEqualTo(safeInsets.top));
    expect(dialog.right, lessThanOrEqualTo(viewport.width - safeInsets.right));
    expect(
      dialog.bottom,
      lessThanOrEqualTo(viewport.height - safeInsets.bottom),
    );
  });
}
