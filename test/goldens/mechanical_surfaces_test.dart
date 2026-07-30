import 'dart:ui' show SemanticsAction;

import 'package:anode/app_state.dart';
import 'package:anode/data/design_repository.dart';
import 'package:anode/editor/editor_page.dart';
import 'package:anode/editor/effect_panel.dart';
import 'package:anode/library/library_page.dart';
import 'package:anode/mechanical/mechanical_pager.dart';
import 'package:anode/mechanical/mechanical_lever.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/dev_design.dart';
import 'package:anode/model/optical_profile.dart';
import 'package:anode/vfd/vfd_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/fixtures.dart';

void main() {
  const palette = VfdPalette(lit: Color(0xFF4DFFB8), unlit: Color(0xFF73827B));

  setUpAll(() async {
    final loader = FontLoader('Barlow Condensed')
      ..addFont(
        rootBundle.load('assets/fonts/BarlowCondensed-MediumItalic.ttf'),
      );
    await loader.load();
  });

  testWidgets('editor closed and open baselines', (tester) async {
    await tester.binding.setSurfaceSize(const Size(874, 402));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const ValueKey('surface'),
          child: EditorPage(dashboard: dashboard, onChanged: (_) {}),
        ),
      ),
    );

    await expectLater(
      find.byKey(const ValueKey('surface')),
      matchesGoldenFile('baselines/editor_closed.png'),
    );
    await tester.tap(find.byKey(const ValueKey('mechanical-drawer-latch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await expectLater(
      find.byKey(const ValueKey('surface')),
      matchesGoldenFile('baselines/editor_open.png'),
    );
  });

  testWidgets('LOOK fascia and service hatch baselines', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final profile = OpticalProfile(
      effects: <String, EffectSetting>{
        EffectIds.bloom: const EffectSetting(
          strength: 0.72,
          resumeStrength: 0.72,
        ),
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const ValueKey('surface'),
          child: EffectPanel(
            title: 'Design effects',
            dashboardProfile: profile,
            baseProfile: profile,
            scope: EffectScope.dashboard,
            prismStyle: const PrismStyle(),
            soundEnabled: false,
            hapticsEnabled: false,
            onProfileChanged: (_) {},
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(const ValueKey('surface')),
      matchesGoldenFile('baselines/effect_closed.png'),
    );
    await tester.tap(find.byKey(const ValueKey('look-tune')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('surface')),
      matchesGoldenFile('baselines/effect_open.png'),
    );
  });

  testWidgets('automotive lever state baselines', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ColoredBox(
          color: const Color(0xFF050807),
          child: RepaintBoundary(
            key: const ValueKey('surface'),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: <Widget>[
                  MechanicalLever(
                    label: 'Off',
                    value: 0,
                    min: 0,
                    max: 2,
                    referenceValue: 1,
                    offAtMinimum: true,
                    palette: palette,
                    prismStyle: const PrismStyle(),
                    soundEnabled: false,
                    hapticsEnabled: false,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 6),
                  MechanicalLever(
                    label: 'Tuned',
                    value: 1,
                    min: 0,
                    max: 2,
                    referenceValue: 1,
                    palette: palette,
                    prismStyle: const PrismStyle(),
                    soundEnabled: false,
                    hapticsEnabled: false,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 6),
                  MechanicalLever(
                    label: 'Overdrive',
                    value: 2,
                    min: 0,
                    max: 2,
                    referenceValue: 1,
                    palette: palette,
                    prismStyle: const PrismStyle(),
                    soundEnabled: false,
                    hapticsEnabled: false,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 6),
                  const MechanicalLever(
                    label: 'Inherited',
                    value: 0.72,
                    min: 0,
                    max: 2,
                    referenceValue: 1,
                    palette: palette,
                    prismStyle: PrismStyle(),
                    onChanged: null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(const ValueKey('surface')),
      matchesGoldenFile('baselines/mechanical_levers.png'),
    );
  });

  testWidgets('Prism-style lever detail baseline', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const ValueKey('surface'),
          child: PrismStyleEditor(
            profile: OpticalProfile(),
            style: const PrismStyle(),
            soundEnabled: false,
            hapticsEnabled: false,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('depth')));
    await tester.pump();

    await expectLater(
      find.byKey(const ValueKey('surface')),
      matchesGoldenFile('baselines/prism_lever_detail.png'),
    );
  });

  testWidgets('editor PLACE and bottom-bay baselines', (tester) async {
    await tester.binding.setSurfaceSize(const Size(874, 402));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'editor');
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const ValueKey('surface'),
          child: EditorPage(dashboard: dashboard, onChanged: (_) {}),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('canvas-speed')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mechanical-drawer-latch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final sections = tester.getSemantics(
      find.bySemanticsLabel('Editor service section'),
    );
    sections.owner!.performAction(sections.id, SemanticsAction.increase);
    await tester.pump();
    await tester.tap(find.text('PLACE'));
    await tester.pump();
    await expectLater(
      find.byKey(const ValueKey('surface')),
      matchesGoldenFile('baselines/editor_place_right.png'),
    );

    await tester.binding.setSurfaceSize(const Size(393, 852));
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const ValueKey('surface'),
          child: EditorPage(
            key: const ValueKey('portrait-editor'),
            dashboard: dashboard,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('mechanical-drawer-latch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await expectLater(
      find.byKey(const ValueKey('surface')),
      matchesGoldenFile('baselines/editor_bay_bottom.png'),
    );
  });

  testWidgets('pager indexed state baseline', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ColoredBox(
          color: const Color(0xFF050807),
          child: RepaintBoundary(
            key: const ValueKey('surface'),
            child: MechanicalPager(
              pages: <Widget>[
                for (final label in <String>[
                  'PAGE ONE',
                  'PAGE TWO',
                  'PAGE THREE',
                ])
                  Center(
                    child: VfdLegend(
                      label,
                      palette: palette,
                      lit: true,
                      size: 18,
                    ),
                  ),
              ],
              palette: palette,
              prismStyle: const PrismStyle(),
              soundEnabled: false,
              hapticsEnabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pager-next')));
    await tester.pump(const Duration(milliseconds: 60));

    await expectLater(
      find.byKey(const ValueKey('surface')),
      matchesGoldenFile('baselines/pager_indexed.png'),
    );
  });

  testWidgets('Library and Settings baselines', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final state = AnodeState.load(
      repository: DesignRepository(await SharedPreferences.getInstance()),
      presets: [preset()],
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const ValueKey('surface'),
          child: LibraryPage(state: state),
        ),
      ),
    );

    await expectLater(
      find.byKey(const ValueKey('surface')),
      matchesGoldenFile('baselines/library.png'),
    );
    await tester.tap(find.text('SETTINGS'));
    await tester.pump();
    await expectLater(
      find.byKey(const ValueKey('surface')),
      matchesGoldenFile('baselines/settings.png'),
    );
  });
}
