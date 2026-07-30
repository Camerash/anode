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

Every design owns a primary fixed `FrameSpec` and may own one explicit
opposite-orientation alternate. A `FrameSpec` stores an **extent** — width and
height in design units — not a bare aspect. The authored extent is
**contain-fitted inside the safe rect**, picking the tighter axis and centring
the frame. A missing alternate uses the primary unchanged; content never
rotates. Contain fit never crops or clamps component placement. The safe rect
governs placement only, so halo, sheen, and grain keep evaluating across the
full fragment bounds and spill past both the frame and screen edge.

**A design unit is frame-independent.** It is a physical unit of the tube face,
roughly the height of the module in the reference photographs — it is not "the
height of the frame". This matters because every optical constant in `vfd.frag`
is expressed in design units: halo lobe falloff, control-grid pitch, filament
diameter and spacing, phosphor coating grain, segment edge softness, tilt shift.
If the meaning of a unit varied with the shape of the frame, changing a frame's
aspect would silently rescale the entire optical stack. It did: a frame once
carried only an aspect and was implicitly one unit tall, so creating a portrait
alternate from a landscape primary raised px-per-design-unit about 4.6× and
bloomed every effect while the geometry, shrunk to compensate, held still. The
absence of this paragraph is what allowed that. Do not reintroduce a frame
whose height is assumed.

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
  Renumbering in place is fine and has been done once, when the scalar `uAspect`
  became the `vec2` `uFrame`; appending instead would have left a dead float
  behind forever. `VfdPainter.paint` asserts that writing one float past the end
  throws, so a uniform added on the shader side without a matching `setFloat`
  fails loudly instead of rendering plausibly and wrongly.
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
  - *The sampled path is 8-bit normalised even though the upload is
    `rgbaFloat32`.* It pins anything outside [0, 1], and a single channel has
    only 256 sampled states. Store scaled. Every geometry scalar uses high/low
    bytes for 16-bit precision; position signs are folded into integer metadata
    rather than spending a geometry channel.
  - *Geometry low bytes deliberately dual-use payload lanes.* Non-Prism rows
    use the two spare RGB lanes in each digit's nine-lane payload; Prism rows
    use lanes after the maximum 24 glyphs. Do not fill those lanes with new
    segment or glyph data without relocating all eight geometry low bytes in
    both `component_data.dart` and `vfd.frag`.
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
The old boolean `VfdLayers` implementation has been removed. The unreleased app
uses schema 5 and deliberately rejects old dashboard payloads rather than
carrying migration code; global settings contain device preferences only.

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

The automotive strength lever double-marks `1.00` as its tuned reference.
Persist each authored value as an `EffectSetting` containing `strength` and
`resumeStrength`; enabled state
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
event. Schema-5 dashboard and active-design preferences use v2 keys. The app is
unreleased, so older dashboard schemas are rejected rather than migrated;
uninstall/reinstall is the supported development reset.

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

Additional modules declare a region per explicitly authored layout and own
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

Every design has one fixed-aspect primary authored layout. Landscape is the
default because physical automotive faces are normally landscape, though the
model retains explicit primary identity for intentionally portrait designs.
`frameSpecs` entries mean authored layouts; they are not a list of device
orientations the app supports.

Runtime chooses an explicitly authored layout matching the current viewport
orientation. When none exists, it renders the primary layout unchanged and
contain-fits it in the viewport. It never rotates content, reflows elements, or
synthesizes a portrait arrangement. A landscape primary therefore remains a
horizontal landscape face centred inside a portrait window.

The editor previews the current window orientation first. A fallback preview is
read-only, and it draws the **device envelope** the runtime would fill, with the
inherited primary contained and dimmed inside it. That is what the runtime
actually shows, so `CREATE` is visibly a promotion of exactly what is on screen.

`CREATE PORTRAIT` or `CREATE LANDSCAPE` explicitly adds an independent
alternate. Its extent comes from the **device safe rect measured at the current
fit scale**: given a primary of extent `(pw, ph)` and a device rect `(W, H)`
oriented to the target, `s = min(W/pw, H/ph)` and the new extent is `(W/s, H/s)`.
Placements are then copied **verbatim** — nothing is rescaled. This is what makes
"no runtime visual jump" structural rather than something a test has to police:
the geometry does not move, and because a design unit still means the same
thing, neither does the optical layer. Both the read-only preview and the bake
call one shared function, so they cannot disagree.

The device rect is measured above the editor's own `SafeArea`. A cramped editor,
an open service bay, or a full-screen session must never bake a different
envelope.

The alternate can then diverge freely or be reset to primary fallback.
Export/import preserves primary identity, every authored frame extent, and every
authored placement.

