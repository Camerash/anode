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
| 4 | Editor and optical authoring | Done — developer, optical, Prism, and mechanical refinements complete |
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
- [x] Runtime controls were initially docked in contain-fit dead space. Stage 4
      later removed the active-dashboard config dock; `SET` now opens Settings
      and debug controls live in a separate workbench.

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
- [x] Anchor-plus-offset positioning initially proved placement. Schema 5 later
      removed anchors and spans in favour of required absolute centre and size.
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

`positionRange` is 16 and `sizeScale` is 32. These are encoding ranges, not
tuned values, and they carry headroom deliberately: the main module's size is
now the authored frame extent, and a landscape primary contained into a narrow
tall window derives an envelope 8.32 units tall at 320×1024 — which the previous
`sizeScale` of 8 clamped silently. `rgbaFloat32` resolves roughly 6e-8 inside
[0, 1], so even at these ranges a decoded value is good to about 2e-6 design
units, or 6e-4 px at the halo test's 300 px per unit.

The main module is identified by an explicit packed flag in `texel 8.b`, not by
comparing its size against the frame. Its size now *equals* the frame extent, so
a geometric test would also fire for an authored sub-module a user happened to
size to the whole frame — silently making its grain global and its filaments use
the tube reference.

Layout, mirrored between `component_data.dart` and `vfd.frag`:

    texel 0:        type, cx, cy
    texel 1:        w, h, paramA
    texel 2:        paramB, component variant code, Prism lit
    texel 3:        component phosphor RGB
    texel 4:        emission, bloom, phosphor texture
    texel 5:        grid, unlit phosphor, decay
    texel 6:        module centre x/y, module width
    texel 7:        module height, glass grain, filament strength
    texel 8:        Prism pressed, filament variant code, main-module flag
    texel 9:        Prism bevel, face opacity, inactive luminosity
    texels 10..21:  digit segment payload, or 24 Prism glyph indices

`paramA` is digit count, cell count, or lit unit index depending on type.
For Prism rows it carries rendered glyph count. `paramB` is the bar's fill
fraction. The segment buffer keeps a stride of eight — seven segments plus a
spare for a future decimal point. Prism rows reuse those same RGB slots; texture
dimensions and the sixteen-component limit do not change.

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
| 16, 17 | `uFrame` — authored frame extent in design units |
| 18 | `uCount` |
| 19, 20 | `uDataSize` |

Sampler 0 is `uData`, sampler 1 is `uPrismGlyphs`.

`VfdPainter.paint` asserts that `setFloat(21, …)` throws. If it ever succeeds,
`vfd.frag` declares a uniform nothing writes — which renders plausibly and
wrongly rather than erroring, exactly like the three texture traps above.

---

## Stage 4 — editor and optical authoring — DONE

Built BEFORE the shipped presets are authored, as a forcing function on the
data model. Commit `4d511ed` is the reviewed developer-tool boundary. The
optical-authoring extension completed before Stage 5 or shipped preset
authoring.

- [x] Editor route with a visible authored-frame canvas. Every authored frame
      holds its fixed aspect and contain-fits.
- [x] Add, remove, reorder components from the `ComponentTypes` registry.
- [x] Drag to reposition; writes `Placement.offset` for the displayed
      orientation ONLY.
- [x] Resize handles writing `Placement.size` (width and height independent).
- [x] Params rendered generically from `ParamSpec`. A param needing a bespoke
      control is a finding about the model, not a reason to special-case it.
- [x] Viewport switcher previews both orientations on one device. A missing
      alternate contains the primary layout read-only; explicit creation bakes
      that appearance before editing.
- [x] Clone a template into a named dashboard through explicit confirmation.
- [x] **Deliverable: a written list of everything the model could not express.**
      That list is the actual output of this stage.

Already-known gaps to fold into that list:

- No per-orientation param overrides. Only placement varies per orientation, so
  3 digits in landscape and 2 in portrait needs two components with two ids.
- Z-order is implicit list order (deliberate, see Stage 2).

