# backend — the project's TWIN

The piece both other members talk to. If you remember one thing: **the
backend is a deployment, not a route.**

## The mental model

A thermo project has three kinds of code, and each runs in a different place:

| Member | Instances | Runs |
|---|---|---|
| `frontend/` | one **per browser tab** | in each visitor's browser |
| `device/` | one **per device** | on each of your enrolled boxes |
| `backend/` | **exactly one per project** | on the platform — as the project's **twin** |

The backend is called a *twin* because that's what it is: the always-on
digital twin of your fleet. Devices stream readings **up into it**; browsers
subscribe **down from it**; it holds the shared state and does the durable
writes. It is not "part of" the frontend or the device — it's the meeting
point they pair through.

## A deployment, not a route

Deploying the frontend gives you a URL. Deploying the backend gives you a
**running twin** — no URL of its own, no worker to point at. The platform
pairs everything by the **project**:

1. A browser opens the frontend and its WebSocket goes to the app's own URL.
   The platform sees the app is `runtime: "stateful"` and routes the socket
   to the project's twin — one shared instance, created on first contact.
2. The twin loads **this member's deployed artifact** and runs it for every
   message that arrives — a reading from a device, a join from a browser.
3. The twin's `env.db` writes land in the **project database** — the same
   one your console's Database page shows.

So the backend appears on the console's Applications page like any other
member (it has a manifest, a name, deployments and versions) — it just has
no "open" link. Its output *is* the live state the frontends render and the
rows in your database.

Being its own application is deliberate: the twin deploys **independently**
of the frontend and the device code. A UI rollout never redeploys the twin;
a twin change never touches what browsers are served; and a backend team
can own this member end to end while another team ships the frontend. Small
blast radius, real team boundaries — the project binds the members, the
deployments stay separate.

## Files

- [`src/twin.q`](./src/twin.q) — the twin. Owns the schema
  (`setup()` creates `thermo_readings`; the platform calls it once per
  deployed artifact), appends one row per reading via `env.db`, and fans
  each reading out to every connected frontend. Build:
  `qube build --addr wasm32` → the `.kvcore` artifact is what the twin
  runtime runs. **Requires q64 ≥ 0.0.10** (0.0.9 emits a trapping module
  for db twins).
- [`deploy.sh`](./deploy.sh) — builds and ships the twin as a **stateful**
  deployment (`runtime: "stateful"` in the deploy manifest is the line that
  makes it a twin). Needs `QUBEPODS_TOKEN` (project token, deploy scope);
  until `qube deploy` packs the `.kvcore` artifact itself, this script is
  the deploy path.
- [`src/index.js`](./src/index.js) — the retired v0 **stateless** JS worker
  (dashboard page + `POST /api/report` over `env.KV`). `qube.json5` now
  deploys the twin instead; the worker stays as reference until the
  frontend member takes over the dashboard (a twin has no HTTP surface —
  pages belong to the frontend).

## One project = one twin

Because the twin is addressed by the project, a project has exactly **one**
backend. That's a feature, not a limit: every frontend and every device in
the project converge on the same state. Want an isolated playground? That's
what a second *project* is for (the platform's staging model).
