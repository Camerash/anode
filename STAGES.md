# Anode — stage plan and status

Working notes for whoever picks this up. Architecture and rationale live in
`CLAUDE.md`; this file only tracks what is done, what is next, and what is
known-broken. Read `CLAUDE.md` first — it is the spec, and several decisions in
it were made specifically to close off approaches that look reasonable.

**Each stage ends in a commit before the next begins.** Stages are reviewed at
their boundary.

| Stage | What | Status |
|-------|------|--------|
| 1 | Full bleed | Done — `444a836` |
| 2 | Component data model | Done — `bdd4d01`, `80831c0` |
| 3 | Single-pass renderer | Done — `de91249` |
| 4 | Editor as developer tool | Not started |
| 5 | Speed estimation | Not started |

---

## Stage 1 — full bleed — DONE

Commit `444a836`.

- [x] Bezel mask — there was none in `vfd.frag`; nothing to remove.
- [x] `ClipRRect`, `AspectRatio`, `ListView` workbench removed; cluster is root.
- [x] Contain-fit of the authored frame inside a safe rect passed as uniforms.
      Placement only — no mask, no clamp, so halo/sheen/grain still spill past
      the safe rect and off the screen edge.
- [x] System UI hidden (`immersiveSticky`), screen kept awake (`wakelock_plus`).
- [x] Content insets to safe area, background does not.
- [x] Stacked `KM/H` / `MPH` legends, stroked from `sdSeg` paths.
- [x] Runtime controls docked in the contain-fit dead space, in the VFD idiom.

Two shader defects found and fixed while verifying, both recorded in
`CLAUDE.md` under "Flutter shader constraints":

- Bar cells folded each pixel into one `mod()` cell, so halos died on cell
  boundaries and the strip's bloom terminated on a hard rectangle.
- `halo()` is tuned for digit segments and its falloff is in design units, so
  the finer legend strokes summed a dozen digit-sized lobes into a blob.

---

## Stage 2 — component data model — DONE

Commits `bdd4d01` (model) and `80831c0` (independent sizing).

- [x] `lib/model/` — capability, param spec, component type registry,
      placement, component instance, preset, dashboard, settings, capability
      union.
- [x] Copy-on-customize: `Dashboard.forkFrom` snapshots wholesale, records
      source id and version as provenance only. No delta-merging, ever.
- [x] Per-orientation authored layouts; a missing placement means the component
      does not exist in that orientation.
- [x] Anchor-plus-offset positioning, resolved against the frame aspect.
- [x] Independent width and height on `Placement.size`.
- [x] Capability union, optionally scoped to one orientation.
- [x] Hand-written tolerant serialization: unknown type dropped, unknown
      orientation ignored, out-of-range params clamped, unknown params kept.
- [x] 41 tests in `test/model/` and `test/render/`.

Deliberately not done: z-order is implicit list order. Components do not
overlap on a VFD face, so an explicit layer index would have no reader.

---

## Stage 3 — single-pass renderer — DONE

One `FragmentShader` for the whole screen, consuming the component list. This
is a correctness constraint, not a performance one: per-component shaders would
each be their own raster surface and halos could not compound across component
boundaries.

- [x] `lib/vfd/component_data.dart` — packs components into a float texture.
- [x] `vfd.frag` rewritten: samples `uData`, loops `MAX_COMPONENTS` with a
      guard, dispatches on type id, and accumulates every component into the
      same shared `glow` / `core` / `dim`.
- [x] `VfdController` builds `ComponentFrame`s from the active dashboard and
      re-uploads the texture only when the packed bytes actually change.
- [x] `CustomPainter(repaint: controller)` kept; no `setState` per frame.
- [x] `lib/model/dev_design.dart` — development scaffolding reproducing the
      previously hardcoded layout. **Not an authored preset**; those come last.
- [x] **Visual parity check against Stage 1.** Digit spacing, bar pitch and
      legend placement all reproduce the previous render.
