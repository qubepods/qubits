//! qubepods.examples.now — the smallest runnable clock.
//!
//! Imports the `clock` library qube (which wraps env.time.monotonic_ns) and
//! prints its reading to stdout, so `qube run` writes the time into the
//! terminal. `clock` itself is a library (no `main`); THIS Qube is the
//! application that links it and runs — the "add a main that uses the library"
//! shape.

import qubepods.examples.clock.{now_ns}

fn main {
    let t = now_ns()
    env.out("monotonic time: {t} ns")
}
