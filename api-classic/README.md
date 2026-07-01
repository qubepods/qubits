# api-classic

A **classic request/response HTTP API**, built the way every qubepods app is
built: **one manifest, two commands.** It stores data in the project's
**key-value store, SQLite database, and object storage** — and it never names a
namespace, a database, or a bucket. That capability boundary is the whole point.

It's the request/response sibling of [`twin-counter`](../twin-counter/): same
manifest-driven model, but an `@http_handler` (a plain HTTP endpoint) instead of a
live wRPC channel. This is the "backend with real KV + SQL + R2" example from the
platform's [example roadmap](https://qubepods.com) (#4 — *the twin architecture
for real*).

## What it proves

> "What can this do that a vibe-coded React app can't?"

A **capability-bounded backend**: the qube asks for `@kv`, `@db`, `@blob` in its
manifest and reaches them through `env.kv` / `env.db` / `env.blob`. qubepods opens
each store, **pins it to this qube's identity** (org/project/app), and meters the
calls. The app *cannot* read another tenant's data — enforced by the runtime, not
by a `WHERE user_id = ?` you hope you didn't forget. No Cloudflare, no bucket
names, no connection strings, no `wrangler.jsonc`.

## The whole lifecycle — two commands

There is **one** manifest ([`qube.json5`](./qube.json5)) and it declares what the
app *is* (an HTTP application) and what it *needs* (`effects: [@kv, @db, @blob,
@network]`). You never write a deploy script, a token, or a per-cloud config.

```sh
qube run      # build + serve locally in the shell — hit the endpoints, test it
qube deploy   # ship it; qubepods serves it at a per-qube HTTPS endpoint
```

Both run in **Qubonaut** (the in-browser IDE at `app.qubepods.com`) — the q64
compiler is itself wasm, so this works on an **iPad** just as well as a desktop
terminal. `qube run` walks up to the nearest `qube.json5`, builds `entry`
(`src/main.q`), and serves the handler; `qube deploy` packs the component and
uploads it. Whatever the deploy step bundles internally is a transient build
artifact — **not** a file you author or maintain.

## Use it

Create a project with the **Backend** switch **on** (same as `twin-counter` — it
provisions the KV + SQLite + object storage that `env.kv`/`env.db`/`env.blob` bind
to; chosen once at creation). Then, in the Qubonaut terminal:

```sh
git clone https://github.com/qubepods/qubits.git
cd qubits/api-classic
qube run
```

### Endpoints

| Method + path | Store | What it does |
|---|---|---|
| `POST /visit` | `env.kv` | atomic `increment("visits", 1)` → the new count |
| `GET /visits` | `env.kv` | read the counter |
| `POST /events` | `env.db` | append the request body as a row (SQLite) |
| `GET /events` | `env.db` | the 50 most recent rows as JSON |
| `PUT /assets/<key>` | `env.blob` | store the request body as an object |
| `GET /assets/<key>` | `env.blob` | read the object back |

`visits` / `events` / `assets/*` are the shared "stats" a future **api-twin** app
in the *same project* would read — one project, one set of stores, shared state.

## Files

| File | What it is |
|------|------------|
| [`qube.json5`](./qube.json5) | The manifest — `type: application`, `component.worlds: ["wasi:http/proxy"]` (serve HTTP), and `effects: [@kv, @db, @blob, @network]`. No storage bindings: the host opens the stores by identity. |
| [`src/main.q`](./src/main.q) | The whole app — one `@http_handler` routing over `env.kv`, `env.db`, `env.blob`. |

## Status (honest, like twin-counter's `COMPILER-READINESS.md`)

This example is written against the **target** q64 surface, the same way
`twin-counter` is. `env.kv` is proven end-to-end there. The `@http_handler` entry
point, `env.db` (SQLite), and `env.blob` (object storage) are specified in
`env.md` and back roadmap #4's "Pod provider bindings"; where the compiler or host
adapter is still catching up to a face, that's a platform seam, not a change to how
*this* qube is written. The manifest and the `env.*` faces are the real, stable
contract — no raw Cloudflare, ever.
