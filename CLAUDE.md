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

The single-pass composable renderer strengthens this case materially. A component
array is a natural uniform buffer in Flutter GPU, whereas on stable it must be
packed into a sampled texture.

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

## Rendering architecture

**One shader pass renders the entire screen.** Components are entries in a data
list the single renderer consumes. They are NOT Flutter widgets.

This is not a performance choice, it is a correctness one. Halos accumulate
additively across all emissive geometry. If each component were its own widget
with its own `FragmentShader`, each would be a separate raster surface and halos
could not bleed across component boundaries — producing a hard seam between every
pair of adjacent gauges. Anything that reintroduces per-component raster surfaces
reintroduces those seams.

Consequence: per-component parameters cannot be individual uniforms; four gauges
would exhaust the uniform budget. Pack component data into a small texture and
sample it via `setImageSampler`.

## Full bleed

The app has no visible edge. The substrate extends to the fragment bounds. No
bezel mask, no `ClipRRect`, no rounded corners, no fixed `AspectRatio`. On OLED
the near-black substrate blends into the device bezel so the tube appears to
continue past the glass. Any vignette is a gentle falloff, never an edge.

Content insets to safe area; the background does not. System UI is hidden.

An authored frame declares an aspect and is **contain-fitted inside the safe
rect**: the fit picks whichever axis is tighter, the frame is centred on the safe
rect, and nothing is ever cropped to it. The safe rect governs placement only —
there is no mask and no clamp, so halo, sheen and grain keep evaluating across
the full fragment bounds and spill past both the safe rect and the screen edge.
Content therefore never bleeds off; light always does.

Halo compounding is already correct — `glow` accumulates additively. Brightness
is governed by the tonemap, which is deliberately compressive so overlapping
cores blow to white rather than clipping to garish green. Expose exposure as a
parameter; do not "fix" the tonemap.

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
- **Repeated geometry must accumulate neighbours, not fold into one cell.** A
  `mod()` cell-local coordinate puts each pixel in exactly one cell, so a halo
  gated by that cell's lit state dies on the cell boundary and the strip's bloom
  terminates on a hard rectangle. Evaluate each cell against its own centre and
  sum a few neighbours instead. Every term derived from the cell index still has
  to be gated by `inRange`, or phantom unlit cells appear outside the gauge.
  Both of these have been fixed once already.
- **Halo width has to scale with feature size.** `halo()` is tuned for digit
  segments and its falloff is in design units, so reusing it on anything finer
  sums a dozen digit-sized lobes into one blown-out blob. The unit legends
  needed their own tighter falloff (`legHalo`) plus a weight. Any glyph smaller
  than a digit segment will hit this.
- The numeric constants in `vfd.frag` are visually tuned against reference
  photographs. Do not refactor, round, rename or extract them.

## Layer toggles

`VfdLayers` gates each optical layer independently. These are GLOBAL, app-wide
settings, not per-dashboard. They govern render fidelity and performance, not a
design's identity. Persist once with `shared_preferences`.

Keep them. They are a debugging tool, a user-facing authenticity panel, and how
App Store screenshots get made — killing grain and raising bloom for a still is
genuinely useful. Never collapse them into a single "retro mode" boolean.

## Dashboards, presets and components

A **DesignPreset** is shipped, immutable and versioned. A **Dashboard** is a user
instance. Editing a preset FORKS it into a Dashboard, which is then owned by the
user and never auto-updated. This is copy-on-customize. Do not implement
delta-merging against updated presets — it sounds more elegant and causes pain
forever.

### Capabilities

Every component type declares what it needs: GPS, accelerometer, barometer,
network, trip storage. The app takes the union across the ACTIVE dashboard and
starts only those sensors and requests only those permissions. This is how the
barometer stays off for someone with no altimeter, and how network permission is
not requested for a layout with no weather gauge.

### Orientation

Layouts are NOT responsive. These are designed instrument faces, not web pages. A
design declares which orientations it supports, and each supported orientation
gets its own AUTHORED layout — never a reflow of the other. Lock to supported
orientations while a design is active. Within an orientation, absorb the aspect
ratio spread (18:9 through iPad 4:3) with anchor-plus-offset positioning, not
absolute coordinates.

### Three settings levels

