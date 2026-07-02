//! qubepods.examples.clock — the time component.
//!
//! One export wrapping one capability: `env.time.monotonic_ns()`, the
//! monotonic clock in nanoseconds. The face is nullary and returns a plain
//! i64 — no Result box, no allocation — so the emitted component's world is
//! one import and one export:
//!
//!   qube build --component --addr wasm32
//!   # → world imports wasi:clocks/monotonic-clock, exports now-ns
//!
//! Contrast with `adder`: same shape of qube, but this one's world is not
//! empty — linking it into a Qube adds @time to that Qube's capability set.

// The monotonic clock reading, in nanoseconds since an arbitrary origin.
// Instants only compare against other instants from the same clock.
pub fn now_ns() -> i64 { env.time.monotonic_ns() }
