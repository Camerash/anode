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
| 4 | Editor and optical authoring | Done — `4d511ed`; optical extension complete |
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
    texel 2:        paramB, component variant code, Prism lit
    texel 3:        component phosphor RGB
    texel 4:        emission, bloom, phosphor texture
    texel 5:        grid, unlit phosphor, decay
    texel 6:        module centre x/y, module width
    texel 7:        module height, glass grain, filament strength
    texel 8:        Prism pressed, filament variant code, spare
    texel 9:        Prism bevel, face opacity, inactive luminosity
    texel 10 + 3k:  digit k segments 0..2
    texel 11 + 3k:  digit k segments 3..5
    texel 12 + 3k:  digit k segment 6, spare, spare

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

## Stage 4 — editor and optical authoring — DONE

Built BEFORE the shipped presets are authored, as a forcing function on the
data model. Commit `4d511ed` is the reviewed developer-tool boundary. The
optical-authoring extension completed before Stage 5 or shipped preset
authoring.

- [x] Editor route with an aspect-locked canvas. The canvas holds the target
      orientation's aspect regardless of the window and scales to fit, with a
      visible frame boundary — the one place a visible edge is correct.
- [x] Add, remove, reorder components from the `ComponentTypes` registry.
- [x] Drag to reposition; writes `Placement.offset` for the displayed
      orientation ONLY.
- [x] Resize handles writing `Placement.size` (width and height independent).
- [x] Params rendered generically from `ParamSpec`. A param needing a bespoke
      control is a finding about the model, not a reason to special-case it.
- [x] Orientation switcher, so both authored layouts are editable on one device.
- [x] Fork a preset into a dashboard, visibly.
- [x] **Deliverable: a written list of everything the model could not express.**
      That list is the actual output of this stage.

Already-known gaps to fold into that list:

- No per-orientation param overrides. Only placement varies per orientation, so
  3 digits in landscape and 2 in portrait needs two components with two ids.
- Z-order is implicit list order (deliberate, see Stage 2).

Also outstanding from the navigation decision, which needs the model and so
could not be built in Stage 1:

- [x] Library route reached from the dock, with `Designs` / `Settings` tabs.
      Card tap activates; a separate explicit Edit button opens the editor.
      The dock now exposes the route through a live `LIBRARY` control.

### Stage 4 implementation

- Live shared-render editor canvas with non-painting component and module
  selection/drag/resize overlays; no per-component raster surfaces.
- `Design` read interface lets presets and dashboards activate without silently
  converting presets into dashboards.
- `frameAspects` stores the authored aspect per orientation. Legacy payloads get
  tolerant development defaults.
- Presets stay immutable. Edit visibly creates a user-copy banner, activates the
  fork, and adds it to the dashboard list.
- Dashboards, active selection, and global settings persist through
  `shared_preferences`; editor drag writes are debounced.
- Prism controls cover editor chrome, runtime dock, Library actions, and device
  feedback settings. Generic form fields remain plain controls where appropriate
  for the developer inspector.

### Stage 4 data-model findings

1. **Frame aspect was missing — resolved.** The model could not tell the editor
   which aspect to lock to. It is now authored per orientation.
2. **Per-orientation params are missing — unresolved.** Three digits in
   landscape and two in portrait still requires two component ids with
   mutually exclusive placements.
3. **Explicit z-order remains absent — acceptable for current faces.** Reorder
   edits global list order. The editor needs no second layer field; selected
   editor chrome is lifted locally only to keep handles reachable.
4. **Generic param presentation metadata was incomplete — resolved.**
   `ParamSpec` now carries option labels, numeric step/precision, and unit
   suffix; variant-specific params use the same editor.
5. **Tube-level optical ownership was missing — resolved.** Lightweight
   `VfdModule`s own per-orientation regions, filament references, glass grain,
   and sparse optical overrides. `main` keeps the common case flat.
6. **Renderer coverage is narrower than the registry.** Outside temperature,
   battery, and altitude can be added, placed, resized, and configured in the
   editor, but the current shader skips them. Their data model is sufficient;
   their renderer implementations are outstanding.