Also outstanding from the navigation decision, which needs the model and so
could not be built in Stage 1:

- [x] Library route with `Templates` / `Designs` / `Settings`. Template cards
      activate or clone; user-design cards activate, clone, or explicitly edit.

### Stage 4 implementation

- Live shared-render editor canvas with non-painting component and module
  selection/drag/resize overlays; no per-component raster surfaces.
- `Design` read interface lets presets and dashboards activate without silently
  converting presets into dashboards.
- `FrameSpec` stores one fixed reference aspect for each explicitly authored
  layout. Primary identity is explicit; a missing opposite-orientation layout
  falls back wholesale to the primary.
- Templates stay immutable. Clone confirms and optionally names a dashboard,
  activates it, then opens its editor. Edit never clones implicitly.
- Dashboards, active selection, and global settings persist through
  `shared_preferences`; editor drag writes are debounced.
- Prism controls cover editor chrome, Library actions, and device feedback
  settings. Runtime debug controls live only in a debug workbench.

### Stage 4 data-model findings

1. **Frame behavior was missing — resolved.** Every design has one primary
   fixed frame and may have one explicit opposite-orientation alternate.
   Missing alternates contain the primary unchanged; no content rotation or
   implicit reflow occurs.
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
   now resolve dashboard -> module -> component. Schema 5 rejects old
   dashboards; no unreleased migration remains.
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
13. **Arbitrary shader Prism legends — resolved.** One app-wide Barlow SDF
    atlas and glyph indices packed into existing component payload slots now
    render labels in the shared pass. The 24-glyph ASCII visual fallback does
    not truncate or rewrite persisted source labels.

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
- [x] Fidelity refinement against physical automotive switch reference:
      integrated static socket, near-square smoked cap, thin asymmetric
      chamfer, hard neutral glints, dark inactive face, and cap-only travel.
- [x] Remove status lamp and cyan face fill. Active state backlights the
      dashboard-coloured legend with only a faint internal diffuser wash;
      selection/focus uses external locator ticks.
- [x] Add explicit one-/two-/three-unit Flutter spans and bundled Barlow
      Condensed Medium Italic switch legends. Reduced motion keeps immediate
      state feedback without spatial animation.
- [x] Add checked-in deterministic Barlow SDF atlas. Shader Prism rows reuse
      digit payload slots for up to 24 glyph indices; unsupported text degrades
      visually while full model data survives.
- [x] Keep `PrismStyle` JSON compatible while bounding and relabelling its four
      controls as cap depth, smoke density, inactive legend, and active
      backlight.

#### Editor and runtime interaction

- [x] Replace box-only preview with one live shared VFD render plus non-painting
      selection, drag, and resize overlays. Keep
      `CustomPainter(repaint: controller)`.
- [x] No selection: `DESIGN EFFECTS`. Selected component:
      `<COMPONENT> · LOCAL EFFECTS`. Panel styling always follows dashboard;
      canvas resolves all module/component overrides live.
- [x] Non-scrolling effect-button grid. Tile tap selects detail only. Detail
      supplies physical description, explicit power, segmented strength,
      precise number, and minus/plus steppers. The lever follow-up below
      superseded power/bar/steppers while preserving every effect.
- [x] Per-effect `INHERIT` / `OVERRIDE`. Inherited values remain visible but
      read-only; enabling override seeds current effective value; disabling it
      removes local value.
- [x] Immutable templates never expose live effect controls. `CLONE` confirms
      before creating a mutable dashboard; changing effects never silently
      forks.
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
- [x] Expand Prism device guard for atlas legend output, localized light, dark
      face, fixed socket, moving cap, and opaque filament-wire occlusion.
- [x] End extension in its own reviewed commit. Stop before Stage 5.

#### Mechanical UI refinement — DONE

- [x] Replace `MaterialApp` and visible Material chrome with `WidgetsApp`,
      zero-duration routes, Prism switch banks, recessed `EditableText`, and
      persistent VFD annunciators.
