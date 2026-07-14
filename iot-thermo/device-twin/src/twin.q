//! thermo DEVICE TWIN — one instance per device (the per-entity digital twin).
//!
//! The platform routes each enrolled device's readings to that device's OWN
//! twin instance (manifest `twin: { of: … }` declares the pairing; the DO is
//! keyed `<project>:<this-app>:<node>`). This qube's job is the durable half:
//! every reading is appended to the project database via env.db — the same
//! database the console's Database page shows and the frontend's history API
//! reads. Fan-out to browsers is NOT this twin's job; the fleet twin
//! (../../backend/) does that for the whole project.
//!
//! THE SCHEMA BELONGS HERE, not in the platform. The host calls `setup()`
//! once per deployed artifact (idempotent DDL); each reading then appends a
//! history row. `at` is stamped by SQLite itself (`unixepoch()` DEFAULT) when
//! the statement replays into the project database — q64 v0 interpolates
//! i64s only, and the replay lag is milliseconds.
//!
//! The frame is the packed scalar the platform hands every twin:
//! (device_id << 32 | temp_mc). Identity is the platform's (enrollment),
//! never the wire's — this twin unpacks it for the INSERT.

// Serial inbox (one device's readings, in order).
actor Device {
    state subs: Vec<Sender<i64, Unbounded>> = Vec.new()

    handle Join(tx: Sender<i64, Unbounded>) {
        state.subs.push(move tx)
    }

    handle Report(v: i64) {
        for tx in state.subs { tx.send(v) }
    }
}

// HOST SEAM — one instance per device (this app's per-device DO).
let twin = Device.spawn()

// One-time schema, called by the host on the artifact's first run
// (idempotent). Readings are HISTORY — every report is a row; "latest per
// device" is a query, not a second table.
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

// The channel entry point: this device's packed readings stream up (i64).
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
