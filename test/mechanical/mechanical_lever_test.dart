import 'dart:ui' show SemanticsAction, Tristate;

import 'package:anode/mechanical/mechanical_lever.dart';
import 'package:anode/model/optical_profile.dart';
import 'package:anode/vfd/vfd_widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const palette = VfdPalette(lit: Color(0xFF4DFFB8), unlit: Color(0xFF73827B));

  Future<_LeverHarness> pumpLever(
    WidgetTester tester, {
    double initial = 0.72,
    ValueChanged<double>? observe,
    bool enabled = true,
  }) async {
    final harness = _LeverHarness(initial);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            child: StatefulBuilder(
              builder: (context, setState) => MechanicalLever(
                label: 'Bloom strength',
                value: harness.value,
                min: 0,
                max: 2,
                referenceValue: 1,
                offAtMinimum: true,
                palette: palette,
                prismStyle: const PrismStyle(),
                soundEnabled: false,
                hapticsEnabled: false,
                onChanged: enabled
                    ? (value) {
                        observe?.call(value);
                        setState(() => harness.value = value);
                      }
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
    return harness;
  }

  testWidgets('track taps cannot teleport physical thumb', (tester) async {
    final harness = await pumpLever(tester);
    final lever = find.byKey(const ValueKey('mechanical-lever'));
    final rect = tester.getRect(lever);

    await tester.tapAt(Offset(rect.right - 24, rect.center.dy));
    await tester.pump();

    expect(harness.value, 0.72);
  });

  testWidgets('thumb drag lands only on visible detents and reaches OFF', (
    tester,
  ) async {
    final changes = <double>[];
    final harness = await pumpLever(tester, observe: changes.add);
    final thumb = find.byKey(const ValueKey('mechanical-lever-thumb'));
    final lever = tester.getRect(
      find.byKey(const ValueKey('mechanical-lever')),
    );

    await tester.dragFrom(
      tester.getCenter(thumb),
      Offset(-lever.width, 0),
      touchSlopX: 0,
    );
    await tester.pump();

    expect(harness.value, 0);
    expect(
      changes.every((value) => value * 10 == (value * 10).round()),
      isTrue,
    );
    expect(find.text('OFF · 0.00'), findsOneWidget);
  });

  testWidgets('semantics, keyboard, and wheel move one physical detent', (
    tester,
  ) async {
    final harness = await pumpLever(tester, initial: 1);
    final lever = find.byKey(const ValueKey('mechanical-lever'));
    final semantics = tester.getSemantics(lever);
    expect(semantics.flagsCollection.isSlider, isTrue);
    expect(semantics.value, '1.00');

    semantics.owner!.performAction(semantics.id, SemanticsAction.increase);
    await tester.pump();
    expect(harness.value, closeTo(1.1, 1e-9));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(harness.value, closeTo(1, 1e-9));

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(lever),
        scrollDelta: const Offset(0, -1),
      ),
    );
    await tester.pump();
    expect(harness.value, closeTo(1.1, 1e-9));
  });

  test('non-uniform tuned reference replaces nearest interior detent', () {
    final detents = mechanicalLeverDetents(
      min: 0.6,
      max: 0.95,
      count: 11,
      referenceValue: 0.78,
    );

    expect(detents, hasLength(11));
    expect(detents, contains(0.78));
    expect(detents.first, 0.6);
    expect(detents.last, 0.95);
    expect(detents, orderedEquals(detents.toList()..sort()));
  });

  testWidgets('disabled lever ignores direct and semantic input', (
    tester,
  ) async {
    final harness = await pumpLever(tester, enabled: false);
    final lever = find.byKey(const ValueKey('mechanical-lever'));
    final thumb = find.byKey(const ValueKey('mechanical-lever-thumb'));

    await tester.drag(thumb, const Offset(100, 0));
    await tester.pump();

    expect(harness.value, 0.72);
    expect(
      tester.getSemantics(lever).flagsCollection.isEnabled,
      Tristate.isFalse,
    );
  });
}

class _LeverHarness {
  _LeverHarness(this.value);
  double value;
}