- [x] Reject user-content `Scrollable`, `ListView`, and `PageView` use through
      an architecture test. Native text caret/selection scrolling remains
      exempt.
- [x] Add reusable `MechanicalDrawer`, `MechanicalFlipTray`,
      `MechanicalPager`, `PrismSelectorBank`, `VfdEditableField`, and
      `VfdAnnunciator`.
- [x] Replace free/inertial overflow with integer pages, a draggable detented
      rail, 60ms carriage snap, Prism previous/next controls, adjustable
      semantics, and one feedback event per detent.
- [x] Effect caps first became label-only with a top-hinged detail fascia.
      The lever follow-up below superseded this with icon-only overview keys
      and an active-only detail surface.
- [x] Add non-persisted `EffectSpec.controlLabel`; persisted effect ids and
      values remain unchanged. Unknown ids remain retained and visible.
- [x] Rebuild editor around a 48px rail and manually latched push service bay.
      It initially keyed the edge to preview orientation; the follow-up below
      correctly keys it to route window shape. Selection never opens it.
      Opening reduces preview bounds and re-contain-fits without mutating
      authored geometry.
- [x] Page rack slots; move reorder, visibility, and removal to explicit
      selected-item controls. Generic param, variant, module, action, and
      placement controls use shared mechanical primitives. Schema 5 later
      removed anchor controls.
- [x] Add three-decimal X/Y/W/H readouts and 0.005-unit placement/size nudges.
- [x] Correct edge resize: one delta, half-delta centre correction, opposite
      edge invariant, minimum `0.03` correction after clamp, no frame clamp.
- [x] Strengthen frame authoring chrome with matte outside region,
      dashboard-coloured double boundary, corner registration marks, and exact
      orientation/aspect readout.
- [x] Rebuild Library and Settings as hard-cut Prism surfaces with detented
      design paging and fixed device-feedback controls.
- [x] Add responsive checks at 320×568, 393×852, 874×402, tablet, and desktop;
      add mechanical surface goldens for editor closed/open, effect fascia
      closed/open, pager, Library, and Settings.

Mechanical refinement model findings:

1. **No new persisted-model gap was found.** Paging, drawer state, selected
   editor section, fascia state, compact labels, and mechanical motion are
   presentation state and correctly remain outside dashboard JSON.
2. **Existing unresolved gaps remain unchanged:** per-orientation params and
   optics, declarative interactive action state, and renderer coverage for
   outside temperature, battery, and altitude.
3. **Z-order remains implicit list order and is still sufficient.** Explicit
   `UP`/`DOWN` controls proved reorder needs no separate layer field.
4. **Phosphor is intentionally a synthetic optical channel in presentation.**
   It selects a colour while effect channels select calibrated scalar physics;
   forcing both into one persisted scalar schema would weaken the model.

#### Stage 4 viewport, cloning, and recovery follow-up — DONE

- [x] Fixed aspect is universal. Runtime and editor contain-fit authored frames;
      no viewport resize mutates persisted layout data.
- [x] Replace orientation lock/support flags with explicit primary-layout
      identity plus an optional authored alternate. Landscape is the default
      primary. Editor initially previews current window orientation.
- [x] When no matching alternate exists, contain the primary unchanged. Never
      rotate content or synthesize a cross-orientation reflow.
- [x] Add explicit alternate creation/reset. Creation uses current window aspect
      and bakes the contained primary appearance before independent editing.
      Fallback previews remain read-only. *(Superseded by the frame-extent
      follow-up below: creation now derives a device-safe-rect envelope at the
      current fit scale and copies placements verbatim.)*
- [x] Independent fixed/span placement axes were added, then removed by the
      schema-5 centre/size simplification below.
- [x] Preserve unknown component types during import/round-trip.
- [x] Render and hit-test component overlays beyond frame bounds; dim only the
      portion outside the authored boundary. Add `BRING IN` recovery.
