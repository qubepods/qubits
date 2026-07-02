//! qubepods.examples.stopwatch — two qubes bound into one Qube.
//!
//! `add` comes from qubepods.examples.adder (a pure qube — empty world);
//! `now_ns` from qubepods.examples.clock (imports the monotonic clock).
//! main() brackets the add with two clock readings and prints the span:
//!
//!   add(2, 3) = 5
//!   elapsed: 787780 ns        (jco/Node host; a native host reads far lower)
//!
//! The Qube's capability set is the closure over everything it links:
//! adder contributes nothing, clock contributes @time, main itself adds
//! @stdout — and all three are visible in the emitted component's world.

import qubepods.examples.adder.{add}
import qubepods.examples.clock.{now_ns}

fn main {
    let t0 = now_ns()
    let sum = add(2, 3)
    let t1 = now_ns()
    let ns = t1 - t0
    env.out("add(2, 3) = {sum}")
    env.out("elapsed: {ns} ns")
}
