import 'dart:ui' show Tristate;

import 'package:anode/editor/effect_panel.dart';
import 'package:anode/model/optical_profile.dart';
import 'package:anode/vfd/prism_widgets.dart';
import 'package:anode/vfd/vfd_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const palette = VfdPalette(lit: Color(0xFF4DFFB8), unlit: Color(0xFF73827B));

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

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PrismButton)),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      0.985,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(activations, 1);
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
