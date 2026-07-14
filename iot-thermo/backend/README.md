# backend — the DASHBOARD TWIN

The frontend's single backend twin, and the aggregation point of the star.
If you remember one thing: **a twin is a deployment, not a route.**

## The mental model

A thermo project has four applications, and each runs in a different place:

| Member | Instances | Runs |
|---|---|---|
| `frontend/` | one **per browser tab** | in each visitor's browser (+ a stateless dynamic worker serving it) |
| `device/` | one **per device** | on each of your enrolled boxes |
| `device-twin/` | one **per device** | on the platform — each device's **digital twin** (persists its readings) |
| `backend/` | **exactly one per project** | on the platform — the **dashboard twin** every browser subscribes to |

Every browser holds ONE WebSocket to this twin; every device reading —
after the device's own twin has written it to the project database —
arrives here and fans out to all of them as a packed
`(device_id << 32 | temp_mc)` i64. A joining frontend is greeted with the
whole fleet's current state, so its gauges fill in before the first live
frame.

This twin deliberately does **not** write the database — persistence is the
device twins' job (one writer per device). When the platform's in-twin read
engine lands, this is where aggregate queries (`env.db.query_*`) over the
project database will live.

## A deployment, not a route

Deploying the frontend gives you a URL. Deploying this member gives you a
**running twin** — no URL of its own. The platform pairs everything by the
project: the frontend's WebSocket routes here because this is the project's
stateful app without a `twin` pairing (the device twins declare
`twin: { of: … }`; this one doesn't — that's what makes it the dashboard twin).
It appears on the console's Applications page like any member (deployments,
versions) — it just has no "open" link. Its output *is* the live frames the
browsers render.

Being its own application is deliberate: the twin deploys **independently**
of the frontend and the device code. A UI rollout never redeploys the twin;
a twin change never touches what browsers are served; and a backend team
can own this member end to end while another team ships the frontend. Small
blast radius, real team boundaries — the project binds the members, the
deployments stay separate.

## Files

- [`src/twin.q`](./src/twin.q) — the dashboard twin: subscriber fan-out, pure
  channel code, no store imports (it builds to the raw core; the db-writing
  twin is [`../device-twin/`](../device-twin/)).
- [`deploy.sh`](./deploy.sh) — clean-builds and ships it as a **stateful**
  deployment (`runtime: "stateful"` is the line that makes it a twin).
  Needs `QUBEPODS_TOKEN` (project token, deploy scope).
- [`src/index.js`](./src/index.js) — the retired v0 stateless JS worker
  (dashboard + `POST /api/report` over `env.KV`), kept for reference; the
  dashboard now lives in [`../frontend/`](../frontend/).

## One project = one dashboard twin

Because the dashboard twin is addressed by the project + this app, a project has
exactly one aggregation point — every frontend and every device converge on
the same state. Want an isolated playground? That's what a second *project*
is for (the platform's staging model).
