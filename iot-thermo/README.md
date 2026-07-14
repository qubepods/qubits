# thermo — live fleet thermometer

The **IoT starter**: the first example where **your own hardware is part of
the product**. A fleet of devices (Raspberry Pis, or any Linux/macOS box —
or `--simulate` on a laptop) report their SoC temperature; one Qube collects
the readings and serves a live gauge dashboard.

```
 Pi "pi-milano-1" ──┐  POST /api/report (HTTPS)              ┌─ browser
 Pi "pi-milano-2" ──┼───────────────► thermo Qube (env.KV) ◄─┤   polls /api/fleet,
 laptop --simulate ─┘                 *.qubepod.app          └─ renders the gauges
        │
        │  wss /v1/socket — the node TRUNK (hello + telemetry frames)
        └───────────────► qubepods node plane ► console Nodes page
                          (device enrolled, online, geo, temperature)
```

Two independent planes, one agent, one thermometer reading:

- **App plane** — the reading goes to *your* Qube over plain HTTPS and lands
  in the project's key-value store (`env.KV`, auto-bound from the manifest —
  the [api-classic](../api-classic/) pattern). The dashboard is served by the
  same worker and polls `/api/fleet`. This works everywhere, today, with no
  setup beyond `qube deploy`.
- **Node plane** (optional) — the same agent speaks qubepods' own device
  protocol: it exchanges a one-time enrollment token for a private `qnode_`
  credential, then holds the node **trunk** — one *outbound* WebSocket to
  `/v1/socket` carrying JSON control frames on channel 0 (`hello` and
  `telemetry` up, `config` down). Your Pi shows up on the console **Nodes**
  page: enrolled, online the moment the socket is up, geo-located from its
  egress, temperature in the platform telemetry. If the socket can't be
  established, the agent falls back to the 5-minute heartbeat poll — the same
  backup path the platform defines. The device never opens an inbound port.

## Shape — one project, three members

This example is a **workspace**: one qubepods project, three members, one per
host. The destination is three wasm builds of one language — the same q64
actor model in the browser, on the platform, and on your own hardware:

| Member | Runs | Today | Destination |
|---|---|---|---|
| [`device/`](./device/) | your hardware (Pi) | Python agent script | q64 → **wasm32** on the device host; publishes measurements, **handles commands** |
| [`backend/`](./backend/) | the platform | JS worker (deployable now) | q64 twin: aggregates, fans out to frontends, routes commands down |
| [`frontend/`](./frontend/) | the browser | HTML served by the backend | q64 → **wasm32** remote controller, pushed to over one WebSocket |

The frontend↔backend leg is the [twin-counter](../twin-counter/) pattern,
already running in production. The device leg is what this example adds:
telemetry up, commands down, zero inbound ports. Picture the end state as a
robot walking around, driven from a browser — thermo proves the identical
loop with a thermometer (measurements up; "sample faster" / "blink your LED"
down).

## Files

- [`qube.json5`](./qube.json5) — the workspace root binding the members.
- [`backend/qube.json5`](./backend/qube.json5) — the deployable manifest; one
  KV import, nothing else.
- [`backend/src/index.js`](./backend/src/index.js) — the worker:
  `POST /api/report`, `GET /api/fleet`, and the dashboard page.
- [`device/thermo_agent.py`](./device/thermo_agent.py) — the device agent
  the fleet runs today (**requires `python3`** — preinstalled on Raspberry Pi
  OS). Stdlib-only for the app plane; `pip install websocket-client` enables
  the node-plane trunk. Hand-copying it to the device is scaffolding:
  **enrollment is the last manual act** — placing workloads on an enrolled
  node is the platform's job (see [`device/README.md`](./device/README.md)).
- [`device/qube.json5`](./device/qube.json5) +
  [`frontend/qube.json5`](./frontend/qube.json5) — the two q64 members:
  placeholder mains that compile to valid wasm32 components today
  (`qube build --addr wasm32`) and grow into the sensor actor and the
  browser twin.

## Run it

