# Anode

A Flutter speedometer that simulates a 1980s vacuum fluorescent display at the
optical level, not the icon level. GPS supplies speed; a fragment shader supplies
everything else.

The competitive thesis: every existing retro speedometer app draws a *picture* of
a VFD — flat vector segments with a gaussian blur. This one simulates the physics
of the tube. That difference is the entire product. Any change that makes the
render look more like a styled font and less like a photograph of glowing
phosphor behind glass is a regression, even if it looks "cleaner."

## What actually makes it read as real

In rough order of how much each one matters:

1. **Unlit segments are visible.** Phosphor coating is a pale warm grey when
   unpowered. A display with invisible off-segments reads as a font. This is the
   single biggest tell.
2. **Filament wires.** Hairline tungsten cathodes stretched horizontally in front
   of the phosphor plane. They cut thin dark lines through lit segments and glow
   faintly warm. Nobody else fakes these.
3. **Control grid mesh.** A fine woven mesh sits in front of each digit, giving
   lit areas a subtle moiré texture. It is why real VFD glow looks textured
   rather than smooth.
4. **Two-lobe halo.** Glass scatter is not a single gaussian. Tight bright core
   lobe plus wide soft lobe.
5. **Phosphor decay.** Segments fall off over ~50-80ms, so a digit change leaves
   a brief ghost. Asymmetric: fast attack, slow decay.
6. **Colour.** ZnO:Zn peaks near 505nm — cyan-green, not green. Amber and red
   clusters were the same green phosphor behind a filter, so they bloom slightly
   differently. Never `#00FF00`.

## Composite order (do not reorder)

substrate -> unlit phosphor -> emission x grid mesh -> filament wires ->
glass sheen -> grain -> tonemap

Filaments come after emission because they are physically in front of the
phosphor. Grain comes after the sheen because it is glass and sensor noise, not
phosphor noise.

## The name

**Anode** — the phosphor-coated plate the electrons strike. It is the part that
actually glows, so the name states the thesis: this simulates the tube, not the
typeface.

Deliberately not a speedometer word. The incumbents own "speedometer" as a
keyword and that fight is unwinnable on their terms.

**There are two names, and they must not contaminate each other.** The brand is
`Anode`, short and ownable. The store listing carries the keyword tail —
"Anode — GPS Speedometer" — with `speedometer`, `dashboard`, `hud`, `odometer`
living in the subtitle and keyword fields where they do real work. Never push
store SEO into the product name, the app icon, or the in-app copy.

Rejected, with reasons that still apply to any future rename:

- Anything containing a decade or era. Dates the product and fences it in the
  moment a CRT, Nixie or early-2000s LCD design ships.
- Anything referencing a specific manufacturer's cluster. A trademark complaint
  against the app *name* is fatal in a way one against a single design pack
  is not.
- `Filament`, which encodes the thesis beautifully and is already Google's
  real-time rendering engine. Colliding with a graphics library while pitching a
  graphics product is the worst available collision.

Before any rename ships, check in this order: App Store name availability (Apple
enforces uniqueness, and it is the least negotiable constraint), trademark in
classes 9 and 42, then the domain.

Note that renderer classes stay `Vfd*`. Anode is the product; VFD is the thing
being simulated. Keeping them distinct means a second display technology later
does not require renaming the first.

## Framework: Flutter

Chosen over React Native + Skia. RN was genuinely competitive on day-one
ergonomics — SkSL supports uniform arrays natively, which would have removed the
packing hack below, and it has offscreen surfaces on stable. It lost on ceiling:
when this needs multipass, real geometry, or a swept tachometer, Flutter has a
first-party low-level path already in preview, whereas RN's equivalent is a
native Metal module plus a native Vulkan module — two platform-specific rewrites,
which is the thing a cross-platform framework was adopted to avoid.

Note that the framework choice barely matters for the conventional UI here. The
app is ~95% one custom-rendered screen. That is *why* the decision came down to
the GPU ceiling.

## Render backend

Currently `dart:ui` `FragmentProgram` on the stable channel. Keep the renderer
behind an interface — nothing outside `lib/vfd/` should know how a frame gets
drawn.

**Flutter GPU** (`flutter_gpu`, SDK package) is the eventual upgrade path. It
gives real uniform buffers (arrays and structs, so the packing hack goes away),
real render targets (the cached-emission optimisation becomes natural rather than
a `toImageSync()` workaround), and vertex buffers (draw segments as geometry
instead of evaluating 21 SDFs per pixel — the version that scales to a full
multi-gauge cluster).

Not adopted yet, for two reasons:

1. It requires the **master channel**, which means cutting App Store builds from
   an unreleased branch and pinning the whole project — plugins included — to
   master for one screen. Shader bundling also depends on the experimental Dart
   Native Assets feature, and the API carries no stability guarantee.
2. **There is no measured problem.** Three digits and a bar graph is a trivial
   fragment load. Profile first.

The GLSL body is roughly 90% portable between the two — what differs is uniform
binding and the entry point, not the maths. Revisit if profiling shows a real
thermal wall, or once multi-gauge clusters with swept tachometers are on the
table.