- [x] Separate canvas `EDIT` and `NAV` modes. Nav owns 1×–4× pan/zoom; `FIT`
      restores edit mode and identity without writing placement. *(Superseded by
      the frame-extent follow-up below: modes removed in favour of one
      hit-tested gesture.)*
- [x] Fix first resize interaction by snapshotting resolved size, placement,
      frame aspect, and scale at gesture start.
- [x] Push service bay from bottom in portrait and right in landscape, using the
      same panel contents in both orientations.
- [x] Split Library into immutable Templates and mutable Designs. Clone prompts
      for optional name; template Edit no longer auto-forks.
- [x] Remove active-dashboard configuration dock. `SET` opens app Settings;
      RUN/manual speed/unit survive only in debug workbench.
- [x] Collapse closed effect/Prism detail fascia to zero height and keep selected
      paged channel visible after bank capacity changes.

Follow-up model findings:

1. **Cross-orientation policy — resolved.** Primary plus optional alternate
   replaces mixed orientation-lock/adaptive semantics. `FrameSpec` entries are
   explicit authored layouts, and `primaryOrientation` survives export/import.
2. **Responsive frame behavior — deliberately deferred.** Fixed physical faces
   are the only current frame mode. Resizable windows use contain fit. A future
   same-orientation responsive instrument must justify adaptive authoring with a
   concrete contract before the mode returns.
3. **Alternate initialization — resolved, then superseded.** Placements were
   baked from primary contain geometry. The frame-extent follow-up below
   replaced the rescale with a verbatim copy into a larger envelope; schema 5
   then removed span axes entirely.
4. **Axis span data — resolved by removal.** Fixed authored frames and absolute
   centre/size made the extra alignment contract unnecessary.
5. **Cross-version import loss — resolved.** Unknown component instances now
   survive serialization. They remain unavailable to render until a matching
   type implementation exists.
6. **Per-orientation params and optics remain unresolved.** Placement and frame
   behavior vary per orientation; component params, variant, and sparse optical
   overrides do not.

Mechanical refinement verification:

- `flutter analyze`: clean.
- `flutter test`: 113 passing, including primary fallback, alternate
  bake/reset, capability resolution, responsive editor, and updated goldens.
- Existing Prism golden remains unchanged except shared VFD typography now uses
  the bundled Barlow face.
- `integration_test/halo_compounding_test.dart`: four tests passing on iPhone
  17 Pro simulator, iOS 26.3, Impeller. Original seam/halo assertion remains
  unchanged.
- Fresh debug launch verified the `WidgetsApp` hard-cut shell on device after
  explicit termination. Native portrait and landscape screenshots were
  inspected. Portrait now shows the unchanged horizontal 2.6:1 primary centred
  by contain fit; landscape retains the authored face. The latter keeps the
  documented 90-degree screenshot rotation.

Extension verification:

- `flutter analyze`: clean.
- `flutter test`: 80 passing, including deterministic Prism state golden.
- `integration_test/halo_compounding_test.dart`: four tests passing on iPhone
  17 Pro simulator, iOS 26.3, Impeller — original seam guard, mixed-colour halo
  compounding, dashboard/module/component inheritance, and physical Prism
  body/light/press/legend/filament occlusion.
- The integration harness forces its documented 780×300 render target with an
  `OverflowBox`; simulator portrait constraints can no longer silently
  invalidate its 300 px/design-unit measurement.
- Fresh debug launch inspected after explicit terminate; shared render remains
  intact and the app was terminated cleanly afterward.

#### Stage 4 frame-extent and editor-interaction follow-up — DONE

Creating a portrait alternate from a landscape primary blew every optical effect
up about 4.6×. Nothing stretched — `fitScale` is and was isotropic. The defect
was that one design unit meant "the height of the frame", so a `FrameSpec`
carrying only an aspect silently set the physical scale of the tube.
`bakeContainedPlacement` shrank geometry to compensate, which preserved the
digits and left every design-unit optical constant — halo lobes, mesh pitch,
edge softness, filament diameter, coating grain, tilt shift — magnified on
screen. It was never only a bake bug: any design authored at an aspect far from
2.6 had wrong optics.

