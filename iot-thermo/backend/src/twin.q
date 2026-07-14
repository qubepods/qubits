//! thermo backend TWIN — the q64 wasm half of the example's destination.
//!
//! One instance per project (the ProjectTwin Durable Object). A device
//! connects and streams its SoC temperature (millidegrees C) up the channel;
//! the twin PERSISTS each reading via env.db — into the project's real
//! database, the one the console's Database page shows — and fans it out to
//! every connected frontend, so a browser gauge updates the moment the Pi
//! reports. This is the twin-counter pattern (../../twin-counter/) applied
//! to a sensor fleet, plus the platform's env.db face (write-behind: the
//! statements replay into the project database in order).
//!
//! Runs as a CORE module in the ProjectTwin (env.channel_* + q64:db/sql
//! served at the core seam); component packaging of raw env.* is a tracked
//! q64 gap, so the twin runtime runs the core directly — verified:
//! `qube build --addr wasm32` emits the `.kvcore` artifact with imports
//! env.channel_recv / env.channel_send / q64:db/sql and exports
//! `cm32p2||setup` / `cm32p2||report`.
//!
//! DEVICE IDENTITY IS NOT ON THE WIRE. q64 channels carry bare scalars today
//! (not structs — a hard-verified codegen limit), and they don't need to: the
//! platform already knows which node a connection is (enrollment + the node
//! credential). The DO packs (device_id << 32 | temp_mc) into the i64 it
//! hands the twin AND broadcasts; this twin unpacks it for its INSERT, and
//! the frontend unpacks it to render a gauge per id. Identity lives where it
//! is authoritative.
//!
//! THE SCHEMA BELONGS HERE, not in the platform. The host calls `setup()`
//! once per deployed artifact (idempotent DDL); each reading then appends a
//! history row. `at` is stamped by SQLite itself (`unixepoch()` DEFAULT) when
//! the statement replays into the project database — q64 v0 interpolates
//! i64s only, and the replay lag is milliseconds.

// The twin: the connected frontends' senders, one serial inbox.
actor Fleet {
    state subs: Vec<Sender<i64, Unbounded>> = Vec.new()

    // A frontend joined: keep its sender for fan-out.
    handle Join(tx: Sender<i64, Unbounded>) {
        state.subs.push(move tx)
    }

    // A device reported a reading: fan it out to every frontend.
    handle Report(v: i64) {
        for tx in state.subs { tx.send(v) }
    }
}

// HOST SEAM — one twin per project (the ProjectTwin DO instance).
let twin = Fleet.spawn()

// One-time schema, called by the host on the artifact's first run
// (idempotent). Readings are HISTORY — every report is a row; the dashboard's
// "latest per device" is a query, not a second table.
pub fn setup() -> i64 {
    match env.db.execute("CREATE TABLE IF NOT EXISTS thermo_readings(device INTEGER NOT NULL, temp_mc INTEGER NOT NULL, at INTEGER NOT NULL DEFAULT (unixepoch()))") {
        Ok(_)  -> 1
        Err(_) -> 0 - 1
    }
}

// Append one reading — the interpolated i64s are the v0 param mechanism.
fn save(device: i64, temp_mc: i64) -> i64 {
    match env.db.execute("INSERT INTO thermo_readings(device, temp_mc) VALUES({device}, {temp_mc})") {
        Ok(rows) -> rows
        Err(_)   -> 0 - 1
    }
}

// The channel entry point: packed readings stream up (i64), the fleet's
// readings stream down to this session.
@channel_handler
pub fn report(session: Channel<i64, i64>) @wire {
    let (tx, rx) = channel<i64>(policy: Unbounded)
    twin.tell(Join(move tx))
    spawn { for n in rx { session.send(n) } }
    for v in session {
        let device = v >> 32
        let temp_mc = v & 4294967295
        let saved = save(device, temp_mc)
        twin.tell(Report(v + saved * 0))
    }
}