There is no orientation lock and no adaptive frame mode. The app itself remains
fully resizable and supports iPad orientations and Split View; contain fitting
absorbs window changes without mutating design data. Adaptive responsive
authoring is deferred until a concrete same-orientation instrument needs it.
Placement stores only absolute centre and size; no anchor or span metadata
participates in runtime fitting.

### Authored and device settings

- Per-component: variant, speed unit, digit count, data binding, action binding,
  and sparse component optical overrides.
- Per-module: authored region, filament variant, glass grain, and sparse module
  optical overrides.
- Per-dashboard: primary/alternate layouts, baseline `OpticalProfile`, and
  `PrismStyle`.
- App-wide: sound, haptics, accessibility, demo mode, and renderer quality only.

### Build order

The editor is built EARLY, before the shipped presets are authored. It is a
forcing function: if components are genuinely data, an editor manipulating that
data proves it; if they are hardcoded layouts in disguise, the editor exposes
that immediately. Presets authored before the editor exists will encode
assumptions the editor breaks.

The first Stage 4 boundary deliberately built a plain-Material developer editor
to stress placement, params, persistence, and copy-on-customize. That exemption
ended during the Stage 4 mechanical refinement: no visible Material control,
route transition, content scroller, or app shell remains. Before any shipped
preset is authored, the editor must continue proving generic effect metadata,
inheritance, variants, modules, and actions without falling back to stock form
controls.

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

### Runtime screen has no configuration dock

Active dashboard is the instrument, not a live configuration surface. `SET`
opens Library Settings directly. Dashboard optics, Prism style, components, and
placement change only in the design editor. Debug-only `RUN`, manual speed, and
unit controls live in a separate workbench route and never mutate persisted
design state.

Fixed frames always scale uniformly and letterbox. Editor service chrome may
reduce available preview space, but it must recompute the same contain fit; it
never changes authored coordinates or frame aspect.

### Config UI is in the VFD idiom

Every user-facing control surface — editor, Library, and Settings — is drawn
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
- A physical Prism cap has one immutable legend. A binary control names the
  asserted state (`FULL`, `OVERRIDE`, `VISIBLE`, `RUN`); illumination says
  whether that state is active. It never swaps to `EXIT`, `INHERIT`, `HIDDEN`,
  or `HOLD` when dark. Multi-choice state uses separate fixed-label keys, such
  as `KM/H` and `MPH`, rather than one cap whose print changes. Momentary
  commands retain one fixed action verb.
- Flutter control widths are physical one-, two-, or three-unit spans. Text
  never invents an arbitrary cap width. Selection and keyboard focus use
  external locator ticks so neither can masquerade as the active lamp.
- Gauge-like quantities and generic bounded params use the segmented cell bar.
  Optical and Prism-style values use the recessed automotive lever described
  below. A continuous Material slider does not belong on either substrate.
- Dense banks of buttons are intentional period language when the functions are
  familiar and individually useful. They are not permission to expose renderer
  internals as an unlabeled keypad. Establish hierarchy through button size,
  bezel depth, grouping, spacing, label scale, and controlled luminous
  intensity. Reserve a consistent light treatment for state so hierarchy never
  makes an inactive control look active.
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

The editor section is named `LOOK`, not `OPTICS`. Its normal fascia exposes two
decisions only: the current phosphor colour and a `TUNE` latch. Tapping the
colour hard-cuts to the three labelled phosphor choices; local scopes also
offer `USE DESIGN` to clear the phosphor override.

`TUNE` retracts the fascia vertically behind a fixed lower service lip and
reveals a fixed-footprint service face. The surrounding service bay and canvas
do not change size. The shutter releases for 20ms, travels at constant rate for
110ms, and hard-seats for 20ms. It never rotates, scales, eases, or collapses in
perspective; a narrow moving edge and shadow provide its only simulated depth.
The service face shows one effect at a time: previous and next Prism keys with hard
stops, an indexed position readout, the effect's name and physical description,
a small secondary pictogram, inheritance control where local, exact value, and
one recessed automotive lever. No effect overview grid, pager or scrolling
exists. The last selected service channel is editor-session state only.

Pictograms remain hand-authored period line art from non-persisted `EffectSpec`
metadata, but never identify a control without its name. Unknown stored ids
remain in the indexed sequence, show a `?`, expose their exact read-only value,
and survive round-trip. Closing the hatch changes no authored value.