- [x] **Acceptance test: halo compounding.** `integration_test/halo_compounding_test.dart`.
      Renders each component alone and both together, then compares the
      luminance profile. Passes: the gap is brighter with both lit than with
      either alone, and the profile inside the gap is smooth.

### Texture format — read this before touching `component_data.dart`

Three separate traps here, each of which produced a plausible-looking wrong
render rather than an error. All three cost a device round trip to find.

**1. Only RGB carries data. Alpha is always 1.0.** Pixel formats are
premultiplied, so a payload value stored in alpha comes back scaled — or zeroed
when the value happens to be 0. Storing a spare `0` in alpha blanked every
component; the symptom was a near-black screen with only filament wires.

**2. The range is clamped to [0, 1] even though the format is float.**
`rgbaFloat32` keeps full precision inside that range but pins anything outside
it. A width of 1.035 read back as 1.0, and the bar's type id of 2 read back as
1 — so the bar and the legend both rendered as one-digit speed readouts.
Everything is now stored scaled, with an offset for signed values:
`positionRange`, `sizeScale`, `typeScale`, `countScale` in
`component_data.dart`, mirrored in `vfd.frag`.

**3. Values do not survive exactly.** A digit count of 3 comes back very
slightly above 3, so `float(k) >= count` drew a fourth digit — visible as a
phantom digit box sitting on top of the unit legend. The shader compares
against a rounded count instead.

Layout, mirrored between `component_data.dart` and `vfd.frag`:

    texel 0:        type, cx, cy
    texel 1:        w, h, paramA
    texel 2:        paramB, spare, spare
    texel 3 + 3k:   digit k segments 0..2
    texel 4 + 3k:   digit k segments 3..5
    texel 5 + 3k:   digit k segment 6, spare, spare

`paramA` is digit count, cell count, or lit unit index depending on type.
`paramB` is the bar's fill fraction. The segment buffer keeps a stride of
eight — seven segments plus a spare for a future decimal point.

### Known constraint: `decodeImageFromPixelsSync` is Impeller-only

Skia does not implement it, so it throws under `flutter test`, which runs
headless on Skia. Consequences:

- Any widget test that pumps `VfdCluster` must run under `integration_test` on
  a device, not `flutter test`. The halo acceptance test already does.
- The precision question was answered on device rather than by a probe: values
  inside [0, 1] survive with full float precision, values outside it are
  clamped. Hence the normalised encoding above.

### Float uniform index map

`vfd.frag` and `VfdPainter.paint` must stay in sync. Add new uniforms at the
end and renumber both sides together.

| Floats | Uniform |
|--------|---------|
| 0, 1 | `uSize` |
| 2 | `uTime` |
| 3 | `uTilt` |
| 4–6 | `uPhosphor` |
| 7–10 | `uLayers` (bloom, unlit, grid, filament) |
| 11 | `uGrain` |
| 12, 13 | `uSafeMin` |
| 14, 15 | `uSafeMax` |
| 16 | `uAspect` |
| 17 | `uCount` |
| 18, 19 | `uDataSize` |

Sampler 0 is `uData`.

---

## Stage 4 — editor as developer tool — NOT STARTED

Built BEFORE the shipped presets are authored, as a forcing function on the
data model. Plain Material widgets, no onboarding, no polish — see "Build
order" in `CLAUDE.md`. The editor is exempt from the VFD idiom while it is a
developer tool.

- [ ] Editor route with an aspect-locked canvas. The canvas holds the target
      orientation's aspect regardless of the window and scales to fit, with a
      visible frame boundary — the one place a visible edge is correct.
- [ ] Add, remove, reorder components from the `ComponentTypes` registry.
- [ ] Drag to reposition; writes `Placement.offset` for the displayed
      orientation ONLY.
- [ ] Resize handles writing `Placement.size` (width and height independent).
- [ ] Params rendered generically from `ParamSpec`. A param needing a bespoke
      control is a finding about the model, not a reason to special-case it.