- Per-component: speed unit, digit count, data binding
- Per-dashboard: orientation, brightness, phosphor colour
- Global: authenticity layer toggles (see "Layer toggles")

### Build order

The editor is built EARLY, before the shipped presets are authored. It is a
forcing function: if components are genuinely data, an editor manipulating that
data proves it; if they are hardcoded layouts in disguise, the editor exposes
that immediately. Presets authored before the editor exists will encode
assumptions the editor breaks.

Build the editor first as a DEVELOPER TOOL — plain Material widgets, no
onboarding, no polish. Its purpose is to stress the data model. Polish it only
once the model has stopped moving.

## Screens

The speedometer is the root screen and is standalone. A dimmed gear in the bottom
right auto-hides after a few seconds and returns on tap anywhere.

The gear must be rendered in the VFD idiom — unlit-segment grey on the same
substrate. A crisp vector icon floating on top breaks the illusion harder than
almost anything else on that screen.

Keep the screen awake. Hide system UI.

### Runtime controls dock in the dead space

Contain-fitting an authored frame into an arbitrary screen leaves empty tube
above and below the design band. That dead space belongs to no design, so it is
where the effect toggles, phosphor, unit and demo-mode controls live. They never
resize the render, never occlude the band, and never change its aspect.

**Nothing may resize the cluster to make room for chrome.** Anchor-plus-offset
positions resolve against the aspect ratio, so shrinking the cluster moves every
component — a panel taking a third of the screen means you are tuning and
authoring against a frame that never ships. A settings sheet that pushed the
cluster aside was built and removed for exactly this reason; the objection is
not that it occluded the render, it is that it silently changed the layout.

If a surface genuinely needs more room than the dead space offers, scale the
whole rendered frame uniformly and letterbox it. Never reflow it.

### Config UI is in the VFD idiom

Every user-facing control surface — the dock, the Library, Settings — is drawn
in the tube's visual language, not Material's. A stock switch or a filled chip
sitting on the substrate breaks the illusion exactly the way a crisp vector gear
does, and these surfaces sit directly on top of the render.

- Two states, borrowed from the phosphor: unlit warm grey for available, lit
  phosphor for active. Never a fill colour, never an accent hue that is not the
  active phosphor.
- Etched hairline borders. No shadows, no elevation, no ripples. Controls look
  like shapes etched on the anode, not like paper.
- Legends are uppercase and letterspaced. Prefer a word to an icon — `RUN` and
  `HOLD` read more period-correct than a play triangle.
- Anything showing a quantity uses the segmented cell bar on the same rule as
  the gauge: cell `i` is lit when `(i + 0.5) / n <= fraction`. A continuous
  Material slider does not belong on this substrate.
- Controls sit on the substrate with no panel fill behind them. The tube shows
  through.

The glow is faked in these widgets, which is acceptable because they are chrome
rather than instrument. Do not push the fake far — a widget approximating a
two-lobe halo directly beside a real one looks worse than a flat etched control.
Genuine emissive controls arrive with the baked SDF atlas, which turns a legend
into real anode geometry whose halo compounds with everything else.

The editor is exempt while it is a developer tool. See "Build order": plain
Material until the data model stops moving, then it adopts the idiom.

### Navigation, and why there are no root gestures

**The cluster is inert to touch except the gear.** No long-press, no swipe, no
double-tap. The phone lives in a windshield mount that gets bumped, and a hand
bracing against the device produces exactly the gesture a long-press detector
is looking for. A mistouch that opens an editor over a driver's instrument is
the worst failure this app can have, so no whole-screen gesture may be bound to
anything. This also means pointer-drag tilt is a desktop and development
affordance only; on device, tilt comes from the gravity vector.

Everything that is not driving sits behind one deliberate path:

    cluster --gear--> dock --[Library]--> route with tabs
                                          [ Designs | Settings ]

Conventional app chrome — tabs, lists, app bars — is fine on that route. It is
only forbidden on the instrument itself. Tapping a design card activates it;
opening the editor requires the card's separate, explicit Edit button, so
nothing is editable in fewer than three deliberate taps.

Edit on a shipped preset forks it. The Library is where copy-on-customize
becomes legible to the user, and the fork must be visible when it happens
rather than discovered later.

There is deliberately **no motion lock**. Everything stays reachable at any
speed; this was considered and rejected as paternalistic, and the three-tap
depth already rules out accidental entry.