7. **Optical scope was missing — resolved.** `OpticalProfile`,
   `EffectSetting`, generic `EffectSpec`, and sparse module/component overrides
   now resolve dashboard -> module -> component. Legacy booleans migrate on
   repository load.
8. **Component variants were missing — resolved.** Instances persist stable
   id/revision refs; legacy remains registered after new variants are added;
   unknown refs and params survive with visible fallback. No shipped variants
   were authored.
9. **Interactive actions were missing — resolved for tap actions.** Design
   components persist stable action ids and generic params. Non-painting runtime
   hit regions provide semantics and shader press state. Unsupported actions
   remain visible and stored.
10. **Per-orientation optics remain absent — unresolved.** Variant, params, and
    sparse optical overrides are component-wide. Different optics between
    orientations require separate component ids.
11. **Each component belongs to exactly one VFD module — deliberate.** This
    keeps grouping lightweight. Overlapping/shared physical envelopes would
    require another relation if a real design proves it necessary.
12. **Action state binding is missing — unresolved.** A Prism component has one
    tap action and static lamp/label params. It cannot yet bind light or legend
    to media state, or declare long-press/double-press/release actions.
13. **Arbitrary shader Prism legends await the SDF atlas.** Label data persists
    and Flutter Prism controls render labels, but instrument Prism bodies have
    no arbitrary glyph renderer yet. This is renderer coverage, not a model gap.

Verification at the boundary:

- `flutter analyze`: clean.
- `flutter test`: 53 passing.
- `integration_test/halo_compounding_test.dart`: passing on iPhone 17 Pro
  simulator, iOS 26.3, Impeller.
- Fresh debug launch inspected after explicit terminate; Stage 3 render remains
  intact. Screenshot is rotated in the captured file as documented.

### Stage 4 optical-authoring extension — DONE

This extension remained a forcing function on the model. No shipped preset or
handcrafted digit variant was authored during it.

#### Model and persistence

- [x] Replace app-wide authored `VfdLayers` with dashboard
      `OpticalProfile` values driven by generic `EffectSpec` metadata.
- [x] Calibrated effect strength: `0.00` off, `1.00` tuned ideal, `2.00`
      overdrive ceiling unless an effect declares a lower safe maximum. Preserve
      `strength` plus `resumeStrength`; derive power from `strength > 0` rather
      than persisting a duplicate enabled boolean.
- [x] Add sparse inheritance:
      dashboard baseline -> VFD module -> component. Missing means inherit;
      explicit zero means locally off.
- [x] Add component-overridable phosphor colour, emission, bloom, phosphor
      texture, grid strength, unlit-phosphor strength, and decay.
- [x] Keep tilt/parallax dashboard-scoped. Keep glass grain and filament
      geometry module-scoped.
- [x] Add lightweight `VfdModule`: implicit `main`, flat component list,
      component `moduleId`, per-orientation module region, filament variant,
      glass grain, and sparse optical overrides. Hide module management until a
      second module exists.
- [x] Add revisioned `ComponentVariantSpec` and persisted variant reference.
      New variants register new refs; deprecated variants remain renderable;
      unknown refs and params survive round-trip with visible fallback.
- [x] Variant switching preserves `Placement.size`; explicit
      `RESET TO VARIANT SIZE` applies recommended dimensions.
- [x] Add extensible `ActionRegistry` and persisted action bindings. App and
      platform register prebuilt actions; unsupported bindings remain stored and
      visibly unavailable.
- [x] Move app Settings to user/device preferences only: sound, haptics,
      accessibility, demo mode, and future renderer quality. Remove duplicate
      authored effect controls.
- [x] Extend tolerant serialization tests for legacy layer payloads, unknown
      modules, variants/revisions, effect ids, overrides, and action ids.

#### Prism control system

- [x] Reusable Flutter `PrismButton`: smoked acrylic trapezoidal bevel,
      independent active/pressed states, dashboard-coloured light, focus and
      semantics, depth transform, click sound, and haptic actuation.