`MechanicalLever` is a cable-driven HVAC control: fixed recessed black
faceplate, narrow horizontal slot, smoked/chrome rectangular thumb, 44px thumb
hit region, and no inertial motion. Only direct thumb drag changes value; track
taps never teleport it. Every visible mark is a real detent: the thumb, stored
value, keyboard/wheel step, semantics action, illuminated marker, and feedback
all resolve to the same detent value. Optical levers have 21 detents from
`0.00` through `2.00` at `0.10` intervals, label the left stop `OFF`, and
double-mark the reachable tuned reference. Prism-style levers use 11 detents;
if their tuned default is not on the uniform sequence, it replaces the nearest
interior mark so it remains an exact reachable double detent. Values never move
smoothly between illuminated marks.

With no component selected, the `LOOK` fascia edits the dashboard profile. With
a component or module selected it names that local context and displays whether
its phosphor and current service channel use the design value or a local
override. Each local service effect exposes `INHERIT` / `OVERRIDE`; inherited
values remain visible but read-only. Changing an override updates the selected
object live. The panel itself continues to use dashboard styling. Keep context
labels visible so selecting an object cannot silently change what identical
controls mean.

An immutable template can activate or clone only. Clone opens a confirmation
surface with optional naming, then creates and activates a dashboard before
opening the editor. User designs can activate, clone, or edit. Never silently
fork from Edit or from a slider drag.

### Mechanical UI contract

The whole app is switchgear, not a Material app wearing a VFD theme:

- `WidgetsApp` supplies navigation, focus, semantics, and native text input.
  Routes cut directly with no transition.
- User content never uses a kinetic `Scrollable`, `ListView`, or `PageView`.
  Native caret and selection scrolling inside `EditableText` is the one
  exception.
- Overflow becomes fixed pages. A detented rail selects an integer page,
  snaps its carriage in 60ms, exposes adjustable semantics, and has Prism
  previous/next controls when height permits them. Crossing one detent emits one
  configured click/haptic.
- Hidden service surfaces move as mechanisms. A drawer releases its latch for
  20ms, travels linearly for 130ms, and hard-seats for 30ms. The LOOK service
  shutter releases for 20ms, retracts linearly behind a fixed lip for 110ms,
  and hard-seats for 20ms. Both faces occupy the exact same footprint; the
  shutter never expands the panel, moves the canvas, scales, or uses perspective.
  Reduced-motion resolves moving mechanisms immediately.
- Continuous direct manipulation remains for component drag/resize, levers,
  and segmented value bars. This is not content navigation and must not acquire
  fling or inertial behaviour.
- Text and unbounded-number authoring use a recessed `EditableText` field so
  platform keyboard, caret, selection, and accessibility behaviour survive
  beneath custom chrome.
- Fork and other route feedback uses a persistent VFD annunciator with explicit
  acknowledgement. It is never a transient snackbar.

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

Library, Settings, and editing sit behind explicit controls:

    cluster --SET--> Library(Settings)
    cluster action --> Library(Templates | Designs | Settings)

Template card tap activates; `CLONE` confirms and optionally names a new user
design before opening its editor. User-design card tap activates; `CLONE` and
`EDIT` are separate actions. A design's media or trip-computer buttons do not
open editing or navigation accidentally.

There is deliberately **no motion lock**. Everything stays reachable at any
speed; this was considered and rejected as paternalistic, and the three-tap
depth already rules out accidental entry.

### The editor is its own route

Editing needs persistent chrome that tuning does not, so it gets a dedicated
screen: a contain-fit authored canvas plus a component list and inspector. On
entry, current window orientation is previewed. The top switch chooses portrait
or landscape viewport. If no matching alternate exists, it shows the contained
primary read-only and offers explicit creation.

The editor canvas is the one place a visible frame edge is correct. Every
authored frame holds its reference aspect regardless of window shape and scales
to fit. Matte outside the double boundary dims rendered component portions
without clipping their hit regions; off-frame elements remain selectable,
draggable, and resizable. `BRING IN` moves each recoverable axis only far enough
to contain the border box; an axis wider than the frame centres. Size never
changes.

The editor uses one live, shared render of the whole design plus non-painting
selection/drag/resize overlays. It does not embed component shaders or create
per-component raster surfaces. Selection chrome may be lifted above the canvas
so handles remain reachable; this does not change component list order or
runtime z-order.

The 48px top rail contains only `BACK`, dashboard identity, and orientation.
Every other control lives in one manually latched service bay. Its edge follows
the current route window, never the preview orientation: `height > width` pushes
from the bottom; `width >= height` pushes from the right. Opening it reduces
available preview bounds, then
re-contain-fits the same authored frame. It never changes authored coordinates,
fixed aspect, or element size. The closed bay leaves a 44px triangular latch.

There is no camera mode switch. One pointer gesture is resolved at pointer-down
by explicit hit-testing against known screen-space rects, topmost first, corner
before edges:

