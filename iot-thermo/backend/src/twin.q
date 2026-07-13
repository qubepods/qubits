//! thermo backend TWIN — the q64 wasm half of the example's destination.
//!
//! One instance per project (the ProjectTwin Durable Object). A device
//! connects and streams its SoC temperature (millidegrees C) up the channel
//! as a bare i64; the twin fans each reading out to every connected frontend,
//! so a browser gauge updates the moment the Pi reports. This is the
//! twin-counter pattern (../../twin-counter/) applied to a sensor fleet.
//!
//! Runs as a CORE module in the ProjectTwin (env.channel_* + env.kv served
//! over WASI); component packaging of raw env.* is a tracked q64 gap, so the
//! twin runtime runs the core directly — verified: `qube build --addr wasm32`
//! emits it with imports env.channel_recv / env.channel_send / wasi:keyvalue
//! and export `report`.
//!
//! DEVICE IDENTITY IS NOT ON THE WIRE. q64 channels carry bare scalars today
//! (not structs — a hard-verified codegen limit), and they don't need to: the
//! platform already knows which node a connection is (enrollment + the node
//! credential). The DO tags each reading with its sender and packs
//! (device_id << 32 | temp) into the i64 it broadcasts; the frontend unpacks
//! and renders a gauge per id. Identity lives where it is authoritative.

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

// The channel entry point: readings stream up (i64), the fleet's readings
// stream down to this session.
@channel_handler
pub fn report(session: Channel<i64, i64>) @wire {
    let (tx, rx) = channel<i64>(policy: Unbounded)
    twin.tell(Join(move tx))
    spawn { for n in rx { session.send(n) } }
    for v in session { twin.tell(Report(v)) }
}
