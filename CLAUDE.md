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
- **A sampled data texture carries data in RGB only, normalised to [0, 1].**
  Three separate traps, each of which silently produces a plausible-looking
  wrong render rather than an error:
  - *Alpha is not a data channel.* Pixel formats are premultiplied, so a value
    stored in alpha comes back scaled — and a texel whose alpha happens to be 0
    returns nothing at all. Always write 1.0 there. Three floats per texel.
  - *The range is clamped even though the format is float.* `rgbaFloat32` keeps
    full precision inside [0, 1] but pins anything outside it, so a width of
    1.035 reads back as 1.0 and a type id of 2 reads back as 1. Store scaled,
    and offset anything signed.
  - *Values do not survive exactly.* A count of 3 comes back very slightly
    above 3, so `k >= count` draws one item too many. Compare against a rounded
    count.
- **Halo width has to scale with feature size.** `halo()` is tuned for digit
  segments and its falloff is in design units, so reusing it on anything finer
  sums a dozen digit-sized lobes into one blown-out blob. The unit legends
  needed their own tighter falloff (`legHalo`) plus a weight. Any glyph smaller
  than a digit segment will hit this.
- The numeric constants in `vfd.frag` are visually tuned against reference
  photographs. Do not refactor, round, rename or extract them.

## Optical profiles and effect scope

Optical appearance is part of a design's identity, not an app-wide preference.
The old boolean `VfdLayers` implementation has been removed. Repository loading
migrates its legacy booleans into the baseline profile of stored legacy
dashboards; new global settings contain device preferences only.

An effect is declared once through generic metadata: stable id, label,
description, scope, calibrated default, minimum, maximum, step, precision, and
renderer transfer function. The editor builds every effect control from this
metadata. An effect needing a bespoke editor control is a model finding, not a
reason to special-case the panel.

Effect ids are persisted API. Add new effects under new ids; never reuse an id
for different physics. Deprecated effects may disappear from new-authoring
choices, but unknown stored values survive round-trip and appear as unavailable
in the editor rather than being silently discarded.

Strength is a calibrated multiplier, not a normalised fraction:

- `0.00` is off.
- `1.00` is the photograph-tuned ideal and must reproduce the current render
  without changing any tuned constant in `vfd.frag`.
- `2.00` is 200% overdrive. Start with this as the common ceiling; an effect may
  declare a lower safe maximum when its transfer function stops being useful.

The segmented strength bar marks `1.00` explicitly. Persist each authored value
as an `EffectSetting` containing `strength` and `resumeStrength`; enabled state
is derived from `strength > 0`, never stored as a second boolean. Turning an
effect off writes zero while retaining `resumeStrength`; turning it back on
restores that value. Overdrive scales the result around the tuned calculation.
It does not refactor, replace, or round the tuned shader constants.

The physical layer determines where a value may be authored:

- **Dashboard:** tilt/parallax and the baseline `OpticalProfile`.
- **VFD module:** glass grain, filament geometry, and sparse module optical
  overrides.
- **Component:** phosphor colour, emission strength, bloom, phosphor texture,
  control-grid strength, unlit-phosphor strength, and phosphor decay.

Glass grain remains glass/sensor noise after sheen. It is not a way to make one
anode brighter. Use component emission strength for brightness and phosphor
texture for local coating irregularity. Filaments are cathode wires belonging to
a physical VFD module, not to an anode component. A curved bar changes anode and
control-grid geometry; it does not bend a shared cathode around itself.

Resolution follows:

    dashboard baseline -> VFD module sparse overrides -> component sparse overrides

An absent override inherits. A present zero explicitly disables that effect. A
present positive value is local. The dashboard control panel always uses the
dashboard's phosphor colour and `PrismStyle`; selecting a red component in a
cyan-green dashboard makes that component red in the live canvas while the
panel and other components remain cyan-green.

App Settings contains user/device preferences only: sound, haptics, accessibility,
and any future renderer-quality switch that changes performance rather than
authored appearance. Do not duplicate authored effect controls in Settings.

## Dashboards, presets and components

A **DesignPreset** is shipped, immutable and versioned. A **Dashboard** is a user
instance. Editing a preset FORKS it into a Dashboard, which is then owned by the
user and never auto-updated. This is copy-on-customize. Do not implement
delta-merging against updated presets — it sounds more elegant and causes pain
forever.

Presets remain code-owned and never enter user storage. Dashboards, the active
design reference, and global settings are persisted through `shared_preferences`.
Editor drag writes are debounced so pointer movement does not write on every
event.