### The editor is its own route

Editing needs persistent chrome that tuning does not, so it gets a dedicated
screen: an aspect-locked canvas plus a component list and inspector, with an
orientation switcher choosing which authored layout is being edited.

The editor canvas is the one place a visible frame edge is correct. Everywhere
else an edge breaks the illusion; here you are authoring the frame, so you have
to see where it ends. The canvas holds the target orientation's aspect
regardless of the window shape, and scales to fit.

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

## Data sources: phone only

Anode runs on phone sensors alone. GPS, accelerometer, barometer, battery, clock,
and one weather API. Nothing is read from the vehicle.

This is a conversion decision before it is an engineering one. The install path
for an aesthetic app is "see screenshot -> install -> open -> it works". Adding
"buy an adapter, discover it does not work on your iPhone, wait for shipping"
loses nearly everyone, and inherits a permanent per-vehicle support matrix. OBD
app reviews are full of one-star "does not work on my 2013 Civic" complaints.
That is the cost, and a tachometer is not worth it.

### The density problem

Real clusters show eight or nine live values at once. Speed, outside temp and
battery is three, and three values read as a widget with decoration around it
rather than an instrument cluster. Density is the central design problem of the
phone-only approach. Do not solve it with inert fake elements — that guts the
authenticity thesis, which is the whole product.

Solve it with the trip computer instead. The reference clusters have a button
row: AVG ECON / INST ECON / TRIP A / TRIP B, plus E/M and RESET. A period trip
computer showed elapsed time, average speed, distance, outside temp and economy.
Five of those six are derivable from the phone. The original hardware's
interaction model happens to map onto exactly the data available, so that button
row becomes real UI rather than ornament.

### Available values

Roughly in order of how period-correct they feel:

- Trip odometer, from integrated GPS distance. Period-correct, and an odometer
  readout is a large amount of visual density for free.
- Heading, as a compass strip. Present on the reference GM cluster.
- Elapsed time, average speed, max speed. Trip computer staples, all derived.
- Phone battery as the fuel gauge. Not a compromise stand-in — the metaphor is
  both a joke and genuinely useful, since a mounted driver does care about phone
  charge, and on a car charger the gauge fills as you drive. Animate the charging
  state; add a low-battery warning legend in period amber.
- Altitude and barometric pressure. Nearly every phone since the iPhone 6 has a
  barometer. Period-implausible but visually convincing.
- Lateral and longitudinal g, plus a 0-100 timer. The 300ZX had exactly this.
- Auto dimming from ambient light and sunset time. Real clusters dimmed with the
  headlight switch; doing it automatically is an invisible detail worth having.

### Outside temperature

Use Open-Meteo: free, no API key, no attribution friction, no billing surprise at
scale. Cache aggressively and only refetch on meaningful movement — ambient
temperature changes slowly and the phone is on battery in a hot car. Degrade
gracefully with no signal; tunnels and rural roads are exactly where people
drive. Expect disagreement with the car's own reading, which measures at the
bumper and over-reads when parked in sun. Display the value without over-claiming
precision.

### Known support burden

GPS speed reads consistently lower than the car's speedometer, by a few percent.
This is correct behaviour: most markets require a speedometer never to under-read,
so manufacturers bias them high. Users will report it as a bug. Put it in an FAQ
and consider a one-time in-app note — it will otherwise be the most common review
complaint.

## Speed estimation

Speed comes from GPS Doppler (`Position.speed`), never from differentiating
positions and never from integrating acceleration. Use `geolocator` with
`LocationAccuracy.bestForNavigation`.

### What v1 does

Use the IMU for **stationary detection only**, and get perceived responsiveness
from the render loop.

Accelerometer *magnitude* variance is rotation-independent, so stationary
detection needs no knowledge of the mount angle. That single signal delivers both
things that matter: it kills phantom drift when parked, and it detects motion
onset a few hundred milliseconds before GPS reports it. This is a ZUPT
(zero-velocity update) detector — a mature technique for constraining dead
reckoning drift.

Between GPS fixes, extrapolate in the render loop. `VfdController` already ticks
independently of the speed source; sensor rate and render rate stay decoupled.
Perceived responsiveness comes from the render loop, not the sensor rate.