- Tap a component to select it and reveal its handles.
- Drag a **selected** component to move it; drag its handles to resize.
- Drag an unselected component, or empty substrate, to pan the camera.
- Two or more pointers always drive the camera, including a promotion part-way
  through an element drag. A promoted gesture never falls back to moving the
  element, and the placement freezes at the value it had when the second pointer
  landed.

Camera scale is clamped 1×–4×; `FIT` restores identity. Camera transforms never
write placement.

Canvas controls are `SNAP`, `FIT`, and `FULL`. `SNAP` is illuminated and active
by default, lives only for the editor session, and survives preview/full-screen
switches. It affects component and module drag/resize only. A gesture quantizes
its total design-space delta to `0.005` relative to the pointer-down placement,
so toggling SNAP never mutates existing off-grid geometry. With SNAP dark,
movement and resize are fully continuous. Selection chrome always derives from
the same committed placement sent to the renderer. Authored geometry refreshes
synchronously with the editor rebuild rather than waiting for the optical
animation ticker, so the border and shader commit the same placement in the
same widget frame. Optical flicker, decay, and tilt remain ticker-driven.

The canvas drives the camera itself from a single `Listener` rather than nesting
an `InteractiveViewer`. Its scale recogniser is an arena member that wins over
child pan recognisers once a second pointer lands and can steal a single-pointer
drag after slop, and "drag an unselected component to pan" is not expressible
through per-component recognisers at all — the child must reject before the
parent has seen any movement. Explicit hit-testing is deterministic and testable
headlessly. Do not reintroduce nested gesture recognisers here.

Selection chrome and resize handles live in screen space, above the camera
transform, so a handle stays a constant 44px at any zoom and the hit test never
has to undo the transform. The overlay paints and carries semantics; it does not
consume pointer events.

`FULL` hides the rail and the service bay and gives the canvas the whole route,
so the render is at exactly runtime scale. Selection, drag, resize and camera all
keep working. It is a state flag, not a route, so selection and the render
controller survive entering and leaving it.

Right, bottom, and bottom-right resize handles retain small visual grips but
have 44x44 touch regions, straddling the border they resize rather than sitting
inboard of it. Edge resizing applies one pointer delta, not the old
symmetric two-delta transform. The grabbed right/bottom edge moves; the
opposite edge remains fixed by shifting the resolved centre by half the applied
size delta. Minimum size is `0.03`, with centre correction applied after
clamping. Placements remain intentionally unclamped to the frame.

`Placement` is schema-5 absolute geometry: required `center: Offset` and
required `size: Size`, persisted only as `x`, `y`, `w`, `h`. Fixed authored
frames and contain-fit make anchors and span axes redundant. Alternate creation
copies placements verbatim. PLACE is one non-paged surface: precise X/Y, 3×3
D-pad with centre `BRING IN`, and W/H minus/readout/plus rows. D-pad and size
buttons always step `0.005`, independent of SNAP.

### Model findings from the developer editor

The editor exists to expose these. Keep unresolved findings visible rather than
special-casing controls around them:

- **Resolved during Stage 4 follow-up:** one primary fixed layout always exists;
  an optional opposite-orientation layout is explicit. Missing alternates
  render the primary through contain fit with no content rotation. Creating an
  alternate bakes that contained appearance before independent editing.
- **Resolved by schema 5 simplification:** anchors and span axes were removed.
  Fixed authored frames need only absolute centre and size; contain-fit handles
  viewport mismatch without layout alignment metadata.
- **Resolved during Stage 4 follow-up:** imported unknown component types remain
  serialized instead of being silently dropped. Renderer/editor availability is
  separate from lossless design transport.
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
- **Resolved during the frame-extent refinement:** a frame carries an extent, not
  an aspect, so a design unit is frame-independent and optical scale no longer
  moves when a frame's shape does. Alternates are created by growing the
  envelope, not by shrinking the contents.
- **New finding, unresolved:** filament span is frame-derived, not authored.
  `filamentHalfWidth` is `0.62 * moduleSize.x / uFrame.x`, so a sub-module's wire
  span is a fraction of the frame rather than a property of the module. That is
  wrong physically — cathode length belongs to the tube — but the constant is
  photograph-tuned and folding the frame width into it would produce a rounded
  derivative of a tuned value. Fix it by making filament span an authored module
  property, not by rewriting the expression.
- `outsideTemp`, `phoneBattery`, and `altitude` are expressible and editable as
  component data, but the current shader intentionally skips them. This is a
  renderer coverage gap, not a reason to hardcode or remove them from the
  registry.
- **Unwired, and not a model gap:** `VfdAnnunciator` exists and has no call
  sites, while this file mandates it for fork and route feedback. It is the wrong
  vehicle for a read-only badge — it demands explicit acknowledgement — so the
  read-only preview dims instead. The mandate is still unmet elsewhere.

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