### Capabilities

Every component type declares what it needs: GPS, accelerometer, barometer,
network, trip storage. The app takes the union across the ACTIVE dashboard and
starts only those sensors and requests only those permissions. This is how the
barometer stays off for someone with no altimeter, and how network permission is
not requested for a layout with no weather gauge.

Interactive components contribute action capabilities through the same union.
The app exposes an extensible `ActionRegistry` of prebuilt actions such as
`media.playPause`, `media.previous`, and `media.next`. This is not a frozen
policy allowlist: app versions and platforms register whatever actions they
implement. A persisted action binding stores a stable action id plus generic,
validated params. Unsupported or removed ids are preserved and shown as
unavailable with a reason; they are never silently deleted or rebound.

Platform availability filters presentation, not persistence. A dashboard moved
between iOS and Android keeps an unsupported binding so it can work again on a
platform that provides the action. Arbitrary scripts and callbacks are not
design data.

### VFD modules

A dashboard may contain multiple physical VFD modules. This is a lightweight
optical grouping, not a second component tree:

- Every design has an implicit `main` module covering the authored frame.
- Legacy components and components with no `moduleId` belong to `main`.
- The component list stays flat. A component inspector exposes its module as a
  simple choice.
- Module management remains hidden until a second module is added.
- Deleting a module reassigns its components to `main`; it never deletes them.

Additional modules declare an authored region per supported orientation and own
their filament variant, glass grain, and sparse optical overrides. Components
still use frame-relative placements and reference their module by stable id.
This allows separate display envelopes to have different cathode layouts without
pretending every anode owns a filament. The renderer still composites all
modules and components in one pass.

Module ids are persisted API. Never reuse one inside a dashboard. An unknown
module reference survives round-trip, resolves through `main` for rendering, and
shows a missing-module warning until the user explicitly reassigns it. This is
different from deliberately deleting a known module, which performs the visible
reassignment described above.

### Component variants

A variant changes handcrafted geometry or minor rendering behaviour while
preserving the component's semantic job, data binding, capabilities, and
interaction model. The blocky, chamfered, and rounded seven-segment references
are variants of one numeric-display type. A swept needle gauge is not.

`ComponentTypeSpec` declares common params and available
`ComponentVariantSpec`s. `ComponentInstance` stores a stable variant id and
revision. A variant declares its label, renderer geometry, recommended size,
optional generic params, glyph mapping, and sizing constraints. The editor
merges common and variant param metadata; it does not add bespoke controls.

Variant references are persisted API:

- Never persist a shader ordinal. The renderer translates the stable string
  reference at its boundary.
- Never reuse an id or revision for different geometry.
- Adding a variant only registers a new reference.
- Deprecating a variant hides it from new selection but retains its renderer so
  existing presets and dashboards remain visually stable.
- Hard removal requires an explicit versioned migration. Unknown references and
  their unknown params are preserved, rendered with a visible fallback, and
  shown as missing in the editor; loading must not silently rewrite them.
- Payloads predating variants map to a fixed legacy revision, not whichever
  variant happens to become the future default.

Changing a component's variant preserves `Placement.size`. Different intrinsic
proportions fit inside that authored box. An explicit `RESET TO VARIANT SIZE`
action applies the recommended size; switching variants never moves or resizes
the layout silently. Variant choice is component-wide, like other params; only
placement currently varies by orientation. Two orientation-specific variants
therefore require two component ids until the broader per-orientation param gap
is solved.

### Orientation

Layouts are NOT responsive. These are designed instrument faces, not web pages. A
design declares which orientations it supports, and each supported orientation
gets its own AUTHORED layout — never a reflow of the other. Lock to supported
orientations while a design is active. Within an orientation, absorb the aspect
ratio spread (18:9 through iPad 4:3) with anchor-plus-offset positioning, not
absolute coordinates.

The authored frame aspect is also per orientation and lives on the design. It is
not inferred from the device and is not one global ratio reused after rotation.
Payloads written before this was expressible receive tolerant development
defaults on read.

### Authored and device settings

- Per-component: variant, speed unit, digit count, data binding, action binding,
  and sparse component optical overrides.
- Per-module: authored region, filament variant, glass grain, and sparse module
  optical overrides.
- Per-dashboard: orientation, baseline `OpticalProfile`, and `PrismStyle`.
- App-wide: sound, haptics, accessibility, demo mode, and renderer quality only.

### Build order