## Flutter shader constraints

These cost real time to rediscover:

- **No uniform arrays.** `uniform float x[21]` will not compile. Segment
  brightness is packed into six `vec4`s with an 8-float stride per digit (7
  segments + 1 spare for a future decimal point). Digit loops must be unrolled;
  helper functions with `inout` params keep this readable.
- **`setFloat(i, v)` indexes flat floats**, not uniforms. A `vec2` consumes two
  indices. The index map in `vfd.frag` and `VfdPainter.paint` must stay in sync —
  if you add a uniform, add it at the end or renumber both sides together.
- **`FlutterFragCoord()` has y pointing down.** Flip it before doing any maths
  that assumes a standard GL frame.
- **Keep `highp`.** The SDF loses accuracy at mediump and the halo bands visibly.
- The bar graph uses `mod()` for cell layout, which repeats infinitely across the
  display. Every term derived from it must be gated by `inRange` or phantom
  unlit cells appear outside the gauge. This bug has been fixed once already.

## Layer toggles

`VfdLayers` gates each optical layer independently. Keep this. It is a debugging
tool now, a user-facing authenticity panel later, and it is also how the App
Store screenshots get made — being able to kill the grain and raise the bloom for
a still is genuinely useful. Persist it with `shared_preferences`. Never collapse
the toggles into a single "retro mode" boolean.

## Performance and battery

This runs with the screen at full brightness, GPS active, phone in a windshield
mount in direct sun. Thermals matter more than framerate.

- Digits change once or twice a second. The emission layer should eventually be
  rendered to a cached `ui.Image` via `PictureRecorder.toImageSync()` on value
  change only, with grain, multiplex flicker, and sheen composited over it every
  frame. Not yet implemented — the naive full re-render is fine during
  development, and this is the first optimisation to reach for when profiling.
- Painting is driven by `CustomPainter(repaint: controller)`, not `setState`.
  Keep it that way; rebuilding the widget tree every frame for a shader is waste.
- Measure with `flutter run --profile` on a physical device, in sunlight, warm.
  Simulator numbers are meaningless here.

## Sensors

- **Speed comes from GPS, never the accelerometer.** Double-integrating
  acceleration drifts within seconds. Use `geolocator` with
  `LocationAccuracy.bestForNavigation`. `SpeedFilter` is a 1D Kalman seeded from
  the first fix and weighted by `speedAccuracy`; hold the last good value rather
  than letting the display flicker on a bad fix.
- **Tilt uses the gravity vector, not raw acceleration.** Raw accelerometer in a
  car is mostly road vibration and will make the display jitter. `TiltSource`
  applies a deadzone plus smoothing — feed it `sensors_plus`
  `accelerometerEventStream` (gravity included), not `userAccelerometerEventStream`.
- **Respect reduce motion.** `MediaQuery.disableAnimationsOf` forces tilt
  parallax off; the workbench already does this. Parallax has a documented
  motion-sickness history.
- Prefer moving the **glass sheen and unlit-segment shading** rather than
  translating the digits. It sells depth better and nothing the driver is reading
  moves.

## Roadmap

Near term:

- **Cluster designs as data.** Segment endpoints, digit positions and bar
  geometry are currently constants in the shader. They should be a config the
  renderer consumes, so a new design is a file rather than a shader edit.
- **Irregular glyphs via a baked SDF atlas.** Real clusters have etched anode
  shapes that are not seven-segment: `MPH`, fuel pump icons, arrows, `ANTI-LOCK`,
  `CHECK ENGINE`, 14-segment alphanumerics. Author them as SVG, bake to an SDF
  texture at build time, sample in the shader via `setImageSampler`. One path for
  fonts, icons and warning legends, all inheriting the same halo maths. Do this
  *before* adding the second cluster design, not after.
- Amber and red filter modes as first-class designs, not just a colour swap — the
  filter changes bloom falloff, not only hue.

Later:

- Trip computer readouts in period-correct phrasing (avg econ, dist to empty).
- Optional OBD2 for RPM, coolant, fuel. A VFD cluster looks empty without a tach.
- CarPlay / Android Auto. **Investigate before betting on it.** Both are template
  systems with restricted app categories; a gauge display does not obviously
  qualify, and the surface that allows custom drawing is the navigation one.
  Flutter support here is thin — assume a native Swift/Kotlin surface if it
  happens at all. Do not put this on a roadmap shown to anyone until validated.

## Non-goals

- Pixel-exact clones of a specific manufacturer's cluster, named as such.
  Inspired-by designs with original naming only.
- Subscriptions. The audience for this resents renting a shader. One-time unlock
  or paid cluster packs.
- Feature parity with the generic GPS speedometer apps. Speed limit databases,
  route recording and trip CSV export are commodity features the incumbents
  already do better. Compete on the render.
- Flutter web. The landing page demo should be the standalone WebGL build, which
  will be smaller and faster than anything Flutter compiles to web and does not
  need to share a codepath with the app.
