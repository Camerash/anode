# Product

## Register

product

## Users

Drivers and retro-instrument enthusiasts use Anode as a glanceable GPS
speedometer and as a focused design tool for authoring VFD instrument faces.
Runtime use must remain safe in a windshield mount. Editing must support touch,
pointer, phones, tablets, and resizable iPad windows.

## Product Purpose

Anode turns live GPS speed into a physically credible 1980s vacuum fluorescent
instrument. Its editor lets users author fixed VFD faces without weakening the
optical model or changing their runtime geometry. Success means immediate,
glanceable driving information and precise, recoverable authoring.

## Brand Personality

Mechanical, photographic, uncompromising. Anode should feel like operating
1980s automotive switchgear and viewing a physical vacuum fluorescent module,
not a stock mobile UI wearing a retro theme. Familiar modern editing hierarchy
is welcome when it makes tools predictable; its physical expression remains
purpose-built.

## Anti-references

- Flat vector segments with generic Gaussian glow.
- Visible Material controls or decorative modern mobile chrome.
- Generic glassmorphism.
- Kinetic content scrolling or ornamental motion.
- Unlabelled navigation and state hidden behind discovery gestures.

## Design Principles

1. Preserve optical physics and the one-pass VFD renderer over conventional
   visual cleanliness.
2. Make state and navigation mechanical: explicit controls, hard stops,
   detents, and recoverable actions.
3. Keep runtime interaction deliberate and driver-safe; keep editing precise,
   accessible, and non-destructive.
4. Keep physical faces fixed and frame-independent. Contain unchanged authored
   geometry across viewports unless another screen layout is explicitly made.
5. Adapt editor chrome to physical window bounds without changing persisted
   design data or restricting authored content.

## Screen Layouts

A design has one or more named layouts. Each layout has an authored frame ratio
and independent placements. Layouts are not device models and are not limited
to portrait and landscape. DESIGN shows these layouts directly as a ratio grid.
Selecting a tile changes the editable canvas.

Layout tiles are passive frame specimens, not physical command buttons. Each
specimen shows its frame shape and ratio. Skin supplies its material and
selection treatment. Theme-specific buttons remain reserved for explicit
commands such as Add, Lock, Modify, and Remove.

With `LOCK` off, Anode selects the layout with the closest frame ratio to the
current viewport. If one layout exists, Anode contain-fits it on every screen.
With `LOCK` on, Anode fixes runtime to the selected layout and disables the
other layout tiles. On phones, it also requests the matching app orientation.
On large or resizable screens that do not accept orientation lock, Anode keeps
the selected layout while the system can rotate the window.

`ADD LAYOUT` copies the visible source layout into a new frame ratio. `MODIFY`
changes the selected frame ratio. Both actions use the Aspect Map. Component
size, position, and VFD optical scale stay unchanged. `REMOVE` is available for
non-base layouts only.

Future background bleed and hardware cutout artwork belong to a separate cover
layer. They must not change layout frames, component coordinates, or VFD optical
units.

## Interface Skins

Editor structure is stable across visual families: full-width document header,
movable command dock, contextual Console, safe-area behavior, semantics, and
accessibility do not change. A skin supplies materials, typography, colour,
motion, backgrounds, cutout treatment, control implementation, and interaction
feedback without owning editor layout or authored renderer geometry.

VFD is the first interface skin, not a permanent universal shell. Future
families include Outrun, Cyberpunk, and Vintage Orange. New skins must preserve
control location, meaning, hit targets, and interaction so changing appearance
never means relearning the editor.

Each family owns its button class and its press/release sound profile. VFD uses
Prism switchgear; Outrun, Cyberpunk, and Vintage Orange can use different
physical controls without adding theme modes to `PrismButton`. Sounds belong to
the interface skin, not a dashboard, optical profile, or saved design. Global
sound and haptic settings remain master switches.

## Accessibility & Inclusion

Preserve 44 px touch targets, keyboard activation, semantic labels, safe-area
protection for app chrome, and reduced-motion behavior. Runtime information must
remain glanceable and must not rely on motion or color alone to communicate
state.