The editor is built EARLY, before the shipped presets are authored. It is a
forcing function: if components are genuinely data, an editor manipulating that
data proves it; if they are hardcoded layouts in disguise, the editor exposes
that immediately. Presets authored before the editor exists will encode
assumptions the editor breaks.

The first Stage 4 boundary deliberately built a plain-Material developer editor
to stress placement, params, persistence, and copy-on-customize. Before any
shipped preset is authored, extend that editor with live optical controls and
the reusable Prism control system. This is still model work: generic effect
metadata, inheritance, variants, modules, and actions must prove themselves in
the editor before preset authoring starts.

Prism controls become editor-wide UI. Do not spend this pass on onboarding or
unrelated ornament, but the Prism button's bevel, light, press depth, sound, and
haptic response are functional requirements rather than optional polish.

## Screens

The speedometer is the root screen and is standalone. A dimmed gear in the bottom
right auto-hides after a few seconds and returns on an unclaimed tap on the inert
background. Taps claimed by explicit interactive components invoke only their
bound action.

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

- The primary control primitive is the **Prism button**: smoked acrylic with a
  dark face, an integrated recessed mounting socket, thin transparent chamfer,
  hard neutral perimeter reflections, and visible extrusion. It comes from
  moulded automotive switchgear, not generic frosted-glass or glassmorphism UI.
- Enabled and pressed are independent states. An active button rests raised and
  lit; an inactive button rests raised and dark; pointer-down depresses either
  one temporarily. Only the cap translates by seven percent of its height; the
  socket and layout never scale or move. Reduced-motion mode applies the same
  state immediately.
- The active light follows the dashboard phosphor colour. Component optical
  overrides never recolour the surrounding panel. Illumination belongs to the
  backlit legend plus a faint internal diffuser wash; no status dot and no
  cyan-filled face.
- Prism legends use the bundled Barlow Condensed Medium Italic switchgear face,
  uppercase with restrained tracking. Prefer a word to an icon — `RUN` and
  `HOLD` read more period-correct than a play triangle. Flutter and shader
  renderers share a 24-glyph ASCII visual contract; unsupported characters
  degrade to `?` without rewriting persisted text.
- Flutter control widths are physical one-, two-, or three-unit spans. Text
  never invents an arbitrary cap width. Selection and keyboard focus use
  external locator ticks so neither can masquerade as the active lamp.
- Anything showing a quantity uses the segmented cell bar on the same rule as
  the gauge: cell `i` is lit when `(i + 0.5) / n <= fraction`. A continuous
  Material slider does not belong on this substrate.
- Dense banks of buttons are intentional period language, not a dashboard-card
  grid to simplify away. Establish hierarchy through button size, bezel depth,
  grouping, spacing, label scale, and controlled luminous intensity. Reserve a
  consistent light treatment for state so hierarchy never makes an inactive
  control look active.
- Sound and haptics are app preferences. One low-latency physical click and one
  actuation haptic are enough initially; no per-design sound packs.

Use shared button semantics with two renderers:

- `PrismButton` is the Flutter control used by panels, navigation, and the
  editor. It owns focus, semantics, keyboard/pointer input, press animation,
  sound, and haptics.
- A prism design component is data-driven geometry inside the existing shared
  VFD render pass. It receives state through the controller/data texture so its
  light compounds correctly with neighbouring emission. Its Barlow legend
  samples one app-wide SDF atlas; glyph indices reuse the component row's digit
  payload and require no per-button surface. Its opaque socket masks module
  filament wires.

Do not force both through one renderer. Do not give design components their own
widgets or fragment surfaces.

Effect selection is a non-scrolling button grid. Tapping an effect button
selects its detail; it does not toggle the effect. The detail shows label,
physical description, segmented strength bar, precise number, minus/plus
steppers, and an explicit power control.

With no component selected, the editor shows `DESIGN EFFECTS`. With a component
selected it shows a named `LOCAL EFFECTS` context. Each local effect exposes
`INHERIT` / `OVERRIDE`; inherited values remain visible but read-only. Changing
an override updates the selected component live. The panel itself continues to
use dashboard styling. Keep context labels visible so selecting a component
cannot silently change what identical controls mean.

An immutable preset exposes effect values read-only. `CUSTOMIZE` performs the
same explicit, visible fork as Edit before any value can change. Never silently
fork a preset on a slider drag.

### Navigation, explicit controls, and no root gestures

**The cluster background is inert.** No whole-screen long-press, swipe, or
double-tap. The phone lives in a windshield mount that gets bumped, and a hand
bracing against the device produces exactly the gesture a long-press detector
is looking for. A mistouch that opens an editor over a driver's instrument is
the worst failure this app can have.

