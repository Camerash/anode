import 'dart:ui' as ui;

import 'package:anode/editor/editor_chrome_skin.dart';
import 'package:anode/editor/editor_layout_specimen.dart';
import 'package:anode/model/optical_profile.dart';
import 'package:anode/vfd/prism_widgets.dart';
import 'package:anode/vfd/vfd_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const palette = VfdPalette(lit: Color(0xFF42F5B0), unlit: Color(0xFF587068));
  const skin = VfdEditorChromeSkin(palette: palette, prismStyle: PrismStyle());

  testWidgets('Specimen owns keyboard selection and selected semantics', (
    tester,
  ) async {
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 128,
            child: EditorLayoutSpecimen(
              key: const ValueKey('specimen'),
              skin: skin,
              aspect: 2.6,
              ratio: '2.600:1',
              semanticLabel: '2.600:1 layout, base',
              selected: selected,
              enabled: true,
              onSelected: () => selected = true,
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(selected, isTrue);
    expect(find.byType(PrismButton), findsNothing);
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('specimen')),
    );
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.flagsCollection.isEnabled, ui.Tristate.isTrue);
  });

  testWidgets('Disabled specimen remains visible and cannot activate', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 128,
            child: EditorLayoutSpecimen(
              key: const ValueKey('specimen'),
              skin: skin,
              aspect: 1,
              ratio: '1.000:1',
              semanticLabel: '1.000:1 layout',
              selected: false,
              enabled: false,
              onSelected: () => activations++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('specimen')));
    await tester.pump();

    expect(activations, 0);
    expect(find.text('1.000:1'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('specimen')))
          .flagsCollection
          .isEnabled,
      ui.Tristate.isFalse,
    );
  });
}
