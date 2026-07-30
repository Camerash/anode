import 'package:anode/mechanical/mechanical_flip_tray.dart';
import 'package:anode/mechanical/mechanical_channel_drum.dart';
import 'package:anode/mechanical/mechanical_pager.dart';
import 'package:anode/mechanical/mechanical_push_drawer.dart';
import 'package:anode/model/optical_profile.dart';
import 'package:anode/vfd/prism_widgets.dart';
import 'package:anode/vfd/vfd_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const palette = VfdPalette(lit: Color(0xFF4DFFB8), unlit: Color(0xFF73827B));

  test('pagination keeps complete rows and partial final page', () {
    final pages = paginateCompleteRows(
      List<int>.generate(7, (index) => index),
      columns: 3,
      rows: 2,
    );
    expect(pages, <List<int>>[
      <int>[0, 1, 2, 3, 4, 5],
      <int>[6],
    ]);
  });

  testWidgets('rail crosses detents and exposes adjustable semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 240,
          child: MechanicalPager(
            pages: const <Widget>[Text('ONE'), Text('TWO'), Text('THREE')],
            palette: palette,
            prismStyle: const PrismStyle(),
            soundEnabled: false,
            hapticsEnabled: false,
          ),
        ),
      ),
    );

    final rail = find.byKey(const ValueKey('pager-detent-rail'));
    final semantics = tester.getSemantics(rail);
    expect(semantics.flagsCollection.isSlider, isTrue);
    expect(semantics.value, '1 of 3');

    final gesture = await tester.startGesture(
      tester.getRect(rail).bottomCenter - const Offset(0, 2),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('THREE'), findsOneWidget);
    expect(tester.getSemantics(rail).value, '3 of 3');
  });

  testWidgets('pager feedback obeys sound and haptic preferences', (
    tester,
  ) async {
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

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 240,
          child: MechanicalPager(
            pages: const <Widget>[Text('ONE'), Text('TWO')],
            palette: palette,
            prismStyle: const PrismStyle(),
            soundEnabled: false,
            hapticsEnabled: false,
          ),
        ),
      ),
    );
    calls.clear();
    await tester.tap(find.byKey(const ValueKey('pager-next')));
    expect(calls, isEmpty);
  });

  testWidgets('flip tray keeps surrounding layout fixed', (tester) async {
    var open = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Column(
              children: <Widget>[
                const SizedBox(key: ValueKey('before'), height: 20),
                MechanicalFlipTray(
                  open: open,
                  height: 140,
                  palette: palette,
                  soundEnabled: false,
                  hapticsEnabled: false,
                  child: const Text('DETAIL'),
                ),
                const SizedBox(key: ValueKey('after'), height: 20),
              ],
            );
          },
        ),
      ),
    );

    final before = tester.getTopLeft(find.byKey(const ValueKey('after')));
    rebuild(() => open = true);
    await tester.pump(const Duration(milliseconds: 150));
    final after = tester.getTopLeft(find.byKey(const ValueKey('after')));
    expect(after, before);
    expect(find.text('DETAIL'), findsOneWidget);
  });

  testWidgets('reduced motion resolves tray state immediately', (tester) async {
    var open = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MechanicalFlipTray(
                open: open,
                height: 140,
                palette: palette,
                soundEnabled: false,
                hapticsEnabled: false,
                child: const Text('DETAIL'),
              );
            },
          ),
        ),
      ),
    );

    rebuild(() => open = true);
    await tester.pump();
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
  });

  testWidgets('collapsing tray occupies zero height while closed', (
    tester,
  ) async {
    var open = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Column(
              children: <Widget>[
                MechanicalFlipTray(
                  open: open,
                  height: 140,
                  collapseWhenClosed: true,
                  palette: palette,
                  soundEnabled: false,
                  hapticsEnabled: false,
                  child: const Text('DETAIL'),
                ),
                const SizedBox(key: ValueKey('after-collapsed'), height: 20),
              ],
            );
          },
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(const ValueKey('after-collapsed'))).dy,
      0,
    );
    rebuild(() => open = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('after-collapsed'))).dy,
      140,
    );
  });

  testWidgets('push drawer consumes right-side workspace when open', (
    tester,
  ) async {
    var open = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 500,
            height: 300,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return MechanicalPushDrawer(
                  open: open,
                  edge: MechanicalDrawerEdge.right,
                  extent: 180,
                  palette: palette,
                  prismStyle: const PrismStyle(),
                  soundEnabled: false,
                  hapticsEnabled: false,
                  onOpenChanged: (value) => rebuild(() => open = value),
                  content: const SizedBox(key: ValueKey('drawer-content')),
                  drawer: const Text('DRAWER'),
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('drawer-content'))).width,
      500,
    );
    expect(find.text('PANEL'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mechanical-drawer-latch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final latch = tester.widget<PrismButton>(
      find.byKey(const ValueKey('mechanical-drawer-latch')),
    );
    expect(latch.label, 'Panel');
    expect(latch.lit, isTrue);
    expect(
      tester.getSize(find.byKey(const ValueKey('drawer-content'))).width,
      320,
    );
  });

  testWidgets('segmented bar snaps values and exposes slider semantics', (
    tester,
  ) async {
    double? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: VfdCellBar(
              value: 0.5,
              min: 0,
              max: 2,
              step: 0.1,
              precision: 1,
              semanticLabel: 'Bloom strength',
              palette: palette,
              onChanged: (value) => changed = value,
            ),
          ),
        ),
      ),
    );

    final bar = find.byType(VfdCellBar);
    final rect = tester.getRect(bar);
    await tester.tapAt(Offset(rect.left + rect.width * 0.36, rect.center.dy));
    expect(changed, closeTo(0.7, 1e-9));
    expect(tester.getSemantics(bar).flagsCollection.isSlider, isTrue);
  });

  testWidgets('channel drum exposes neighbours and hard indexed steps', (
    tester,
  ) async {
    var index = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, rebuild) => MechanicalChannelDrum(
            labels: const <String>['EMISSION', 'BLOOM', 'GRID'],
            index: index,
            palette: palette,
            prismStyle: const PrismStyle(),
            soundEnabled: false,
            hapticsEnabled: false,
            onChanged: (value) => rebuild(() => index = value),
          ),
        ),
      ),
    );

    expect(find.text('EMISSION'), findsOneWidget);
    expect(find.text('BLOOM'), findsOneWidget);
    expect(find.text('GRID'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('service-effect-next')));
    await tester.pump();
    expect(index, 2);
    expect(
      tester
          .widget<PrismButton>(
            find.byKey(const ValueKey('service-effect-next')),
          )
          .enabled,
      isFalse,
    );
  });
}