Explicit interactive design components are allowed. Their authored placement is
their visible hit region, and they invoke prebuilt actions from the
`ActionRegistry`. Invisible Flutter hit regions and accessibility semantics may
sit above the renderer, but they must not paint or create per-component visual
surfaces. Press state goes through the render controller and keeps
`CustomPainter(repaint: controller)`; do not rebuild the widget tree per frame.

Pointer-drag tilt remains a desktop and development affordance only. On device,
tilt comes from the gravity vector.

Library, Settings, and editing sit behind one deliberate path:

    cluster --gear--> dock --[Library]--> route with tabs
                                          [ Designs | Settings ]

Tapping a design card activates it; opening the editor requires the card's
separate, explicit Edit button, so nothing is editable in fewer than three
deliberate taps. A design's explicit media or trip-computer buttons do not open
editing or navigation accidentally.

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

The editor uses one live, shared render of the whole design plus non-painting
selection/drag/resize overlays. It does not embed component shaders or create
per-component raster surfaces. Selection chrome may be lifted above the canvas
so handles remain reachable; this does not change component list order or
runtime z-order.

### Model findings from the developer editor

The editor exists to expose these. Keep unresolved findings visible rather than
special-casing controls around them:

- **Resolved during Stage 4:** a design could not express the authored frame
  aspect. `frameAspects` now stores it per orientation on presets and dashboards.
- **Unresolved:** params are global to a component id. Only placement varies by
  orientation. A three-digit landscape readout and two-digit portrait readout
  therefore require two component ids with mutually exclusive placements.
- **Confirmed acceptable for current faces:** runtime z-order remains component
  list order. Editor reordering edits that list globally; it did not need a
  separate layer field or a per-orientation order. If overlapping instrument
  geometry becomes a real design requirement, revisit this decision.
- **Resolved during the extension:** `ParamSpec` now declares option labels,
  numeric step/precision, and unit suffix, including variant-specific params.
- **Resolved during the extension:** lightweight `VfdModule`s own authored
  regions, filament references, glass grain, and sparse overrides. A component
  references exactly one module; overlapping/shared envelopes are not
  expressible without adding another grouping relation.
- **Resolved during the extension:** `OpticalProfile` and sparse overrides
  express calibrated dashboard, module, and component appearance. Optical
  values remain component-wide, not per-orientation; different portrait and
  landscape optics require separate component ids just like different params.
- **Resolved during the extension:** component instances carry stable,
  revisioned variant references. Unknown references and params survive and show
  a missing fallback. No handcrafted shipped variants were authored in this
  pass.
- **Resolved during the extension:** persisted action bindings and non-painting
  hit semantics invoke an open runtime registry. Binding params are generic.
- **New unresolved interaction-state gap:** a design button can persist one tap
  action and a static `lit` param, but cannot bind its lamp or legend to runtime
  action state, declare long-press/double-press behaviour, or choose separate
  press/release actions. Play/pause state feedback will require a declarative
  state binding rather than callbacks in design data.
- **Resolved during the Prism fidelity refinement:** shader Prism components
  render their arbitrary persisted labels through a shared Barlow SDF atlas.
  The visual subset is uppercase ASCII UI text, 24 glyphs maximum; unsupported
  glyphs render `?` and longer labels render 21 glyphs plus `...`, while the full
  source string remains persisted.
- `outsideTemp`, `phoneBattery`, and `altitude` are expressible and editable as
  component data, but the current shader intentionally skips them. This is a
  renderer coverage gap, not a reason to hardcode or remove them from the
  registry.

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
- **Stage 4 optical editor extension.** Live shared-render canvas, calibrated
  optical profiles, lightweight VFD modules, revisioned component variants,
  interactive action bindings, and editor-wide Prism controls. Complete and
  review this before Stage 5 or shipped preset authoring.
- **Extend the SDF contract to irregular VFD glyphs.** Stage 4 now has a baked
  Barlow atlas for physical Prism switch legends. Real VFD anodes still need
  etched shapes that are not that switch font: fuel pump icons, arrows,
  `ANTI-LOCK`, `CHECK ENGINE`, and 14-segment alphanumerics. Author them as SVG,
  bake them beside or into a dedicated anode atlas, and preserve their own halo
  maths. `KM/H` and `MPH` remain hand-stroked from `sdSeg`, which is fine for
  five glyphs and is not a route to that broader library.
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