**1. Deploy the Qube** — from `backend/`, in the web shell
([app.qubepods.com](https://app.qubepods.com)) or a terminal after
`qube pod login`:

```console
$ qube deploy
… https://<project>.qubepod.app/
```

**2. Start a device** — no hardware needed for a first look:

```console
$ python3 device/thermo_agent.py --report-url https://<project>.qubepod.app \
    --device demo-1 --simulate
[app] claimed device name "demo-1" — key stored in the state file
[app] reporting as "demo-1" to https://<project>.qubepod.app every 5 s (simulated sensor)
```

Open the dashboard; the gauge is live. Start a couple more (`demo-2`,
`demo-3`) for a fleet. On a real Pi, drop `--simulate` — the agent reads
`/sys/class/thermal` (with a `vcgencmd` fallback).

**3. Put the device on the node plane** (optional): in the console, open your
project → **Nodes** → add a node with role **device** and the Pi's platform
(`linux` / `aarch64` — use 64-bit Raspberry Pi OS). Instead of running the
generated host installer, hand the one-time token to the agent:

```console
$ pip install websocket-client
$ python3 device/thermo_agent.py --report-url https://<project>.qubepod.app \
    --device pi-milano-1 --enroll-token qp_enroll_…
[node] enrolled as pi-milano-1 (node …)
[node] trunk up (wss://api.qubepods.com/v1/socket)
[node] config: heartbeat every 300 s (poll is the backup)
```

The console Nodes page now shows the device online with its location — and it
flips to offline within seconds of you pulling the plug, because presence *is*
the socket, not a stale poll.

## Device identity — claim on first report

The first report for a device name mints a `thermo_…` key, returns it exactly
once, and the worker stores only its SHA-256 — the same hash-at-rest
discipline as the platform's own `qnode_` tokens. Later reports must sign
with the key (the agent handles this via its state file,
`~/.config/thermo-agent/<device>.json`, mode 0600). To retire a device:

```console
$ curl -X DELETE https://<project>.qubepod.app/api/devices/demo-1 \
    -H "Authorization: Bearer thermo_…"
```

It's pairing, not security theater: anyone can claim an *unused* name on your
dashboard, but nobody can impersonate or overwrite a claimed one. For a
private fleet, add a project **secret** as a shared enrollment password (the
[open-sesame](../open-sesame/) pattern) — one `if` in `report()`.

One honest caveat: the worker uses `env.KV` when the substrate injects it,
and falls back to **isolate memory** where it doesn't (the fleet payload says
which via `persistent`, and the dashboard shows a banner). On the ephemeral
fallback, readings reset when an isolate recycles, reads may hit different
isolates, and device keys are **not enforced** — an ephemeral ledger would
re-mint on every recycle and 401 the key it issued a moment ago. Identity is
policed exactly where it can be kept: on the durable store.

## The q64 twin — readings land in the project database

The destination backend ([`backend/src/twin.q`](./backend/src/twin.q)) now
does more than fan out: **every reading persists via `env.db` into the
project's real database** — the one the console's Database page shows. The
twin owns its schema (`setup()` creates `thermo_readings(device, temp_mc,
at)`; the platform calls it once per deployed artifact) and appends one row
per report. The platform packs `(device_id << 32 | temp_mc)` into the i64 it
hands the twin, so the row carries the true device id without identity ever
riding the wire; `at` is stamped by SQLite itself (`unixepoch()` DEFAULT)
when the statement replays — write-behind, milliseconds after the report.

Open your project's **Database** page while the fleet reports and watch
`thermo_readings` grow:

```sql
SELECT device, temp_mc / 1000.0 AS c, datetime(at, 'unixepoch') AS when_utc
FROM thermo_readings ORDER BY at DESC LIMIT 20;
```

Reads from *inside* the qube (`env.db.query_*`) return a typed error until
the platform's in-isolate read engine lands — the honest v0. Querying from
the console (above) works today because it reads the same database the
replay writes.

## Where this example is headed

Thermo deliberately uses only what a customer can reach **today**: the deploy
path, `env.KV`, and the node plane's enroll / trunk / heartbeat surface. The
platform's star fabric is designed to take over more of this, and as it
lands, the example collapses:

- **Data channels over the trunk** — the agent's two uploads (report +
  telemetry) become one published frame, and the dashboard stops polling: the
  browser subscribes to the same channel and the gauges stream.
- **An `env.sensors` face** — the Python agent becomes a q64 qube that the
  scheduler *places* on your devices (`target: "nodes"` in the manifest), no
  script to copy.
- **Bind-leases + re-place-on-death** — the failover drill: kill the box
  aggregating the fleet and watch the work hop to another node while the
  gauges never flicker.

Until then, this is the honest v0 — and it already does the thing no
browser-only stack can: your hardware, in the loop, with zero inbound ports.
