//! qubepods.examples.thermo_device — placeholder for the on-device qube.
//!
//! Destination: an actor placed on the fleet by the scheduler and run by the
//! device host (wasmtime/Pulley — wasm32, so a 32-bit ARMv7 Pi from 2015 is a
//! full citizen). It reads the SoC temperature through the `env.sensors`
//! face (the HOST reads /sys/class/thermal; the sandboxed qube cannot and
//! must not), publishes measurements up the trunk, and HANDLES commands
//! coming down — set the sample interval, blink the LED; in the robot
//! version of this architecture, drive.
//!
//! Until that face lands, the fleet runs ../thermo_agent.py, and this main
//! exists so the member compiles and holds its seat in the workspace.

fn main {
    env.out("thermo_device: placeholder — awaiting env.sensors; run ../thermo_agent.py on the fleet")
}
