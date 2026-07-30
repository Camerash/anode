import 'package:anode/mechanical/mechanical_service_hatch.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('service face replaces fascia without changing footprint', (
    tester,
  ) async {
    Widget harness(bool open) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 320,
          height: 180,
          child: MechanicalServiceHatch(
            open: open,
            soundEnabled: false,
            hapticsEnabled: false,
            front: Semantics(
              label: 'Normal fascia',
              child: const ColoredBox(color: Color(0xFF090D0C)),
            ),
            service: Semantics(
              label: 'Service face',
              child: const ColoredBox(color: Color(0xFF050706)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(harness(false));

    final hatch = find.byKey(const ValueKey('mechanical-service-hatch'));
    final footprint = tester.getSize(hatch);
    expect(find.bySemanticsLabel('Normal fascia'), findsOneWidget);
    expect(find.bySemanticsLabel('Service face'), findsNothing);

    await tester.pumpWidget(harness(true));
    await tester.pumpAndSettle();

    expect(tester.getSize(hatch), footprint);
    expect(find.bySemanticsLabel('Service face'), findsOneWidget);
  });

  testWidgets('reduced motion seats hatch immediately', (tester) async {
    Widget harness(bool open) => MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 320,
            height: 180,
            child: MechanicalServiceHatch(
              open: open,
              soundEnabled: false,
              hapticsEnabled: false,
              front: const SizedBox.expand(),
              service: Semantics(
                label: 'Service face',
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(harness(false));
    await tester.pumpWidget(harness(true));

    expect(find.bySemanticsLabel('Service face'), findsOneWidget);
  });
}
