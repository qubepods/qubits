//! qubepods.examples.thermo_device — the sensor loop that runs ON the device.
//!
//! Placed by the platform (see `placement` in ../qube.json5: every project
//! node tagged `thermo` runs this), executed by the Qubepods Host. One
//! reading every 15 seconds, forever. The device is an actor, not a sensor
//! pipe — commands ride down the same trunk these readings ride up.
//!
//! The temperature arrives through a capability face, never the filesystem:
//! the HOST reads /sys/class/thermal (the sandbox cannot and must not) and
//! serves it as the identity-scoped key `soc-temp-mc` (millidegrees C). The
//! read idiom is the kv face's own documented one — a +0 increment returns
//! the current value as a typed i64 (see q64's kv-counter example). This is
//! the v0 stand-in for the coming `env.sensors` face: q64's `env.fs` is not
//! implemented yet and `env.config.get` returns a string q64 cannot parse to
//! a number yet — `env.kv` is the one proven face with a numeric answer.
//! When `env.sensors` lands, `read_milli` changes and nothing else does.
//!
//! Next step (once ../../backend is the q64 twin): replace `env.out` with a
//! wRPC channel session — `connect<report>()` + `session.send(m)` — the
//! twin-counter pattern, so the backend pushes every reading straight to the
//! dashboard. Until then the host captures this output as the workload's
//! telemetry.

// The SoC temperature in millidegrees C, via the host-served sensor key.
// Negative sentinel when the host doesn't provide the face.
fn read_milli() -> i64 {
    match env.kv.increment("soc-temp-mc", 0) {
        Ok(m)  -> m
        Err(_) -> 0 - 1
    }
}

fn main {
    loop {
        let m = read_milli()
        env.out("thermo_device: soc temperature {m} m°C")
        env.time.sleep_ns(15_000_000_000)
    }
}
