# Stopwatch

**Two qubes bound into one Qube.** `stopwatch` is an application qube whose
`main()` links [`adder`](../adder/) (a pure library — empty world) and
[`clock`](../clock/) (a library importing the monotonic clock), times the
`add()` call, and prints the span:

```q
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
```

```
$ qube build --component --addr wasm32
# → target/debug/wasm32/qubepods.examples.stopwatch.component.wasm

$ # transpile + run (jco maps the WASI imports to Node):
add(2, 3) = 5
elapsed: 675038 ns
```

(The ~675µs is the jco/Node host's clock-call overhead — two JS shim round
trips bracket the add. A native component host reads the clock in tens of
nanoseconds.)

## How the binding works

The manifest's `dependencies` block names the two qubes; keys are full qube
names, which double as the module paths `import` uses:

```json5
dependencies: {
  "qubepods.examples.adder": { path: "../adder" },
  "qubepods.examples.clock": { path: "../clock" },
}
```

`qube build` resolves each dependency to its source and hands everything to
one `q64 emit` — the linked qubes become plain functions inside the Qube's
single core module (in the emitted wasm, `main` is literally
`call now_ns; call add; call now_ns; i64.sub`). A published qube would be
named with a version range instead and resolved via the Continuum.

## The capability closure

The Qube's contract is the closure over everything it links: `adder`
contributes nothing, `clock` contributes the monotonic clock, `main`'s
`env.out` adds stdout — all visible in the synthesized world:

```wit
world stopwatch {
  import wasi:cli/stdout;
  import wasi:clocks/monotonic-clock;
  export wasi:cli/run;
}
```

Because `main()` prints, the component is built as a `wasi:cli/run`
**command**: the core's `fd_write`/`clock_time_get` preview1 syscalls are
lifted by the vendored WASI adapter, so any component runtime (wasmtime,
jco) can execute it.
