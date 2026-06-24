# cube — a turning 3D cube with a QView overlay

A **q64** application that renders a **turning 3D cube with a form floating over
it**. The cube is drawn by a real game engine; the form is QView. They composite
into one view — 3D behind, UI on top.

It also **links a second qube**: `test.color` (in [`color/`](./color)), a small
**library** qube whose `random_color(seed)` returns a packed `0xAARRGGBB`. The
**Tap +1** handler calls it and paints a colour swatch — a real cross-qube call
(scalar in, scalar out). See [The second qube](#the-second-qube--testcolor) and
[Does this compile + link online?](#does-this-compile--link-online).

Built by Claude as an end-to-end test of the Qubonaut loop, and as the first user
of QView's new **`scene` viewport** (kind 21, protocol 1.11):
**clone/pull on iPad → `qube build` → Preview**.

## How it works

- `main.q` creates a **`scene`** node (`kind 21`) with `scene_id 0`. A `scene`
  node is a **content-agnostic 3D viewport**: the producer names a scene by
  integer id, the **host** renders it — no geometry, strings, or GPU calls cross
  the wasm boundary. On the web the host renders it with the **quine** game engine
  (loaded from `cdn.qubeworlds.com`) on a canvas **behind** the QView surface; a
  native host would render the same id through its own 3D backend. Scene `0` is
  the host's turning cube (an SDF box with a `spin` component, lit, orbit camera).
- The **frosted card** below (a `column` with `surface: material`) is a normal
  QView subtree that composites **on top** — that layering is the overlay. The
  card holds a title, a live count, and a **colour swatch** (a plain `box` whose
  `fill` is a packed `0xAARRGGBB`).
- The **Tap +1** button bumps the live count (surgical `set_attr` on the count
  label) **and** asks the linked `test.color` qube for a fresh colour
  (`random_color(taps)`), repainting the swatch's `fill`. That call is the
  cross-qube link in action — the app gets a colour from a separate library qube
  and sets it on a node.

## The second qube — `test.color`

[`color/`](./color) is a separate **library** qube (`type: library`):

- `color/src/lib.q` — `pub fn random_color(seed: i64) -> i64`: a deterministic
  per-channel integer hash → a bright, opaque packed `0xFFRRGGBB`. (q64 cores are
  deterministic — no host RNG — so "random" is a hash of the tap count; each tap
  lands on a visibly different bright colour.)
- `color/qube.json5` — the library manifest.

`main.q` declares it as a dependency (`qube.json5` → `dependencies.test.color`)
and `import test.color.{random_color}`s it. `qube build` resolves the path and
links the library **into** the app's core module — `q64 emit … --module
test.color=color/src`. This is q64 **module linking** (the library's function is
compiled into the app's wasm), which is the right fit here because the app is a
**QView host-face module** (it imports `qview`), not a scalar component. The
component-model `qube wac` link is for scalar component-to-component wiring, not
a host-face app — so this example uses module linking, not `wac`.

## The reusable composite

The scene+form pattern is a reusable QView component-registry **block**,
`scene_overlay`, vendored under `src/ui/` (copy-and-own — you own these files):

- `src/ui/scene_overlay.q` — the block: a `scene` viewport + an overlaid `card`.
- `src/ui/card.q` — a frosted, theme-resolved container.
- `src/ui/proto.q` — named `KIND`/`ATTR` constants (the `q64.view.proto` mirror).
- `src/ui/ui.lock.json5` — pins the components to `PROTOCOL_VERSION 1.11`.

`main.q`'s **UI** is the LOWERED form of that block (plain `qview.*` ops, no
multi-file `use` — the registry `use` isn't wired on the on-device compiler yet).
Its **logic**, though, now links the `test.color` library qube (a `--module`
dependency, above), so the app is **no longer a single standalone file** — it
needs the dependency resolved at build (`qube build`, or `q64 emit … --module
…`). The canonical design lives in q64 `spec/qview-protocol.md` §"3D scene
viewport" and `spec/qview-ui-registry.md`.

## Files

- `main.q` — the app (q64). The `qview` face: `create / set_attr / on / present`,
  a `state` global, an `on_5` press handler, and `import test.color.{random_color}`.
- `color/` — the **`test.color` library qube** (`random_color`), linked into the app.
- `src/ui/` — the vendored `scene_overlay` registry block (the reusable composite).
- `qube.json5` — the app manifest (`type: application`, `dependencies.test.color`).

## Run it

On the Qubonaut iPad app:

```sh
git pull            # get this repo (app + the color/ library qube)
qube build          # resolves dependencies.test.color → links color/src into the app
# open the Preview tab — the cube turns, the card floats over it,
# and Tap +1 repaints the swatch with the library's colour
```

Locally (with the q64 toolchain) — the link is an explicit `--module`:

```sh
q64 emit main.q main.wasm --addr wasm32 --module test.color=color/src
# render via q64/runtime/web-retained (./build.sh --serve) in a WebGPU browser

# the library itself runs/links standalone too:
q64 emit color/src/lib.q color.wasm --addr wasm32 --component
wasmtime run --invoke 'random-color(3)' color.component.wasm   # -> 4288855754 (0xFFA2BECA)
```

The Preview/host must reach `cdn.qubeworlds.com` to load the engine bundle; if it
can't (offline / blocked), the form still renders and the 3D area stays dim
(graceful degradation).

## Does this compile + link online?

Short answer (as of 2026-06-24): **it builds and links with the native q64
toolchain (above), and now in the qubepods web shell (stage) too.**

- **Native q64 + `qube` CLI** — ✅ works today. `qube build` resolves the
  `test.color` dependency and module-links it; the library also emits a
  component and runs under `wasmtime` (shown above).
- **In-browser web shell (`qube run`)** — ✅ the deploy now stages the
  `/compiler/` (q64→wasm + `qube-resolve.wasm`), `/wac/`, and `/qview/` Preview
  host (and a `verify-app-assets.sh` guard fails the deploy if any is missing —
  the `single-page-application` fallback used to ship them silently absent). The
  shell resolves a **multi-qube project** through `qube-resolve.wasm` — the same
  resolver the native CLI uses — so the `test.color` path dependency is linked in
  (`--module test.color=color/src`), not just a single `.q` file. The 3D engine
  (`com.qubeworlds.quine`) is host-mounted from `cdn.qubeworlds.com`; if that's
  blocked the form still renders and the 3D area stays dim (graceful degradation).

(Note: a host-face QView app like this links its library by **module linking**,
not the component-model `qube wac` link — see [The second qube](#the-second-qube--testcolor).)

## Note on text

QView Stage-1 is text-by-id: a label's `text_id >= 1000` shows the host glyph
catalog string (`1011` = "Tap +1", `1034` = "Turning cube"); `text_id < 1000`
renders the integer itself, which is how the count label shows the live number.
Custom label strings are added to the host catalog (no strings cross the wasm
boundary yet).
