//! qubepods.examples.thermo_frontend — placeholder for the browser twin.
//!
//! Destination: the remote controller — a wasm32 qube in the browser holding
//! one wRPC channel over a WebSocket to the backend twin (see
//! ../../twin-counter/, which runs this pattern in production). The backend
//! PUSHES every change (no polling: the gauge moves because the backend said
//! so), and commands travel back up the same channel to the fleet.
//!
//! Until the backend becomes a q64 twin, the dashboard is the HTML page the
//! backend worker serves inline, and this main exists so the member compiles
//! and holds its seat in the workspace.

fn main {
    env.out("thermo_frontend: placeholder — dashboard is served by the backend until the twin lands")
}
