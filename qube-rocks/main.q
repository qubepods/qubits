//! qube-rocks — Asteroids-lite in the quine 3D engine, no backend.
//!
//! main.q is tiny on purpose: it creates ONE full-bleed `scene` viewport
//! (QView kind 21, scene_id 0) and presents it. Everything that makes it a
//! *game* lives in data the host feeds the engine, not here:
//!
//!   - scene.json            — the entities (cone ship, rock/bullet templates,
//!                             camera, light) + `fixedHz: 64` + `interpolate`.
//!   - qube-rocks.skill.js   — the game loop (onPreStep): steering via the
//!                             transform.rotation native, firing + rock-splitting
//!                             via world.spawn/despawn, reading the input axes.
//!   - overlay: controls.js  — the reusable on-screen controller (◄ ► ▲ ●),
//!                             hydrated over the canvas; it drives the input axes.
//!
//! The host renders the engine's 3D scene in the canvas and mounts the scene's
//! linked HTML overlay on top — same composition as the `scene-overlay` example,
//! here with a game controller instead of a QView card.
//!
//! kinds:  scene=21     attrs:  scene_id=29

fn main {
    qview.create(1, 21, 0)   // a content-agnostic 3D viewport
    qview.set_attr(1, 29, 0) // scene_id = 0 -> game.scene (qube-rocks)
    qview.present()
}