- [x] `FrameSpec` stores `width` and `height` in design units;
      `referenceAspect` survives as a derived getter. A design unit is now
      frame-independent. `FrameSpec.aspect(a)` keeps one-unit-tall frames
      expressible, and JSON writes the extent plus the derived aspect so an
      older build degrades rather than falling back to a default.
- [x] `Anchor.pointIn`, `Placement.resolve` and `resolveSizeIn` temporarily took
      a frame `Size`. Schema 5 later removed all three with anchors/spans.
- [x] `viewportFrameExtent` derives an alternate's envelope from the device safe
      rect at the current fit scale, swapping axes when the target orientation
      disagrees with the device. Both `CREATE` and the read-only preview call
      it, so zero-jump is structural rather than test-enforced.
- [x] Alternate creation copies geometry verbatim. Schema 5 made this literal:
      placements contain only absolute centre and size.
- [x] `uAspect` → `vec2 uFrame`, renumbered in place; flat float indices 17–19
      shifted to 18–20. `VfdPainter.paint` asserts a write past the end throws.
- [x] Main module identified by a packed flag in `texel 8.b`, and filament Y
      spacing references a new `MAIN_TUBE_HEIGHT` constant for it. Without that
      the fix would have reintroduced its own 5.6× defect one layer down, since
      the main module's size is now the frame extent rather than a hardcoded
      one unit. `filamentHalfWidth` divides by `uFrame.x` — a substitution, not
      a removal; the divisor is only constant for the main module.
- [x] `positionRange` 4 → 16 and `sizeScale` 8 → 32, since an envelope derived
      from a narrow tall window exceeds the old range.
- [x] Unauthored-orientation preview draws the device envelope with the
      inherited layout contained and scrimmed inside it, labelled
      `INHERITED · READ ONLY`. The scrim is painted into the existing matte
      painter, not an `Opacity` layer over the shared render pass.
- [x] `EDIT`/`NAV` modes and the nested `InteractiveViewer` deleted. One root
      `Listener` resolves each gesture at pointer-down against screen-space
      rects. Selection chrome and handles lifted into screen space, so a handle
      is a constant 44px at any zoom and straddles the border it resizes.
- [x] Full-screen editor mode as a state flag; canvas controls moved
      bottom-right so they no longer collide with the bottom-left bay latch;
      portrait/landscape drawer branches folded into one `_WorkspaceLayout`
      with both sets of numbers unchanged.

Frame-extent model findings:

1. **Optical scale was coupled to frame shape — resolved.** A frame carries an
   extent; a design unit is frame-independent. Alternates are created by growing
   the envelope, not by shrinking the contents.
2. **Filament span is frame-derived — unresolved.** `0.62 * moduleSize.x /
   uFrame.x` makes a sub-module's wire span a fraction of the frame rather than
   a property of the tube. Physically wrong, but the constant is
   photograph-tuned and folding the frame width into it would produce a rounded
   derivative of a tuned value. The fix is an authored module property.
3. **Span-axis bake ambiguity — resolved by schema 5 removal.** No persisted
   placement now changes meaning when its frame envelope grows.
4. **`VfdAnnunciator` is still unwired.** It was considered for the read-only
   badge and rejected: it demands acknowledgement, which a passive state must
   not. The mandate for fork/route feedback remains unmet.
5. **No new persisted-model gap.** Camera transform, full-screen state, and
   selection remain presentation state and stay out of dashboard JSON.

Frame-extent verification:

- `flutter analyze`: clean.
- `flutter test`: 130 passing. New: zero-jump across five device sizes,
  optical-scale invariance across devices and both primary orientations,
  `FrameSpec` extent round-trip, the main-module flag, the raised encoder
  ranges, the vertical-span clamp against a tall frame, and a gesture matrix
  covering tap-to-select, drag-on-unselected-pans, substrate pan, `FIT`,
  two-pointer promotion freezing placement, handle constancy at 4× zoom, and
  full-screen parity.
