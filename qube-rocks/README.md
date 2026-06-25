# qube-rocks — Asteroids-lite in the quine engine (no backend)

A small **Asteroids** you fly in the browser: steer a ship, thrust, fire, and
break rocks into smaller rocks. It's a **pure-client** Qube — the whole game runs
in the **quine** 3D engine's deterministic skill. No server, no database, no wRPC.

It's also the **game** companion to [`scene-overlay`](../scene-overlay/): where
that example floats a QView card over a turning cube, this one floats a **reusable
on-screen controller** over a live game — the same "engine scene + linked HTML
overlay, host renders both" composition.

## What it shows

Qube Rocks is the worked example for a set of quine engine features:

| Feature | Where | What it does |
|---|---|---|
| **64 Hz fixed game loop** | `scene.json` → `"fixedHz": 64` | The sim ticks at 64 Hz independent of render rate (a `Time::<Fixed>::from_hz(64.0)` equivalent). |
| **Render interpolation** | `scene.json` → `"interpolate": true` | The renderer lerps between sim ticks by the accumulator overstep, so 64 Hz sim on a 60 Hz screen stays smooth. |
| **Steering** | skill → `transform.rotation` | The ship turns to face its heading from the controller's turn axis. |
| **Spawn / despawn** | skill → `world.spawn` / `world.despawn` | Bullets and rock fragments are created and removed at runtime (cloned from off-screen templates). |
| **Cone mesh** | `scene.json` → `"kind": "cone"` | A built-in directional primitive for the ship (apex = forward). |
| **Reusable controller** | `scene.json` → `"overlay"` | The shared [`controls.js`](https://cdn.qubeworlds.com/overlays/controls.js) overlay maps touch + keys onto the input axes. |

## Controls

The linked `controls.js` overlay renders on-screen buttons (and mirrors the
keyboard), driving the engine's input axes that the skill reads via `input(axis)`:

| Action | Axis | Touch | Keyboard |
|---|---|---|---|
| Turn left / right | 0 | ◄ ► | ← → / A D |
| Thrust | 1 | ▲ | ↑ / W |
| Fire | 2 | ● | Space |

## How it maps to a Bevy game

| Bevy | Qube Rocks |
|---|---|
| `App::new().add_plugins(DefaultPlugins)` | `qube.json5` → `dependencies: com.qubeworlds.quine` |
| `insert_resource(Time::<Fixed>::from_hz(64.0))` | `scene.json` → `"fixedHz": 64` |
| `add_systems(Startup, setup)` | `scene.json` → `entities` |
| `add_systems(FixedUpdate, simulate_game)` | `qube-rocks.skill.js` → `onPreStep(dt)` |
| `add_systems(Update, …)` (input/UI per frame) | the `controls.js` overlay |

## Files

- `qube.json5` — the app manifest: the `com.qubeworlds.quine` engine dependency and `game.scene`.
- `main.q` — a one-screen q64 app: a single full-bleed `scene` viewport (kind 21).
- `scene.json` — the entities, the `fixedHz`/`interpolate` knobs, and the links to the skill + the controller overlay.
- `qube-rocks.skill.js` — the game loop (the engine injects it as the scene's skill).

## Run it

In Qubonaut (`app.qubepods.com`), clone this repo and from this folder:

```sh
qube run
```

The host mounts the quine engine on `game.scene`, injects the skill, and hydrates
the scene's linked `controls.js` overlay over the canvas.

> **Host requirement.** Qube Rocks needs a host that (1) renders the engine
> scene, (2) hydrates the scene's linked HTML `overlay`, and (3) exposes an
> **input seam** the overlay pushes axes through (`host.input(axis, value)` →
> the engine's `{type:"input"}` message). The Qubeworlds **`/scene`** viewer does
> all three — the same surface the `water`/`sundial`/`terrain` examples use with
> the `navigator.js` overlay. If a host renders the scene but doesn't wire the
> input seam, the game draws and simulates but the controller won't drive it yet.
> The engine reaches `cdn.qubeworlds.com` for the bundle + the overlay; if that's
> blocked, the scene still renders and the controls stay inert (graceful
> degradation).
