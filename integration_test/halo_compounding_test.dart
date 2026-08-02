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
import 'package:anode/vfd/vfd_render_assets.dart';
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
        Placement(center: Offset(cx, 0), size: const Size(barWidth, 0.084));

    return Dashboard(
      id: 'halo',
      name: 'Halo',
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

  late VfdRenderAssets renderAssets;

  setUpAll(() async {
    renderAssets = await VfdRenderAssets.load();
  });

  tearDownAll(() => renderAssets.dispose());

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
                    renderAssets: renderAssets,
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
                    renderAssets: renderAssets,
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
    components: <ComponentInstance>[
      if (left)
        ComponentInstance(
          id: 'left',
          typeId: ComponentTypes.speedBar,
          params: const <String, Object?>{'cells': 9, 'maxKph': 100.0},
          placements: const <DesignOrientation, Placement>{
            DesignOrientation.landscape: Placement(
              center: Offset(-0.57, 0),
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
              center: Offset(0.57, 0),
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

  int regionLuminance(
    ({Uint8List pixels, int width, int height}) capture,
    ui.Rect region,
  ) {
    var total = 0;
    final left = region.left.floor().clamp(0, capture.width);
    final top = region.top.floor().clamp(0, capture.height);
    final right = region.right.ceil().clamp(0, capture.width);
    final bottom = region.bottom.ceil().clamp(0, capture.height);
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final offset = (y * capture.width + x) * 4;
        total += capture.pixels[offset];
        total += capture.pixels[offset + 1];
        total += capture.pixels[offset + 2];
      }
    }
    return total;
  }

  int regionDifference(
    ({Uint8List pixels, int width, int height}) first,
    ({Uint8List pixels, int width, int height}) second,
    ui.Rect region,
  ) {
    var total = 0;
    final left = region.left.floor().clamp(0, first.width);
    final top = region.top.floor().clamp(0, first.height);
    final right = region.right.ceil().clamp(0, first.width);
    final bottom = region.bottom.ceil().clamp(0, first.height);
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final offset = (y * first.width + x) * 4;
        total += (first.pixels[offset] - second.pixels[offset]).abs();
        total += (first.pixels[offset + 1] - second.pixels[offset + 1]).abs();
        total += (first.pixels[offset + 2] - second.pixels[offset + 2]).abs();
      }
    }
    return total;
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

  testWidgets('shader Prism has physical body, atlas legend, and cap travel', (
    tester,
  ) async {
    Dashboard prism({
      required bool lit,
      String label = 'RESET',
      double filament = 0,
      bool backdrop = false,
    }) => Dashboard(
      id: 'prism',
      name: 'Prism',
      components: <ComponentInstance>[
        if (backdrop)
          ComponentInstance(
            id: 'backdrop',
            typeId: ComponentTypes.speedBar,
            params: const <String, Object?>{'cells': 1, 'maxKph': 100.0},
            placements: const <DesignOrientation, Placement>{
              DesignOrientation.landscape: Placement(
                center: Offset(0, 0.11),
                size: Size(2.4, 0.08),
              ),
            },
          ),
        ComponentInstance(
          id: 'button',
          typeId: ComponentTypes.prismButton,
          params: <String, Object?>{'label': label, 'lit': lit},
          placements: const <DesignOrientation, Placement>{
            DesignOrientation.landscape: Placement(
              center: Offset.zero,
              size: Size(0.7, 0.24),
            ),
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
            EffectIds.filamentWires: EffectSetting(
              strength: filament,
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

    final off = await capture(tester, prism(lit: false));
    final lit = await capture(tester, prism(lit: true));
    final pressed = await capture(
      tester,
      prism(lit: true),
      pressedComponentId: 'button',
    );
    final blank = await capture(tester, prism(lit: true, label: ''));
    final filamentOff = await capture(
      tester,
      prism(lit: false, label: '', filament: 0, backdrop: true),
    );
    final filamentOn = await capture(
      tester,
      prism(lit: false, label: '', filament: 1, backdrop: true),
    );

    const legendRegion = ui.Rect.fromLTWH(315, 130, 150, 40);
    const quietFaceRegion = ui.Rect.fromLTWH(350, 119, 80, 10);
    const leftSocketRegion = ui.Rect.fromLTWH(285, 114, 10, 72);
    const capRegion = ui.Rect.fromLTWH(300, 119, 180, 62);

    expect(
      regionLuminance(lit, legendRegion),
      greaterThan(regionLuminance(off, legendRegion)),
    );
    expect(regionDifference(lit, blank, legendRegion), greaterThan(5000));
    final quietAverage =
        regionLuminance(lit, quietFaceRegion) /
        (quietFaceRegion.width * quietFaceRegion.height * 3);
    expect(quietAverage, lessThan(90));

    final socketDifference = regionDifference(lit, pressed, leftSocketRegion);
    final capDifference = regionDifference(lit, pressed, capRegion);
    expect(capDifference, greaterThan(1000));
    expect(socketDifference, lessThan(capDifference ~/ 8));

    const insideWireRegion = ui.Rect.fromLTWH(370, 110, 40, 80);
    const outsideWireRegion = ui.Rect.fromLTWH(220, 110, 40, 80);
    final insideDifference = regionDifference(
      filamentOff,
      filamentOn,
      insideWireRegion,
    );
    final outsideDifference = regionDifference(
      filamentOff,
      filamentOn,
      outsideWireRegion,
    );
    expect(outsideDifference, greaterThan(200));
    expect(insideDifference, lessThan(outsideDifference ~/ 10));
  });
}

class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    required this.renderAssets,
    required this.dashboard,
  });

  final VfdRenderAssets renderAssets;
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
    renderAssets: widget.renderAssets,
    controller: _controller,
    frameInsets: EdgeInsets.zero,
  );
}