- Two editor goldens regenerated for the moved canvas controls. Every other
  golden — effects, pager, Library, Settings, Prism — unchanged, which is the
  check that nothing leaked.
- `integration_test/halo_compounding_test.dart`: four tests passing on iPhone
  17 Pro simulator, iOS 26.3, Impeller. It derives pixel positions from
  `designUnitPx = 300` and asserts brightness at them, so it is itself the
  landscape parity check — a scale change could not pass it.
- `integration_test/frame_extent_optics_test.dart`: new. Renders one component
  through a landscape primary and through a portrait alternate baked from it,
  both at 300 px per design unit, and compares the luminance profile across a
  lit edge. Max divergence under 12/255, and the halo shoulder width — a pure
  design-unit quantity, so its width in pixels *is* the optical scale — matches
  within 3 px. Guarded against passing vacuously on a bake that silently did
  nothing.
- Screenshot diffing the cluster route before and after is **not** a usable
  parity check: the simulated speed source animates, so two launches show
  different digits and different bar fill. The halo suite is the parity check.

#### Stage 4 centre-placement and automotive-lever follow-up — DONE

- [x] Break placement storage to schema 5: required absolute `center` and
      `size`, persisted as `x`, `y`, `w`, `h`. Remove `Anchor`, `AxisSpan`,
      frame resolution, anchor-relative transforms, and span-specific editor
      controls. Dashboard/active-design preferences use v2 keys; old dashboard
      schemas are rejected without migration.
- [x] Alternate creation copies component and module placements verbatim into
      the expanded frame extent.
- [x] Add editor-wide session-only `SNAP` beside `FIT`: active by default,
      `0.005` design-unit delta quantization relative to pointer-down geometry,
      continuous when dark, and no mutation on toggle.
- [x] Make move/resize pure transforms shared by components and modules.
      Snapped resize quantizes the applied delta, keeps the opposite edge fixed,
      and clamps to `0.03` after quantization. Selection border and renderer
      consume the same committed placement.
- [x] Replace paged anchor/axis placement controls with one PLACE surface:
      exact X/Y, 3×3 D-pad, containing `BRING IN`, and W/H
      minus/readout/plus. Direct controls always step `0.005`, independent of
      SNAP.
- [x] Choose service-bay edge from the route window, not preview orientation:
      bottom for `height > width`, right otherwise. Opening still pushes and
      re-contains the canvas.
- [x] Add `MechanicalLever`: fixed recessed HVAC faceplate, narrow slot,
      smoked/chrome Prism thumb, 44px thumb hit region, thumb-only direct drag,
      initially hundredth quantization, exact VFD readout, adjustable semantics,
      keyboard arrows, pointer wheel, hard stops, and detent-gated feedback.
      The service-hatch follow-up below supersedes hundredths with true physical
      stops.
- [x] Replace effect power/strength bars/steppers with 21-mark `0.00–2.00`
      levers. Zero derives OFF; `resumeStrength` remains persisted. Inherited
      local values remain visible and disabled. Replace Prism-style bars with
      11-mark levers and tuned double marks.
- [x] Add non-persisted effect pictogram metadata and hand-authored line icons.
      Overview caps are icon-only with text semantics. Active detail hard-cuts
      away every other key and the pager. Unknown stored effects use `?`, open
      disabled detail, and survive round-trip. The service-hatch follow-up below
      removes this overview entirely and retains pictograms as secondary marks.
- [x] Add goldens for lever states, effect overview/detail, Prism lever detail,
      right-side PLACE, and bottom service bay. Existing Library, Settings,
      pager, editor, and Prism baselines remain covered.

Model findings:

1. **Anchor/span placement complexity — resolved by removal.** Fixed authored
   extents plus contain-fit need no alignment relation. Absolute centre/size is
   sufficient for runtime, alternate copy, renderer packing, and editor chrome.
2. **Snapping is presentation behavior, not model state.** SNAP, service
   channel, hatch face, current lever drag, and drawer edge/state remain outside
   dashboard JSON.