- [x] Separate shader-rendered prism design component using shared semantics and
      the existing single pass. Never render instrument buttons as individual
      Flutter visual surfaces.
- [x] Add Prism roles for hierarchy through size, bezel depth, grouping, label
      scale, and controlled luminous intensity. Dense period-correct button
      banks are intentional; do not simplify them into sparse modern cards.
- [x] Migrate editor-wide visible controls to the Prism/retro system. Keep
      conventional interaction semantics and accessibility under the custom
      surface.
- [x] Sound and haptics are simple app-wide preferences initially; no
      per-design sound packs.

#### Editor and runtime interaction

- [x] Replace box-only preview with one live shared VFD render plus non-painting
      selection, drag, and resize overlays. Keep
      `CustomPainter(repaint: controller)`.
- [x] No selection: `DESIGN EFFECTS`. Selected component:
      `<COMPONENT> · LOCAL EFFECTS`. Panel styling always follows dashboard;
      canvas resolves all module/component overrides live.
- [x] Non-scrolling effect-button grid. Tile tap selects detail only. Detail
      supplies physical description, explicit power, segmented strength,
      precise number, and minus/plus steppers.
- [x] Per-effect `INHERIT` / `OVERRIDE`. Inherited values remain visible but
      read-only; enabling override seeds current effective value; disabling it
      removes local value.
- [x] Immutable presets show read-only effect controls plus explicit
      `CUSTOMIZE`; changing effects never silently forks.
- [x] Dashboard background remains inert. Explicit interactive design
      components get authored hit regions and accessibility semantics without
      painted Flutter surfaces. Press state flows through the render controller.
- [x] First registry actions may include `media.playPause`, `media.previous`,
      and `media.next`; registry architecture must remain open to later app-built
      actions and platform differences.

#### Renderer verification

- [x] Resolve module ids on CPU and pack module geometry, variant runtime codes,
      optical values, component phosphor colour,
      and prism press/light state without exceeding the sampled-data contract.
- [x] Accumulate component-coloured emission and local bloom/grid effects in the
      same pass; no per-component raster surface.
- [x] Render module filament geometry after emission and module glass grain in
      its physical composite layer.
- [x] Re-run `flutter analyze`, all headless tests, and
      `integration_test/halo_compounding_test.dart`.
- [x] Add device tests for mixed-colour halo compounding, component inheritance,
      and shader-rendered Prism press/light state.
- [x] End extension in its own reviewed commit. Stop before Stage 5.

Extension verification:

- `flutter analyze`: clean.
- `flutter test`: 71 passing.
- `integration_test/halo_compounding_test.dart`: four tests passing on iPhone
  17 Pro simulator, iOS 26.3, Impeller — original seam guard, mixed-colour halo
  compounding, dashboard/module/component inheritance, and Prism light/press.
- The integration harness forces its documented 780×300 render target with an
  `OverflowBox`; simulator portrait constraints can no longer silently
  invalidate its 300 px/design-unit measurement.
- Fresh debug launch inspected after explicit terminate; shared render remains
  intact and the app was terminated cleanly afterward.

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
- [x] **Filament wire ownership moved to VFD modules.** Stage 4 originally
      confirmed the old global wires were positioned around where the digits
      used to be hardcoded (`0.11 ± 0.215`, gated to `|q.x| < 0.62`). They moved
      to module-authored regions and stable filament references; implicit `main`
      preserves the full-frame case.
- [ ] **Tilt on device should come from the gravity vector**, not the pointer.
      The full-screen `Listener` is a desktop and development affordance and
      must not survive onto the instrument. Explicit interactive component hit
      regions are allowed; root gestures are not.
- [ ] Baked SDF atlas for irregular glyphs. The `KM/H` and `MPH` legends are
      hand-stroked, which is fine for five glyphs and is not a route to an
      alphabet. Arbitrary instrument Prism labels now depend on this too.
- [ ] Declarative action-state binding for interactive components: media/trip
      state -> Prism lamp/legend, plus any proven need for long press or release
      actions. Do not persist callbacks.
- [x] Persist dashboards, active design, and global settings with
      `shared_preferences`.
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
