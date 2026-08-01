import 'dart:ui' show Tristate;

import 'package:anode/editor/effect_pictogram.dart';
import 'package:anode/editor/effect_panel.dart';
import 'package:anode/mechanical/mechanical_lever.dart';
import 'package:anode/model/optical_profile.dart';
import 'package:anode/vfd/prism_glyphs.dart';
import 'package:anode/vfd/prism_widgets.dart';
import 'package:anode/vfd/vfd_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const palette = VfdPalette(lit: Color(0xFF4DFFB8), unlit: Color(0xFF73827B));

  setUpAll(() async {
    final loader = FontLoader('Barlow Condensed')
      ..addFont(
        rootBundle.load('assets/fonts/BarlowCondensed-MediumItalic.ttf'),
      );
    await loader.load();
  });

  test('Prism glyph codec preserves ASCII and degrades safely', () {
    expect(PrismGlyphs.displayText('Play/Pause 50%'), 'PLAY/PAUSE 50%');
    expect(PrismGlyphs.displayText('café 🔊'), 'CAF? ?');
    expect(
      PrismGlyphs.displayText('abcdefghijklmnopqrstuvwxyz12345'),
      'ABCDEFGHIJKLMNOPQRSTU...',
    );
    expect(
      PrismGlyphs.encode('A').single,
      PrismGlyphs.characters.indexOf('A') / (PrismGlyphs.characters.length - 1),
    );
  });

  test('Prism redo geometry mirrors undo exactly', () {
    const size = Size(24, 18);
    final undo = PrismSymbolGeometry.path(PrismSymbol.undo, size);
    final redo = PrismSymbolGeometry.path(PrismSymbol.redo, size);

    for (var row = 0; row < 36; row++) {
      for (var column = 0; column < 48; column++) {
        final point = Offset(
          (column + 0.5) * size.width / 48,
          (row + 0.5) * size.height / 36,
        );
        final mirrored = Offset(size.width - point.dx, point.dy);
        expect(redo.contains(mirrored), undo.contains(point));
      }
    }
  });

  testWidgets('Prism symbols hide text and retain command semantics', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PrismButton(
            key: const ValueKey('symbol-button'),
            label: 'Undo',
            symbol: PrismSymbol.undo,
            palette: palette,
            soundEnabled: false,
            hapticsEnabled: false,
            onPressed: () => activations++,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('prism-symbol-undo')), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
    expect(find.text('UNDO'), findsNothing);
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('symbol-button')),
    );
    expect(semantics.label, 'Undo');
    expect(semantics.flagsCollection.isEnabled, Tristate.isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('symbol-button')));
    expect(activations, 2);
  });

  testWidgets('Prism button exposes toggle semantics and depth press', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PrismButton(
            label: 'Bloom',
            value: '0.72',
            palette: palette,
            lit: true,
            selected: true,
            soundEnabled: false,
            hapticsEnabled: false,
            onPressed: () => activations++,
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.byType(PrismButton));
    expect(semantics.flagsCollection.isToggled, Tristate.isTrue);
    expect(semantics.flagsCollection.isSelected, Tristate.isTrue);

    final housing = find.byKey(const ValueKey('prism-housing'));
    final cap = find.byKey(const ValueKey('prism-cap'));
    final housingBefore = tester.getTopLeft(housing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PrismButton)),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getTopLeft(housing), housingBefore);
    expect(tester.widget<AnimatedSlide>(cap).offset.dy, 0.07);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(activations, 1);
  });

  testWidgets('Prism spans use fixed physical modules', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final span in PrismSpan.values)
              PrismButton(
                key: ValueKey(span),
                label: span.name,
                palette: palette,
                role: PrismRole.compact,
                span: span,
                soundEnabled: false,
                hapticsEnabled: false,
                onPressed: () {},
              ),
          ],
        ),
      ),
    );

    final widths = <double>[
      for (final span in PrismSpan.values)
        tester.getSize(find.byKey(ValueKey(span))).width,
    ];
    expect(widths[0], PrismMetrics.width(PrismRole.compact, PrismSpan.one));
    expect(widths[1], PrismMetrics.width(PrismRole.compact, PrismSpan.two));
    expect(widths[2], PrismMetrics.width(PrismRole.compact, PrismSpan.three));
    expect(widths[0], lessThan(widths[1]));
    expect(widths[1], lessThan(widths[2]));
  });

  testWidgets(
    'selection, light, keyboard focus, and disabled stay independent',
    (tester) async {
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: PrismButton(
              label: 'Reset',
              palette: palette,
              lit: true,
              selected: false,
              soundEnabled: false,
              hapticsEnabled: false,
              onPressed: () => activations++,
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(PrismButton));
      expect(semantics.flagsCollection.isToggled, Tristate.isTrue);
      expect(semantics.flagsCollection.isSelected, Tristate.isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(activations, 1);

      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: PrismButton(
              label: 'Reset',
              palette: palette,
              enabled: false,
              soundEnabled: false,
              hapticsEnabled: false,
              onPressed: null,
            ),
          ),
        ),
      );
      final disabled = tester.getSemantics(find.byType(PrismButton));
      expect(disabled.flagsCollection.isEnabled, Tristate.isFalse);
      await tester.tap(find.byType(PrismButton));
      expect(activations, 1);
    },
  );

  testWidgets('reduced motion makes cap travel immediate', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Center(
            child: PrismButton(
              label: 'Reset',
              palette: palette,
              soundEnabled: false,
              hapticsEnabled: false,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PrismButton)),
    );
    await tester.pump();
    expect(
      tester
          .widget<AnimatedSlide>(find.byKey(const ValueKey('prism-cap')))
          .duration,
      Duration.zero,
    );
    await gesture.up();
  });

  testWidgets('sound and haptics obey app preferences', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    Future<void> pumpButton({required bool sound, required bool haptics}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: PrismButton(
                label: 'Reset',
                palette: palette,
                soundEnabled: sound,
                hapticsEnabled: haptics,
                onPressed: () {},
              ),
            ),
          ),
        );

    await pumpButton(sound: false, haptics: false);
    calls.clear();
    await tester.tap(find.byType(PrismButton));
    expect(calls, isEmpty);

    await pumpButton(sound: true, haptics: true);
    calls.clear();
    await tester.tap(find.byType(PrismButton));
    expect(calls.map((call) => call.method), <String>[
      'SystemSound.play',
      'HapticFeedback.vibrate',
    ]);
  });

  testWidgets('Prism switchgear state matrix matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 250));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ColoredBox(
          color: const Color(0xFF090D0C),
          child: Center(
            child: RepaintBoundary(
              key: const ValueKey('prism-golden'),
              child: Wrap(
                spacing: 12,
                runSpacing: 14,
                children: <Widget>[
                  PrismButton(
                    label: 'E/M',
                    palette: palette,
                    soundEnabled: false,
                    hapticsEnabled: false,
                    onPressed: () {},
                  ),
                  PrismButton(
                    label: 'Reset',
                    palette: palette,
                    lit: true,
                    soundEnabled: false,
                    hapticsEnabled: false,
                    onPressed: () {},
                  ),
                  PrismButton(
                    key: const ValueKey('pressed-prism'),
                    label: 'Set',
                    palette: palette,
                    lit: true,
                    selected: true,
                    soundEnabled: false,
                    hapticsEnabled: false,
                    onPressed: () {},
                  ),
                  const PrismButton(
                    label: 'Disabled',
                    palette: palette,
                    enabled: false,
                    onPressed: null,
                  ),
                  PrismButton(
                    label: 'Bloom',
                    value: '0.72',
                    palette: palette,
                    lit: true,
                    span: PrismSpan.two,
                    soundEnabled: false,
                    hapticsEnabled: false,
                    onPressed: () {},
                  ),
                  PrismButton(
                    label: 'Library',
                    palette: palette,
                    span: PrismSpan.three,
                    soundEnabled: false,
                    hapticsEnabled: false,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('pressed-prism'))),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await expectLater(
      find.byKey(const ValueKey('prism-golden')),
      matchesGoldenFile('goldens/prism_switchgear.png'),
    );
    await gesture.up();
  });

  testWidgets('LOOK fascia exposes only phosphor and TUNE', (tester) async {
    final profile = OpticalProfile(
      effects: <String, EffectSetting>{
        EffectIds.emission: const EffectSetting(
          strength: 0.72,
          resumeStrength: 0.72,
        ),
      },
    );
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 700,
          height: 500,
          child: EffectPanel(
            title: 'Design effects',
            dashboardProfile: profile,
            baseProfile: profile,
            scope: EffectScope.dashboard,
            prismStyle: const PrismStyle(),
            soundEnabled: false,
            hapticsEnabled: false,
            onProfileChanged: (_) => changes++,
          ),
        ),
      ),
    );

    final footprint = tester.getSize(
      find.byKey(const ValueKey('mechanical-service-hatch')),
    );
    expect(find.byKey(const ValueKey('look-phosphor')), findsOneWidget);
    expect(find.byKey(const ValueKey('look-tune')), findsOneWidget);
    expect(find.byType(EffectPictogram), findsNothing);
    expect(find.byType(MechanicalLever), findsNothing);
    expect(find.byKey(const ValueKey('pager-detent-rail')), findsNothing);
    expect(find.text('0.72'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('look-tune')));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('mechanical-service-hatch'))),
      footprint,
    );
    expect(changes, 0);
    expect(find.textContaining('EMISSION'), findsOneWidget);
    expect(find.text('0.72'), findsOneWidget);
    expect(find.byType(EffectPictogram), findsOneWidget);
    expect(find.byType(MechanicalLever), findsOneWidget);
    expect(find.byKey(const ValueKey('pager-detent-rail')), findsNothing);
  });

  testWidgets('service lever writes only visible detent values', (
    tester,
  ) async {
    final profile = OpticalProfile(
      effects: <String, EffectSetting>{
        EffectIds.emission: const EffectSetting(
          strength: 0.72,
          resumeStrength: 0.72,
        ),
      },
    );
    final strengths = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 700,
          height: 500,
          child: EffectPanel(
            title: 'Design effects',
            dashboardProfile: profile,
            baseProfile: profile,
            scope: EffectScope.dashboard,
            prismStyle: const PrismStyle(),
            soundEnabled: false,
            hapticsEnabled: false,
            onProfileChanged: (value) =>
                strengths.add(value.effect(EffectIds.emission).strength),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('look-tune')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.descendant(
        of: find.byKey(const ValueKey('effect-lever-emission')),
        matching: find.byKey(const ValueKey('mechanical-lever-thumb')),
      ),
      const Offset(40, 0),
    );
    await tester.pump();

    expect(strengths, isNotEmpty);
    expect(
      strengths.every((value) => value * 10 == (value * 10).round()),
      isTrue,
    );
  });

  testWidgets('service channel uses hard stops and remembers its index', (
    tester,
  ) async {
    final profile = OpticalProfile();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 700,
          height: 500,
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

    await tester.tap(find.byKey(const ValueKey('look-tune')));
    await tester.pumpAndSettle();
    final previous = tester.widget<PrismButton>(
      find.byKey(const ValueKey('service-effect-previous')),
    );
    expect(previous.enabled, isFalse);

    await tester.tap(find.byKey(const ValueKey('service-effect-next')));
    await tester.pump();
    expect(find.textContaining('BLOOM'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('service-hatch-close')));
    await tester.pumpAndSettle();
    expect(find.byType(MechanicalLever), findsNothing);
    await tester.tap(find.byKey(const ValueKey('look-tune')));
    await tester.pumpAndSettle();
    expect(find.textContaining('BLOOM'), findsOneWidget);
  });

  testWidgets('unknown stored effect remains indexed and read-only', (
    tester,
  ) async {
    final profile = OpticalProfile(
      effects: <String, EffectSetting>{
        'futureScatter': const EffectSetting(
          strength: 1.23,
          resumeStrength: 1.23,
        ),
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 700,
          height: 500,
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

    await tester.tap(find.byKey(const ValueKey('look-tune')));
    await tester.pumpAndSettle();
    for (
      var index = 0;
      index < EffectSpecs.forScope(EffectScope.dashboard).length;
      index++
    ) {
      await tester.tap(find.byKey(const ValueKey('service-effect-next')));
      await tester.pump();
    }

    final lever = find.byKey(const ValueKey('effect-lever-futureScatter'));
    expect(lever, findsOneWidget);
    expect(find.text('1.23'), findsOneWidget);
    expect(
      tester.getSemantics(lever).flagsCollection.isEnabled,
      Tristate.isFalse,
    );
  });

  testWidgets('local effect starts inherited and seeds override on demand', (
    tester,
  ) async {
    final profile = OpticalProfile(
      effects: <String, EffectSetting>{
        EffectIds.bloom: const EffectSetting(
          strength: 1.27,
          resumeStrength: 1.27,
        ),
      },
    );
    OpticalOverrides? changed;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 700,
          height: 1100,
          child: EffectPanel(
            title: 'Local effects',
            dashboardProfile: profile,
            baseProfile: profile,
            overrides: OpticalOverrides(),
            scope: EffectScope.component,
            prismStyle: const PrismStyle(),
            soundEnabled: false,
            hapticsEnabled: false,
            onOverridesChanged: (value) => changed = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('look-tune')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('service-effect-next')));
    await tester.pump();
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('effect-lever-bloom')))
          .flagsCollection
          .isEnabled,
      Tristate.isFalse,
    );
    expect(
      tester
          .widget<PrismButton>(
            find.byKey(const ValueKey('effect-override-bloom')),
          )
          .label,
      'Override',
    );
    await tester.tap(find.byKey(const ValueKey('effect-override-bloom')));
    await tester.pump();

    expect(changed?.effects[EffectIds.bloom]?.strength, 1.27);
  });

  testWidgets('phosphor hard-cut changes profile live', (tester) async {
    final profile = OpticalProfile();
    OpticalProfile? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 700,
          height: 500,
          child: EffectPanel(
            title: 'Design effects',
            dashboardProfile: profile,
            baseProfile: profile,
            scope: EffectScope.dashboard,
            prismStyle: const PrismStyle(),
            soundEnabled: false,
            hapticsEnabled: false,
            onProfileChanged: (value) => changed = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('look-phosphor')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('phosphor-Red')));
    await tester.pump();
    expect(changed?.phosphorName, 'Red');
  });

  testWidgets('local service face fits minimum side-bay footprint', (
    tester,
  ) async {
    final profile = OpticalProfile();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 280,
            height: 150,
            child: EffectPanel(
              title: 'Speed digits · Local effects',
              dashboardProfile: profile,
              baseProfile: profile,
              overrides: OpticalOverrides(),
              scope: EffectScope.component,
              prismStyle: const PrismStyle(),
              soundEnabled: false,
              hapticsEnabled: false,
              onOverridesChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('look-tune')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(MechanicalLever), findsOneWidget);
  });
}