3. **No effect was removed.** Active-only disclosure and pictograms reduce
   control density without weakening the optical model or adding bespoke
   persisted controls.
4. **Z-order remains implicit list order and still needs no separate field.**
5. **Existing unresolved gaps remain:** per-orientation params/optics,
   declarative interactive action state, authored filament span, unwired
   annunciator feedback, and renderer coverage for outside temperature,
   battery, and altitude.

Verification:

- `flutter analyze`: clean.
- `flutter test`: 134 passing, including schema rejection,
  snapped/continuous transform invariants,
  SNAP no-mutation, one-page PLACE, BRING IN, shape-driven drawer edge,
  lever input/accessibility, icon-only effects, inheritance, unknown effects,
  and responsive overflow.
- `integration_test/halo_compounding_test.dart`: four tests passing on iPhone
  17 Pro simulator, iOS 26.3, Impeller. Original seam/halo assertions remain
  unchanged.
- `integration_test/frame_extent_optics_test.dart`: passing on the same
  simulator and renderer.
- Fresh debug launch followed an explicit terminate attempt. Portrait and
  landscape native-orientation screenshots show contain-fit without overflow;
  the landscape file retains the simulator's expected 90-degree capture
  rotation. Simulator input automation was unavailable, so snapped versus
  continuous drag feel remains verified by deterministic widget transforms,
  not claimed as a hands-on device check.
- No shader source or tuned constant changed in this follow-up.

#### Stage 4 optical service-hatch follow-up — DONE

- [x] Rename the editor section `OPTICS` to `LOOK`.
- [x] Replace the paged icon overview with a normal fascia exposing only the
      current phosphor colour and a `TUNE` latch.
- [x] Add a labelled phosphor hard-cut: three dashboard colours, plus
      `USE DESIGN` for local scopes.
- [x] Add a fixed-footprint top-hinged service hatch. Opening it replaces
      the fascia without changing service-bay or canvas dimensions.
- [x] Show one labelled effect at a time with previous/next hard stops, index,
      description, secondary pictogram, exact value, local inheritance, and
      the existing lever. Preserve unknown stored effects as disabled channels.
- [x] Make every lever mark a real detent. Optical values step by `0.10` across
      21 marks; Prism values use 11 explicit detents with the tuned reference
      inserted exactly when it is not uniform. Thumb position, stored value,
      semantics, keyboard/wheel input, illuminated mark, and feedback must
      agree.
- [x] Update headless interaction tests, responsive coverage, service-hatch
      goldens, and both Impeller guards. Commit as one Stage 4 follow-up and
      stop before Stage 5.

Verification:

- `flutter analyze`: clean.
- `flutter test`: 138 passing. Coverage includes true detent drag,
  semantics/keyboard/wheel parity, non-uniform tuned-reference insertion,
  fixed hatch footprint, reduced motion, fascia/phosphor/service flows,
  hard stops, remembered service index, local inheritance, unknown effects,
  and a 280×150 minimum local side-bay face without overflow.
- `integration_test/halo_compounding_test.dart`: four tests passing on iPhone
  17 Pro simulator, iOS 26.3, Impeller. Original seam/halo assertions remain
  unchanged.
- `integration_test/frame_extent_optics_test.dart`: passing on the same
  simulator and renderer.
- Fresh debug launch followed an explicit terminate attempt. Portrait and
  landscape runtime screenshots rendered cleanly; landscape capture retains
  the simulator's expected 90-degree native orientation. Service faces were
  visually checked through regenerated goldens. Direct device manipulation was
  unavailable, so lever feel is covered deterministically rather than claimed
  as a hands-on check.
- No persisted schema, shader source, tuned constant, or shipped preset changed.

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
- [ ] Extend SDF rendering to irregular VFD anode glyphs and icons. Stage 4 now
      ships a Barlow atlas for Prism switch legends; `KM/H` and `MPH` remain
      hand-stroked, and warning icons/14-segment alphabets need a distinct
      authored atlas contract.
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
