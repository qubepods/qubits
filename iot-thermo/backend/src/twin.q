//! thermo DASHBOARD TWIN — the frontend's backend twin, one instance per project.
//!
//! The aggregation point of the star: every browser holds ONE WebSocket to
//! this twin, and every device reading — after the device's OWN twin
//! (../../device-twin/) has persisted it — arrives here and fans out to all
//! of them as a packed (device_id << 32 | temp_mc) i64. A joining frontend
//! is greeted with the whole fleet's current state, so the gauges fill in
//! before the first live frame.
//!
//! This twin deliberately does NOT write the database — persistence is the
//! device twins' job (one writer per device, no duplicate rows). When the
//! platform's in-twin read engine lands, this is where the aggregate queries
//! (env.db.query_*) over the project database will live.

// The connected frontends' senders, one serial inbox.
actor Fleet {
    state subs: Vec<Sender<i64, Unbounded>> = Vec.new()

    // A frontend joined: keep its sender for fan-out.
    handle Join(tx: Sender<i64, Unbounded>) {
        state.subs.push(move tx)
    }

    // A reading arrived: fan it out to every frontend.
    handle Report(v: i64) {
        for tx in state.subs { tx.send(v) }
    }
}

// HOST SEAM — one twin per project (this app's twin instance).
let twin = Fleet.spawn()

// The channel entry point: packed readings stream up (i64), the fleet's
// readings stream down to this session.
@channel_handler
pub fn report(session: Channel<i64, i64>) @wire {
    let (tx, rx) = channel<i64>(policy: Unbounded)
    twin.tell(Join(move tx))
    spawn { for n in rx { session.send(n) } }
    for v in session { twin.tell(Report(v)) }
}
