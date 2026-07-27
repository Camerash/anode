import 'dart:ui' as ui;

import 'package:anode/model/component_instance.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/placement.dart';
import 'package:anode/vfd/vfd_cluster.dart';
import 'package:anode/vfd/vfd_layers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The acceptance test for the single-pass renderer.
///
/// Two emissive components are placed adjacent with a gap between them. Their
/// halos must compound across the boundary: the gap must be brighter with both
/// components lit than with either alone, and the luminance profile across the
/// boundary must be smooth.
///
/// A seam here would mean something reintroduced a per-component raster
/// surface. That is an architectural failure, not something to work around.
///
/// Runs on a device because fragment shaders do not render in the headless
/// test environment.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // One design unit is 300px in the 780x300 frame below, so these place the
  // bars' inner edges 0.12 design units either side of centre — 36px. Close
  // enough that the halos overlap measurably, far enough that the middle of the
  // gap contains halo only and none of the bars' own cell edges, which are
  // legitimately sharp and would swamp a smoothness measurement.
  const double barOffset = 0.57;
  const double barWidth = 0.9;
  const double designUnitPx = 300;
  const int gapHalfPx = 25;

  /// Two bars either side of the origin.
  Dashboard dashboardWith({required bool left, required bool right}) {
    Placement place(double cx) =>
        Placement(offset: Offset(cx, 0), size: const Size(barWidth, 0.084));

    return Dashboard(
      id: 'halo',
      name: 'Halo',
      supportedOrientations: <DesignOrientation>{DesignOrientation.landscape},
      components: <ComponentInstance>[
        if (left)
          ComponentInstance(
            id: 'left',
            typeId: ComponentTypes.speedBar,
            params: const <String, Object?>{'cells': 9, 'maxKph': 100.0},
            placements: <DesignOrientation, Placement>{
              DesignOrientation.landscape: place(-barOffset),
            },
          ),
        if (right)
          ComponentInstance(
            id: 'right',
            typeId: ComponentTypes.speedBar,
            params: const <String, Object?>{'cells': 9, 'maxKph': 100.0},
            placements: <DesignOrientation, Placement>{
              DesignOrientation.landscape: place(barOffset),
            },
          ),
      ],
    );
  }

  late ui.FragmentProgram program;

  setUpAll(() async {
    program = await ui.FragmentProgram.fromAsset('shaders/vfd.frag');
  });

  /// Renders one configuration and returns the luminance profile along the
  /// horizontal centre line of the bars.
  Future<List<double>> profile(
    WidgetTester tester, {
    required bool left,
    required bool right,
  }) async {
    final key = GlobalKey();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(780, 300)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 780,
                height: 300,
                child: _Harness(
                  program: program,
                  dashboard: dashboardWith(left: left, right: right),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Let the ticker run so the controller builds its data texture, and settle
    // the phosphor ramp so brightness is at its target.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final pixels = data.buffer.asUint8List();

    final width = image.width;
    final row = image.height ~/ 2;
    final out = <double>[];
    for (var x = 0; x < width; x++) {
      final o = (row * width + x) * 4;
      // Rec. 709 luma; the phosphor is cyan-green so green dominates.
      out.add(0.2126 * pixels[o] +
          0.7152 * pixels[o + 1] +
          0.0722 * pixels[o + 2]);
    }
    image.dispose();
    return out;
  }

  testWidgets('halos compound across a component boundary with no seam',
      (tester) async {
    final leftOnly = await profile(tester, left: true, right: false);
    final rightOnly = await profile(tester, left: false, right: true);
    final both = await profile(tester, left: true, right: true);

    final width = both.length;
    final centre = width ~/ 2;

    // The gap sits at the design origin, which is the centre of the frame.
    final gapLeftOnly = leftOnly[centre];
    final gapRightOnly = rightOnly[centre];
    final gapBoth = both[centre];

    // Each component alone must actually reach the gap, or there is no
    // compounding to measure and the test would pass vacuously.
    final substrate = both[2];
    expect(gapLeftOnly, greaterThan(substrate),
        reason: 'left component halo does not reach the boundary');
    expect(gapRightOnly, greaterThan(substrate),
        reason: 'right component halo does not reach the boundary');

    // The compounding itself: both lit must exceed either alone. Additive
    // accumulation through a compressive tonemap is sub-linear, so this checks
    // the direction and a real margin rather than an exact sum.
    expect(gapBoth, greaterThan(gapLeftOnly),
        reason: 'halos did not compound across the boundary');
    expect(gapBoth, greaterThan(gapRightOnly),
        reason: 'halos did not compound across the boundary');

    final lift = gapBoth - (gapLeftOnly > gapRightOnly ? gapLeftOnly : gapRightOnly);
    expect(lift, greaterThan(1.0),
        reason: 'compounding was too small to be a real accumulation');

    // No seam: inside the gap the profile is halo only, and halo is smooth. A
    // per-component raster surface would clip one component's halo at its own
    // bounds, which shows up here as a step.
    //
    // The window stops short of the bars' inner edges. Those edges are real
    // geometry and legitimately sharp; including them measures the segment
    // edge, not the boundary between components.
    final innerEdgePx =
        ((barOffset - barWidth / 2) * designUnitPx).round();
    expect(gapHalfPx, lessThan(innerEdgePx),
        reason: 'the smoothness window must stay inside the gap');

    var maxJump = 0.0;
    for (var x = centre - gapHalfPx; x < centre + gapHalfPx; x++) {
      final jump = (both[x + 1] - both[x]).abs();
      if (jump > maxJump) maxJump = jump;
    }

    final range = both.reduce((a, b) => a > b ? a : b) - substrate;
    expect(maxJump, lessThan(range * 0.02),
        reason: 'discontinuity inside the gap: a seam. '
            'Something reintroduced a per-component raster surface.');
  });
}

class _Harness extends StatefulWidget {
  const _Harness({required this.program, required this.dashboard});

  final ui.FragmentProgram program;
  final Dashboard dashboard;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with SingleTickerProviderStateMixin {
  late final VfdController _controller = VfdController(
    vsync: this,
    dashboard: widget.dashboard,
  )
    // Both bars fully lit, and the optical layers that would add noise to a
    // luminance profile turned off.
    ..speedKph = 100
    ..layers = const VfdLayers(grain: false, tiltParallax: false);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VfdCluster(
        program: widget.program,
        controller: _controller,
        safeInsets: EdgeInsets.zero,
      );
}