- [ ] Orientation switcher, so both authored layouts are editable on one device.
- [ ] Fork a preset into a dashboard, visibly.
- [ ] **Deliverable: a written list of everything the model could not express.**
      That list is the actual output of this stage.

Already-known gaps to fold into that list:

- No per-orientation param overrides. Only placement varies per orientation, so
  3 digits in landscape and 2 in portrait needs two components with two ids.
- Z-order is implicit list order (deliberate, see Stage 2).

Also outstanding from the navigation decision, which needs the model and so
could not be built in Stage 1:

- [ ] Library route reached from the dock, with `Designs` / `Settings` tabs.
      Card tap activates; a separate explicit Edit button opens the editor.
      The dock has no Library button yet — do not ship a dead control.

---

## Stage 5 — speed estimation — NOT STARTED

Scope is bounded by "The trap" in `CLAUDE.md`. **Do not implement full IMU
velocity fusion.** The phone sits at an unknown mount angle; `accel.y` is not
forward acceleration.

- [ ] ZUPT stationary detector on accelerometer magnitude variance, which is
      rotation-independent and so needs no mount-angle knowledge. Use
      double-threshold hysteresis; a single fixed threshold misfires both at
      rough idle and at steady highway cruise.
- [ ] Render-loop extrapolation between GPS fixes. `VfdController` already ticks
      independently of the speed source.
- [ ] Acquiring state: blank digits with unlit segments visible. Never a bare
      `0`. `SegmentBank` needs an explicit blank mode.
- [ ] Demo mode, user-facing, backed by `SimulatedSpeedSource`.
- [ ] Wire `GpsSpeedSource.start()` — it currently throws `UnimplementedError`.
      Verify the geolocator 14.x API surface first. Add the iOS `Info.plist`
      usage strings and the Android manifest permissions.
- [ ] Gate sensor startup on the Stage 2 capability union.

---

## Cross-cutting, not yet scheduled

- [ ] **Cached emission layer.** Digits change once or twice a second. Render
      emission to a `ui.Image` via `PictureRecorder.toImageSync()` on value
      change, composite grain, multiplex flicker and sheen over it every frame.
      First optimisation to reach for when profiling, not before.
- [ ] **Filament wires are still global**, positioned around where the digits
      used to be hardcoded (`0.11 ± 0.215`, gated to `|q.x| < 0.62`). They
      belong to the tube, not to a component, so they should span the frame
      rather than track a gauge. Visible as an inconsistency the moment a design
      moves the digits.
- [ ] **Tilt on device should come from the gravity vector**, not the pointer.
      The full-screen `Listener` is a desktop and development affordance and
      must not survive onto the instrument — see "no root gestures" in
      `CLAUDE.md`.
- [ ] Baked SDF atlas for irregular glyphs. The `KM/H` and `MPH` legends are
      hand-stroked, which is fine for five glyphs and is not a route to an
      alphabet.
- [ ] Persist global settings with `shared_preferences`. Nothing persists yet.
- [ ] Dock: the right-hand readout shows live speed while the cell bar shows the
      manual target, so they disagree while the simulation runs. Fine for a
      developer tool, wrong for shipping.

---

## How to verify on a device

`flutter test` covers the model and the texture packing only. The shader needs
a real GPU; the simulator runs Impeller and is adequate for correctness, though
`CLAUDE.md` requires a physical device in sunlight for anything thermal.

    xcrun simctl list devices available | grep Booted
    xcrun simctl terminate <UDID> com.example.anode
    flutter run -d <UDID> --debug
    xcrun simctl io <UDID> screenshot out.png

Terminate the app explicitly before relaunching. Killing `flutter run` leaves
the app running on the simulator, so a screenshot taken afterwards can show the
previous build — this produced one wrong conclusion already.

Screenshots are captured in the device's native orientation, so a landscape
app appears rotated 90° in the file.
