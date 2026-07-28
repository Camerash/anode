import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:anode/model/component_instance.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/optical_profile.dart';
import 'package:anode/model/placement.dart';
import 'package:anode/model/settings.dart';
import 'package:anode/model/vfd_module.dart';
import 'package:anode/vfd/vfd_cluster.dart';
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
      settings: DashboardSettings(
        opticalProfile: OpticalProfile(
          effects: <String, EffectSetting>{
            EffectIds.glassGrain: const EffectSetting(
              strength: 0,
              resumeStrength: 1,
            ),
            EffectIds.tiltParallax: const EffectSetting(
              strength: 0,
              resumeStrength: 1,
            ),
          },
        ),
      ),
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
            child: OverflowBox(
              minWidth: 780,
              maxWidth: 780,
              minHeight: 300,
              maxHeight: 300,
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
      out.add(
        0.2126 * pixels[o] + 0.7152 * pixels[o + 1] + 0.0722 * pixels[o + 2],
      );
    }
    image.dispose();
    return out;
  }

  Future<({Uint8List pixels, int width, int height})> capture(
    WidgetTester tester,
    Dashboard dashboard, {
    String? pressedComponentId,
  }) async {
    final boundaryKey = GlobalKey();
    final harnessKey = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(780, 300)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: OverflowBox(
              minWidth: 780,
              maxWidth: 780,
              minHeight: 300,
              maxHeight: 300,
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(
                  width: 780,
                  height: 300,
                  child: _Harness(
                    key: harnessKey,
                    program: program,
                    dashboard: dashboard,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    if (pressedComponentId != null) {
      harnessKey.currentState!.setPressed(pressedComponentId, true);
      await tester.pump(const Duration(milliseconds: 32));
    }

    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final result = (
      pixels: Uint8List.fromList(data.buffer.asUint8List()),
      width: image.width,
      height: image.height,
    );
    image.dispose();
    return result;
  }

  Dashboard colouredBars({
    required bool left,
    required bool right,
    String leftColour = 'Red',
    String rightColour = 'Cyan-green',
  }) => Dashboard(
    id: 'colours',
    name: 'Colours',
    supportedOrientations: <DesignOrientation>{DesignOrientation.landscape},
    components: <ComponentInstance>[
      if (left)
        ComponentInstance(
          id: 'left',
          typeId: ComponentTypes.speedBar,
          params: const <String, Object?>{'cells': 9, 'maxKph': 100.0},
          placements: const <DesignOrientation, Placement>{
            DesignOrientation.landscape: Placement(
              offset: Offset(-0.57, 0),
              size: Size(0.9, 0.084),
            ),
          },
          opticalOverrides: OpticalOverrides(phosphorName: leftColour),
        ),
      if (right)
        ComponentInstance(
          id: 'right',
          typeId: ComponentTypes.speedBar,
          params: const <String, Object?>{'cells': 9, 'maxKph': 100.0},
          placements: const <DesignOrientation, Placement>{
            DesignOrientation.landscape: Placement(
              offset: Offset(0.57, 0),
              size: Size(0.9, 0.084),
            ),
          },
          opticalOverrides: OpticalOverrides(phosphorName: rightColour),
        ),
    ],
    settings: DashboardSettings(
      opticalProfile: OpticalProfile(
        effects: <String, EffectSetting>{
          for (final id in <String>[
            EffectIds.glassGrain,
            EffectIds.filamentWires,
            EffectIds.tiltParallax,
          ])
            id: const EffectSetting(strength: 0, resumeStrength: 1),
        },
      ),
    ),
  );

  List<int> pixel(
    ({Uint8List pixels, int width, int height}) capture,
    int x,
    int y,
  ) {
    final offset = (y * capture.width + x) * 4;
    return capture.pixels.sublist(offset, offset + 3);
  }

  testWidgets('halos compound across a component boundary with no seam', (
    tester,
  ) async {
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
    expect(
      gapLeftOnly,
      greaterThan(substrate),
      reason: 'left component halo does not reach the boundary',
    );
    expect(
      gapRightOnly,
      greaterThan(substrate),
      reason: 'right component halo does not reach the boundary',
    );

    // The compounding itself: both lit must exceed either alone. Additive
    // accumulation through a compressive tonemap is sub-linear, so this checks
    // the direction and a real margin rather than an exact sum.
    expect(
      gapBoth,
      greaterThan(gapLeftOnly),
      reason: 'halos did not compound across the boundary',
    );
    expect(
      gapBoth,
      greaterThan(gapRightOnly),
      reason: 'halos did not compound across the boundary',
    );

    final lift =
        gapBoth - (gapLeftOnly > gapRightOnly ? gapLeftOnly : gapRightOnly);
    expect(
      lift,
      greaterThan(1.0),
      reason: 'compounding was too small to be a real accumulation',
    );

    // No seam: inside the gap the profile is halo only, and halo is smooth. A
    // per-component raster surface would clip one component's halo at its own
    // bounds, which shows up here as a step.
    //
    // The window stops short of the bars' inner edges. Those edges are real
    // geometry and legitimately sharp; including them measures the segment
    // edge, not the boundary between components.
    final innerEdgePx = ((barOffset - barWidth / 2) * designUnitPx).round();
    expect(
      gapHalfPx,
      lessThan(innerEdgePx),
      reason: 'the smoothness window must stay inside the gap',
    );

    var maxJump = 0.0;
    var maxJumpAt = centre;
    for (var x = centre - gapHalfPx; x < centre + gapHalfPx; x++) {
      final jump = (both[x + 1] - both[x]).abs();
      if (jump > maxJump) {
        maxJump = jump;
        maxJumpAt = x;
      }
    }

    final range = both.reduce((a, b) => a > b ? a : b) - substrate;
    expect(
      maxJump,
      lessThan(range * 0.02),
      reason:
          'discontinuity inside the gap: a seam. '
          'Something reintroduced a per-component raster surface. '
          'x=$maxJumpAt values=${both[maxJumpAt]}, '
          '${both[maxJumpAt + 1]}.',
    );
  });

  testWidgets('mixed-colour halos compound in the shared pass', (tester) async {
    final leftOnly = await capture(
      tester,
      colouredBars(left: true, right: false),
    );
    final rightOnly = await capture(
      tester,
      colouredBars(left: false, right: true),
    );
    final both = await capture(tester, colouredBars(left: true, right: true));
    final center = both.width ~/ 2;
    final row = both.height ~/ 2;
    final leftPixel = pixel(leftOnly, center, row);
    final rightPixel = pixel(rightOnly, center, row);
    final mixedPixel = pixel(both, center, row);

    expect(mixedPixel[0], greaterThan(rightPixel[0]));
    expect(mixedPixel[1], greaterThan(leftPixel[1]));
  });

  testWidgets('component colour overrides module inheritance live', (
    tester,
  ) async {
    final source = colouredBars(left: true, right: true, leftColour: 'Red');
    final dashboard = source.copyWith(
      modules: <VfdModule>[
        VfdModule.main().copyWith(
          opticalOverrides: OpticalOverrides(phosphorName: 'Amber'),
        ),
      ],
      components: <ComponentInstance>[
        source.components.first,
        source.components.last.withOpticalOverrides(OpticalOverrides()),
      ],
    );
    final image = await capture(tester, dashboard);
    final left = pixel(image, 390 - (0.57 * 300).round(), image.height ~/ 2);
    final right = pixel(image, 390 + (0.57 * 300).round(), image.height ~/ 2);

    expect(left[0] - left[1], greaterThan(right[0] - right[1]));
    expect(right[1], greaterThan(left[1]));
  });

  testWidgets('shader Prism light and press states both change output', (
    tester,
  ) async {
    Dashboard prism(bool lit) => Dashboard(
      id: 'prism',
      name: 'Prism',
      supportedOrientations: <DesignOrientation>{DesignOrientation.landscape},
      components: <ComponentInstance>[
        ComponentInstance(
          id: 'button',
          typeId: ComponentTypes.prismButton,
          params: <String, Object?>{'label': 'RESET', 'lit': lit},
          placements: const <DesignOrientation, Placement>{
            DesignOrientation.landscape: Placement(size: Size(0.7, 0.24)),
          },
        ),
      ],
      settings: DashboardSettings(
        opticalProfile: OpticalProfile(
          effects: <String, EffectSetting>{
            for (final id in <String>[
              EffectIds.glassGrain,
              EffectIds.filamentWires,
              EffectIds.tiltParallax,
            ])
              id: const EffectSetting(strength: 0, resumeStrength: 1),
          },
        ),
      ),
    );

    final off = await capture(tester, prism(false));
    final lit = await capture(tester, prism(true));
    final pressed = await capture(
      tester,
      prism(true),
      pressedComponentId: 'button',
    );
    int luminanceSum(Uint8List pixels) {
      var total = 0;
      for (var i = 0; i < pixels.length; i += 4) {
        total += pixels[i] + pixels[i + 1] + pixels[i + 2];
      }
      return total;
    }

    var pressedDifference = 0;
    for (var i = 0; i < lit.pixels.length; i += 4) {
      pressedDifference += (lit.pixels[i] - pressed.pixels[i]).abs();
      pressedDifference += (lit.pixels[i + 1] - pressed.pixels[i + 1]).abs();
      pressedDifference += (lit.pixels[i + 2] - pressed.pixels[i + 2]).abs();
    }
    expect(luminanceSum(lit.pixels), greaterThan(luminanceSum(off.pixels)));
    expect(pressedDifference, greaterThan(1000));
  });
}

class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.program, required this.dashboard});

  final ui.FragmentProgram program;
  final Dashboard dashboard;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness>
    with SingleTickerProviderStateMixin {
  late final VfdController
  _controller = VfdController(vsync: this, design: widget.dashboard)
    // Both bars fully lit. Grain and parallax are disabled by dashboard data.
    ..speedKph = 100;

  void setPressed(String componentId, bool pressed) {
    _controller.setComponentPressed(componentId, pressed);
  }

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
