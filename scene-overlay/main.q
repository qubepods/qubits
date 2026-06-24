//! cube — a turning 3D cube with a QView form floating over it.
//!
//! This is the demo for QView's `scene` viewport (kind 21, protocol 1.11): a
//! content-agnostic 3D viewport the HOST renders. `scene_id` 0 is the host's
//! turning cube, drawn by the **quine** game engine on a canvas BEHIND the QView
//! surface; the frosted card below composites ON TOP — that layering is the
//! overlay. Tapping the button bumps a live count (surgical set_attr).
//!
//! It also LINKS a second qube: `test.color` (../color), a library whose
//! `random_color(seed)` returns a packed `0xAARRGGBB`. The tap handler calls it
//! and paints the colour swatch — a real cross-qube call: scalar in, scalar out.
//! Building this app links the library in (`qube build` resolves the manifest
//! `dependencies` → `q64 emit --module test.color=color/src`).
//!
//! The reusable composite this lowers to is the `scene_overlay` registry block
//! (see src/ui/scene_overlay.q + the q64 spec/qview-ui-registry.md). main.q is the
//! self-contained single-file form so it compiles on the on-device q64 compiler
//! today (multi-file `use` of vendored components is not wired on-device yet).
//!
//! kinds:  box=0  column=2  label=4  button=6  scene=21
//! attrs:  y=1  w=2  h=3  radius=4  fill=6  text_id=9  surface=20  align=21  pad=22  gap=19  scene_id=29
//! event:  press=0     align: center=1     surface: material=2

import test.color.{random_color}

state taps = 0

fn main {
    // BACK layer — the 3D scene viewport. scene_id 0 = the host's turning cube.
    // The host renders it full-bleed behind the QView surface (engine canvas);
    // a native host would render the same id through its own 3D backend.
    qview.create(1, 21, 0)
    qview.set_attr(1, 29, 0)         // scene_id = 0 (turning cube)
    qview.set_attr(1, 6, random_color(0)) // fill = the cube's tint (host re-colours the 3D mesh)

    // FRONT layer — a frosted card (a centered column) floating over the 3D.
    qview.create(2, 2, 0)            // column
    qview.set_attr(2, 1, 432)        // y — lower third of the screen
    qview.set_attr(2, 20, 2)         // surface = material (frosted card)
    qview.set_attr(2, 4, 18)         // radius
    qview.set_attr(2, 21, 1)         // align: center
    qview.set_attr(2, 22, 20)        // pad
    qview.set_attr(2, 19, 14)        // gap between children

    // Title label.
    qview.create(3, 4, 2)
    qview.set_attr(3, 9, 1034)       // catalog "Turning cube"

    // The live count — a label whose text_id IS the number (text_id < 1000).
    qview.create(4, 4, 2)
    qview.set_attr(4, 9, taps)

    // Colour swatch — a plain box whose `fill` comes from the linked library.
    // The initial colour is `test.color.random_color(0)`; each tap repaints it.
    qview.create(6, 0, 2)            // box
    qview.set_attr(6, 2, 180)        // w
    qview.set_attr(6, 3, 28)         // h
    qview.set_attr(6, 4, 8)          // radius
    qview.set_attr(6, 6, random_color(0))   // fill = library colour for seed 0

    // "Tap +1" button (catalog id 11), wired to on_5.
    qview.create(5, 6, 2)
    qview.set_attr(5, 2, 220)        // w
    qview.set_attr(5, 3, 52)         // h
    qview.set_attr(5, 4, 12)         // radius
    qview.set_attr(5, 9, 1011)       // catalog "Tap +1"
    qview.on(5, 0, 5)                // press → on_5

    qview.present()
}

// Press handler: bump the count, ask the linked `test.color` qube for a fresh
// colour, and apply it to BOTH the 3D cube (the scene node's fill → the host
// re-colours the live mesh) and the UI swatch. Re-render the changed nodes.
pub fn on_5(node: i64, event: i64) {
    taps = taps + 1
    qview.set_attr(4, 9, taps)               // count label → new number
    qview.set_attr(1, 6, random_color(taps)) // scene fill → the 3D cube re-colours
    qview.set_attr(6, 6, random_color(taps)) // swatch fill → same library colour (deterministic)
    qview.present()
}
