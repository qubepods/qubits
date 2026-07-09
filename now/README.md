# Now

**The smallest runnable clock.** `now` is an application qube — it has a
`main`, so `qube run` executes it and you see an outcome. It links the
[`clock`](../clock/) library qube (which wraps `env.time.monotonic_ns()`) and
prints the reading to the terminal:

```q
import qubepods.examples.clock.{now_ns}

fn main {
    let t = now_ns()
    env.out("monotonic time: {t} ns")
}
```

```
$ qube run
compiling src/main.q + 1 linked qube…
monotonic time: 32213020 ns
```

That's the whole point of the pair: [`clock`](../clock/) is a **library**
(`type: "library"` — one function, no `main`), so `qube run` on it has nothing
to execute. `now` is the **application** that links it and runs — the "add a
`main` that uses the library" shape, the runnable sibling of the library.

## How the link works

The manifest's `dependencies` block names the qube; the key is the full qube
name, which doubles as the module path `import` uses:

```json5
dependencies: {
  "qubepods.examples.clock": { path: "../clock" },
}
```

At build the linked qube becomes a plain function in one core module —
`now_ns()` is called directly, no cross-module call overhead. The capability
closure follows the code: `clock` contributes `@time`, `main` adds `@stdout`,
so the emitted world imports the monotonic clock + stdout and nothing else.

## Run it

```
qube run        # build + run: prints the monotonic time to the terminal
qube build      # just compile the linked core module
```

The monotonic clock counts nanoseconds from an arbitrary origin (compare two
readings for a duration — that's what [`stopwatch`](../stopwatch/) does); it is
not a wall-clock date. For the elapsed-time example, see `stopwatch`.
