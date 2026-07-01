# CLAUDE.md — qubits

Example [Qubes](https://qubepods.com) you can read, pull, and deploy. Each
top-level folder is a self-contained [q64](https://q64.dev) qube with its own
README (see the table in `README.md`). They are real source, built and shipped
with the **`qube`** CLI — no separate build system lives here.

## The `qube` binary — pull it from the release, don't build q64

These examples are exercised with the `qube` CLI (`qube run`, `qube deploy`),
usually from the Qubonaut terminal at `app.qubepods.com`. If you need `qube`
**locally** (e.g. to reproduce a deploy in a cloud session), do **not** clone
and build the q64 repo from source — fetch the prebuilt binary from the
`q64-lang/q64` GitHub release:

```sh
base=https://github.com/q64-lang/q64/releases/latest/download
curl -fsSL "$base/qube-linux-amd64" -o qube && chmod +x qube
curl -fsSL "$base/manifest.json"   # every platform's URL + sha256 — verify first
```

The release carries native `qube` (linux + macOS, amd64/arm64) and `q64`
(linux-amd64 + macOS). Building q64 from source is only needed when you change
q64 itself — never just to run an example here.

## Conventions

- Qube names are **snake_case** — no hyphens (a hyphen in a qube name is
  rejected by `qube`; that's why the folder is `qube-rocks` but its qube id is
  `qubepods.examples.qube_rocks`).
- **static-asset qubes** (`static: { dir: "web" }` in `qube.json5`, e.g.
  `qube-rocks`, `blackbird`) ship the `web/` folder as-is — no q64 compile, no
  component, no backend. Default the engine/page to **WebGL2** (`?gpu=webgpu`
  is opt-in) so the 3D renders on the broadest set of devices.
- Examples that render 3D load the shared **quine** engine from the CDN; UI is
  an HTML **overlay** (e.g. the reusable `controls.js` game controller the
  `water`/`sundial`/`terrain`/`qube-rocks` examples share), never baked into
  the engine.