Expect to tune the ZUPT threshold against real drive logs. Fixed-threshold
detectors are known to misclassify — a single hardcoded value will misfire at
idle in a rough-idling car and at steady highway cruise. Double-threshold or
sliding re-detection is the established fix.

Supplement cheaply with platform activity recognition (IN_VEHICLE /
CMMotionActivity) as a coarse sanity check.

### The trap

The phone sits in a mount at an arbitrary, unknown angle. `accel.y` is NOT
forward acceleration. Full velocity fusion requires estimating device-to-vehicle
rotation by correlating device-frame horizontal acceleration against GPS-derived
acceleration over the first minute of driving. It is fragile and re-converges
every time the phone is re-seated. This is why v1 does stationary detection only.

### Later

Full two-state Kalman fusion (velocity + accelerometer bias, bias constant
between updates) is a clean upgrade once real drive logs exist to tune against.
Published smartphone results show roughly 44-48% improvement in speed accuracy
and precision over GPS alone. Do not attempt it before the mount-orientation
problem has a tested answer.

`SpeedFilter` is the existing 1D Kalman, seeded from the first fix and weighted
by `speedAccuracy`. Hold the last good value rather than letting the display
flicker on a bad fix.

### Perception, not accuracy

Never display a bare `0` while waiting for a fix. Show an explicit acquiring
state in period idiom — blank digits with visible unlit segments is exactly right
and authentic.

Ship the simulated source as a user-facing demo mode. "Installed it, opened it
indoors, saw nothing" is a one-star review unrelated to code quality.

### Tilt

Gravity vector, not raw acceleration — raw accelerometer in a car is mostly road
vibration and will make the display jitter. `TiltSource` applies a deadzone plus
smoothing; feed it `sensors_plus` `accelerometerEventStream` (gravity included),
not `userAccelerometerEventStream`.

Respect reduce motion. `MediaQuery.disableAnimationsOf` forces tilt parallax off;
the workbench already does this. Parallax has a documented motion-sickness
history.

Prefer moving the **glass sheen and unlit-segment shading** rather than
translating the digits. It sells depth better and nothing the driver is reading
moves.

## Working practice

**Each stage ends in a commit before the next one starts.** Stages are reviewed
at their boundary, and an uncommitted boundary makes it impossible to tell what
was approved from what came after it — which matters here because a later stage
routinely revisits the shader the previous one just tuned.

Commit messages follow Conventional Commits. Anything discovered during a stage
that changes the architecture goes into this file in the same commit, so the
spec and the code never disagree about what was decided.

## Roadmap

Near term, roughly in order:

- **Component data model.** Components as data with capability declarations;
  preset/instance split; per-orientation authored layouts.
- **Single-pass composable renderer.** See "Rendering architecture".
- **Dashboard editor as a developer tool.** Built before the shipped presets are
  authored. See "Build order".
- **Irregular glyphs via a baked SDF atlas.** Real clusters have etched anode
  shapes that are not seven-segment: `MPH`, fuel pump icons, arrows, `ANTI-LOCK`,
  `CHECK ENGINE`, 14-segment alphanumerics. Author them as SVG, bake to an SDF
  texture at build time, sample in the shader via `setImageSampler`. One path for
  fonts, icons and warning legends, all inheriting the same halo maths. The
  `KM/H` and `MPH` legends are currently hand-stroked from `sdSeg` paths, which
  is fine for five glyphs and is not a route to an alphabet.
- **Trip computer.** The answer to the density problem, so it is not optional
  polish. See "The density problem".
- **Shipped presets**, authored last, against a model the editor has proven.
- Amber and red filter modes as first-class designs, not just a colour swap — the
  filter changes bloom falloff, not only hue.

Later:

- CarPlay / Android Auto. **Investigate before betting on it.** Both are template
  systems with restricted app categories; a gauge display does not obviously
  qualify, and the surface that allows custom drawing is the navigation one.
  Flutter support here is thin — assume a native Swift/Kotlin surface if it
  happens at all. Do not put this on a roadmap shown to anyone until validated.

## Non-goals

- Vehicle hardware integration. No OBD2, no adapters, no Bluetooth to the car.
  Anode reads the phone and nothing else. This is a product decision, not a
  deferral — see "Data sources: phone only".
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
- Responsive layouts. See "Orientation".