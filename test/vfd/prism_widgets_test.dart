import 'dart:ui' show Tristate;

import 'package:anode/editor/effect_panel.dart';
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

  testWidgets('effect tile selects detail without changing strength', (
    tester,
  ) async {
    final profile = OpticalProfile(
      effects: <String, EffectSetting>{
        EffectIds.bloom: const EffectSetting(
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
          height: 1100,
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

    await tester.tap(find.byKey(const ValueKey('effect-bloom')));
    await tester.pump();
    expect(changes, 0);
    expect(find.text('0.72'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('effect-power-bloom')));
    await tester.pump();
    expect(changes, 1);
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

    await tester.tap(find.byKey(const ValueKey('effect-bloom')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('effect-override-bloom')));
    await tester.pump();

    expect(changed?.effects[EffectIds.bloom]?.strength, 1.27);
  });
}
