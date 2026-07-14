# device-twin — the per-device digital twin

One instance of this app runs **per enrolled device** — never shared. It is
the durable half of the device's presence on the platform: every reading the
device reports is appended to the **project database** via `env.db`, by this
twin and nobody else (one writer per device — no duplicate rows, no write
contention).

## The pairing is declared, not configured

```json5
// qube.json5
twin: { of: "qubepods.examples.thermo_device" }
```

That one line is the whole wiring. The platform derives everything else: a
reading arriving from an enrolled device is routed to **that device's own
instance** of this app (keyed by the project, this app, and the device), with
the artifact resolved from the live deployment — the device itself carries no
knowledge of this app's existence.

## What it owns

- **The schema.** `setup()` (called by the platform once per deployed
  artifact) creates `thermo_readings(device, temp_mc, at)` — idempotent DDL,
  history rows, timestamps stamped by SQLite itself.
- **The writes.** One `INSERT` per reading. "Latest per device" is a query,
  not a second table.

What it deliberately does NOT do: fan out to browsers. That's the **fleet
twin** ([`../backend/`](../backend/)) — the frontend's single backend twin,
which every reading also reaches for live push.

## Deploy

```console
$ QUBEPODS_TOKEN=qube_… ./deploy.sh
```

Builds the `.kvcore` store-component core (requires q64 ≥ 0.0.10) and ships
it as a stateful deployment with the twin pairing in the manifest. Like every
twin: **a deployment, not a route**.
