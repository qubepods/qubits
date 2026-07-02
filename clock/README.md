# Clock

A **library qube wrapping one capability** — the monotonic clock:

```q
pub fn now_ns() -> i64 { env.time.monotonic_ns() }
```

The counterpart to [`adder`](../adder/): the same one-function library shape,
but where adder's world is empty, this qube's world carries an **import** —
linking it into a Qube adds `@time` to that Qube's capability set:

```wit
package qubepods-examples:clock;

world clock {
  import wasi:clocks/monotonic-clock@0.2.0;
  export now-ns: func() -> s64;
}
```

```
qube build --component --addr wasm32
# → target/debug/wasm32/qubepods.examples.clock.component.wasm   (693 bytes)
```

## What it shows

- **Capabilities are inferred, not declared.** The source never mentions
  wasi:clocks — calling the `env.time` face is what derives the import
  (`q64 show capabilities` says `@time`).
- **The bare-scalar face.** `monotonic_ns()` is nullary and returns a plain
  `i64` — no Result box, no allocation, no linear-memory involvement. The
  canonical ABI crosses in registers alone, which is why this is the one
  capability marked `@realtime`-safe in the q64 spec.
- **The host owns the clock.** A runtime satisfies the import with whatever
  clock it pins to the qube — `hrtime.bigint()` under Node/jco, the native
  monotonic clock under wasmtime. The qube only ever sees the instant it
  asked for.

See [`stopwatch`](../stopwatch/) for this qube linked together with `adder`
into a runnable Qube.
