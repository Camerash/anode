import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:anode/model/component_instance.dart';
import 'package:anode/model/component_type.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/optical_profile.dart';
import 'package:anode/model/placement.dart';
import 'package:anode/model/settings.dart';
import 'package:anode/vfd/vfd_cluster.dart';
import 'package:anode/vfd/vfd_render_assets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Creating an alternate layout must not change the optical scale.
///
/// Every photograph-tuned constant in `vfd.frag` — halo lobe falloff, control
/// grid pitch, filament diameter and spacing, phosphor coating grain, segment
/// edge softness — is expressed in design units. A design unit used to mean
/// "the height of the frame", so baking a portrait alternate from a landscape
/// primary raised px-per-design-unit about 4.6x and blew every one of those up
/// while the geometry, shrunk to compensate, stayed put.
///
/// This renders the same component through a landscape primary and through a
/// portrait alternate baked from it, both at 300px per design unit, and
/// compares the luminance across a lit edge. The profiles must match: same
/// halo, same mesh, same edge softness, same wires.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const double designUnitPx = 300;
  const Size landscapeExtent = Size(2.6, 1);

  // A portrait phone. The alternate CREATE would bake for it, sized so the
  // design keeps the fit scale it already had.
  const Size device = Size(300, 780);

  Dashboard landscapeDesign() => Dashboard(
    id: 'optics',
    name: 'Optics',
    frameSpecs: const <DesignOrientation, FrameSpec>{
      DesignOrientation.landscape: FrameSpec(width: 2.6, height: 1),
    },
    components: <ComponentInstance>[
      ComponentInstance(
        id: 'bar',
        typeId: ComponentTypes.speedBar,
        params: const <String, Object?>{'cells': 9, 'maxKph': 100.0},
        placements: const <DesignOrientation, Placement>{
          DesignOrientation.landscape: Placement(
            center: Offset.zero,
            size: Size(0.9, 0.084),
          ),
        },
      ),
    ],
    settings: DashboardSettings(
      opticalProfile: OpticalProfile(
        effects: <String, EffectSetting>{
          // Grain is screen-space and animated; parallax would shift the frame.
          // Neither is what this measures.
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

  late VfdRenderAssets renderAssets;

  setUpAll(() async {
    renderAssets = await VfdRenderAssets.load();
  });

  tearDownAll(() => renderAssets.dispose());

  /// Luminance along the horizontal centre line, at [designUnitPx] per unit.
  Future<List<double>> centreProfile(
    WidgetTester tester,
    Dashboard dashboard,
    DesignOrientation orientation,
    Size extent,
  ) async {
    final width = extent.width * designUnitPx;
    final height = extent.height * designUnitPx;
    final key = GlobalKey();

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(width, height)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: OverflowBox(
              minWidth: width,
              maxWidth: width,
              minHeight: height,
              maxHeight: height,
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: _Harness(
                    renderAssets: renderAssets,
                    dashboard: dashboard,
                    orientation: orientation,
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

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final pixels = data.buffer.asUint8List();
    final row = image.height ~/ 2;
    final out = <double>[];
    for (var x = 0; x < image.width; x++) {
      final o = (row * image.width + x) * 4;
      out.add(
        0.2126 * pixels[o] + 0.7152 * pixels[o + 1] + 0.0722 * pixels[o + 2],
      );
    }
    image.dispose();
    return out;
  }

  testWidgets('a baked alternate renders at the same optical scale', (
    tester,
  ) async {
    final primary = landscapeDesign();
    final extent = viewportFrameExtent(
      DesignOrientation.portrait,
      device,
      primary.frameSpec(DesignOrientation.landscape),
    );
    final baked = primary.withBakedLayout(
      DesignOrientation.portrait,
      extent: extent,
    );

    // The envelope is the same width and much taller — it is the whole phone
    // screen now, not the strip the landscape face occupied.
    expect(extent.width, closeTo(landscapeExtent.width, 1e-9));
    expect(extent.height, greaterThan(5));
    // Without this the test passes vacuously: a bake that silently did nothing
    // would fall back to the landscape layout and compare it against itself.
    expect(baked.hasAuthoredLayout(DesignOrientation.portrait), isTrue);
    expect(
      baked.layoutForViewport(DesignOrientation.portrait),
      DesignOrientation.portrait,
    );
    // Without this the test passes vacuously: a bake that silently did nothing
    // would fall back to the landscape layout and compare it against itself.
    expect(baked.hasAuthoredLayout(DesignOrientation.portrait), isTrue);
    expect(
      baked.layoutForViewport(DesignOrientation.portrait),
      DesignOrientation.portrait,
    );

    final before = await centreProfile(
      tester,
      primary,
      DesignOrientation.landscape,
      landscapeExtent,
    );
    final after = await centreProfile(
      tester,
      baked,
      DesignOrientation.portrait,
      extent,
    );

    expect(after, hasLength(before.length));

    var worst = 0.0;
    var worstX = -1;
    for (var x = 0; x < before.length; x++) {
      final delta = (before[x] - after[x]).abs();
      if (delta > worst) {
        worst = delta;
        worstX = x;
      }
    }

    // Both profiles cross the bar's lit cells, its halo shoulder, the control
    // grid and a filament wire. If a design unit still meant "frame height",
    // the alternate's halo alone would be several times wider here.
    expect(
      worst,
      lessThan(12),
      reason: 'luminance diverged by $worst at x=$worstX',
    );

    // And the profile is not merely flat-and-equal: it has real structure to
    // compare in the first place.
    final peak = before.reduce(math.max);
    final floor = before.reduce(math.min);
    expect(peak - floor, greaterThan(60));

    // Measured directly rather than inferred from the comparison above, so this
    // stays meaningful even if the two renders ever stop being the same width:
    // the halo shoulder is a pure design-unit quantity, so its width in pixels
    // IS the optical scale.
    final beforeShoulder = _shoulderPx(before);
    final afterShoulder = _shoulderPx(after);
    expect(beforeShoulder, greaterThan(8));
    expect(
      afterShoulder,
      closeTo(beforeShoulder, 3),
      reason:
          'halo shoulder was \$beforeShoulder px and became \$afterShoulder px',
    );
  });
}

/// Distance in pixels from the outermost lit edge to where the halo has fallen
/// to a quarter of peak brightness.
int _shoulderPx(List<double> profile) {
  final peak = profile.reduce(math.max);
  final quarter = peak * 0.25;
  var edge = -1;
  for (var x = profile.length - 1; x >= 0; x--) {
    if (profile[x] >= peak * 0.9) {
      edge = x;
      break;
    }
  }
  for (var x = edge; x < profile.length; x++) {
    if (profile[x] < quarter) return x - edge;
  }
  return profile.length - edge;
}

class _Harness extends StatefulWidget {
  const _Harness({
    required this.renderAssets,
    required this.dashboard,
    required this.orientation,
  });

  final VfdRenderAssets renderAssets;
  final Dashboard dashboard;
  final DesignOrientation orientation;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness>
    with SingleTickerProviderStateMixin {
  late final VfdController _controller = VfdController(
    vsync: this,
    design: widget.dashboard,
    orientation: widget.orientation,
  )..speedKph = 100;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VfdCluster(
    renderAssets: widget.renderAssets,
    controller: _controller,
    safeInsets: EdgeInsets.zero,
  );
}
