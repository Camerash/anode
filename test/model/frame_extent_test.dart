import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:anode/model/component_type.dart';
import 'package:anode/model/dashboard.dart';
import 'package:anode/model/dev_design.dart';
import 'package:anode/model/placement.dart';
import 'package:flutter_test/flutter_test.dart';

/// The contain fit performed identically by `vfd.frag`, `EditorCanvas` and
/// `DesignActionOverlay`: one scalar, both axes.
double _fitScale(Size safe, Size frame) =>
    math.min(safe.width / frame.width, safe.height / frame.height);

/// The device rect as seen when it is held in [target]'s orientation. The
/// viewport selector is independent of how the phone happens to be held, so a
/// layout authored for the other orientation is compared against the rotated
/// rect it will actually be rendered into.
Size _viewportFor(DesignOrientation target, Size device) =>
    (device.height >= device.width) == (target == DesignOrientation.portrait)
    ? device
    : Size(device.height, device.width);

const _devices = <String, Size>{
  'iPhone SE': Size(320, 568),
  'iPhone 15 Pro': Size(393, 852),
  'phone landscape': Size(874, 402),
  'iPad portrait': Size(1024, 1366),
  'desktop': Size(1440, 900),
};

void main() {
  group('creating an alternate layout', () {
    test('renders at exactly the fit scale it already had', () {
      for (final entry in _devices.entries) {
        final device = entry.value;
        final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'zero');
        final primary = dashboard.frameSpec(DesignOrientation.landscape);
        final target = device.height >= device.width
            ? DesignOrientation.portrait
            : DesignOrientation.landscape;

        final viewport = _viewportFor(target, device);
        final before = _fitScale(viewport, primary.extent);
        final extent = viewportFrameExtent(target, device, primary);
        final baked = dashboard.withBakedLayout(target, extent: extent);
        final after = _fitScale(viewport, baked.frameExtent(target));

        expect(
          after,
          closeTo(before, 1e-9),
          reason: 'fit scale moved on ${entry.key}',
        );
      }
    });

    test('leaves every component where it already was, in design units', () {
      const device = Size(393, 852);
      final dashboard = Dashboard.forkFrom(developmentPreset(), id: 'zero');
      final source = dashboard.frameExtent(DesignOrientation.landscape);
      final extent = viewportFrameExtent(
        DesignOrientation.portrait,
        device,
        dashboard.frameSpec(DesignOrientation.landscape),
      );
      final baked = dashboard.withBakedLayout(
        DesignOrientation.portrait,
        extent: extent,
      );

      for (final component in baked.components) {
        final type = ComponentTypes.byId(component.typeId);
        final before = component.placements[DesignOrientation.landscape]!;
        final after = component.placements[DesignOrientation.portrait]!;
        expect(
          after.resolve(extent).dx,
          closeTo(before.resolve(source).dx, 1e-9),
          reason: '${component.id} moved in x',
        );
        expect(
          after.resolve(extent).dy,
          closeTo(before.resolve(source).dy, 1e-9),
          reason: '${component.id} moved in y',
        );
        expect(
          after.resolveSizeIn(extent, type, variant: component.effectiveVariant),
          before.resolveSizeIn(source, type, variant: component.effectiveVariant),
          reason: '${component.id} was rescaled',
        );
      }
    });
  });

  group('optical scale', () {
    // Every photograph-tuned constant in `vfd.frag` — halo falloff, control-grid
    // pitch, filament diameter, phosphor coating grain, segment edge softness —
    // is expressed in design units. So px-per-design-unit is the optical scale,
    // and creating an alternate must not change it. It used to change by ~4.6x,
    // which is what made a created portrait layout bloom.
    test('is unchanged by creating an alternate, on every device', () {
      for (final entry in _devices.entries) {
        for (final primaryOrientation in DesignOrientation.values) {
          final device = entry.value;
          final primary = primaryOrientation == DesignOrientation.landscape
              ? const FrameSpec(width: 2.6, height: 1)
              : const FrameSpec(width: 1, height: 2.2);
          final dashboard = Dashboard(
            id: 'optics',
            name: 'Optics',
            primaryOrientation: primaryOrientation,
            frameSpecs: <DesignOrientation, FrameSpec>{
              primaryOrientation: primary,
            },
            components: developmentPreset().components,
          );
          final target = primaryOrientation == DesignOrientation.landscape
              ? DesignOrientation.portrait
              : DesignOrientation.landscape;

          final viewport = _viewportFor(target, device);
          final before = _fitScale(viewport, primary.extent);
          final baked = dashboard.withBakedLayout(
            target,
            extent: viewportFrameExtent(target, device, primary),
          );

          expect(
            _fitScale(viewport, baked.frameExtent(target)),
            closeTo(before, 1e-9),
            reason: 'optical scale moved on ${entry.key} / $primaryOrientation',
          );
        }
      }
    });
  });

  group('viewportFrameExtent', () {
    test('swaps device axes when the target disagrees with the device', () {
      const primary = FrameSpec(width: 2.6, height: 1);
      // Asking for a portrait layout while the device is held in landscape must
      // still describe a portrait envelope.
      final extent = viewportFrameExtent(
        DesignOrientation.portrait,
        const Size(1200, 900),
        primary,
      );
      expect(extent.width / extent.height, closeTo(900 / 1200, 1e-9));
    });

    test('degrades to the primary extent rather than an unusable frame', () {
      const primary = FrameSpec(width: 2.6, height: 1);
      expect(
        viewportFrameExtent(
          DesignOrientation.portrait,
          Size.zero,
          primary,
        ),
        primary.extent,
      );
    });
  });

  group('FrameSpec serialization', () {
    test('round trips an extent whose height is not one unit', () {
      const spec = FrameSpec(width: 2.6, height: 5.637);
      final back = FrameSpec.fromJson(
        spec.toJson(),
        fallback: const FrameSpec.aspect(2.6),
      );
      expect(back.width, closeTo(2.6, 1e-12));
      expect(back.height, closeTo(5.637, 1e-12));
    });

    test('an aspect-only payload decodes as a one-unit-tall frame', () {
      final back = FrameSpec.fromJson(
        <String, Object?>{'referenceAspect': 2.4},
        fallback: const FrameSpec.aspect(2.6),
      );
      expect(back.width, 2.4);
      expect(back.height, 1);
    });

    test('a degenerate extent falls back instead of collapsing the frame', () {
      final back = FrameSpec.fromJson(
        <String, Object?>{'width': 0, 'height': 4},
        fallback: const FrameSpec.aspect(2.6),
      );
      expect(back.extent, const Size(2.6, 1));
    });
  });
}
