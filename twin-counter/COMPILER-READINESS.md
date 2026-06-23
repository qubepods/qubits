# twin-counter — compiler readiness & the path forward

`backend.q` and `frontend.q` are written against the **target** q64 language.
**Both now emit to wasm as written** through the q64 codegen — verified against
`q64 emit` + wasm instantiation (a stub-host round-trip in
`q64-test/tests/build.test.ts`), not aspirational. This note is the honest map:
what runs, what landed, and the one behavioural gap that's left (the live
outbound pump — the runtime ABI's job).

It answers one question in particular: **how does the frontend↔backend wire
actually get built?** q64's cross-qube story is the component model + wRPC,
driven by the `rpc` block in `qube.json5`: the frontend opens its end with
`connect<counter.join>()` and the import (`import counter.{join}`) resolves
against the backend (the `counter` qube) at build — `--module counter=<backend>`
locally, the `rpc.import` binding on deploy. See `spec/rpc.md` in the q64 repo.

## Status legend

- ✅ **runs** — compiles through `q64 emit` and executes on the host.
- 🟡 **partial** — a narrower form runs; the twin uses a richer one.
- ⬜ **gap** — not yet lowered by codegen.

## The backend, construct by construct

| `backend.q` uses | Maps to | Status |
|---|---|---|
| `match env.kv.increment(…) { Ok(n) -> …, Err(_) -> … }` | `env.kv` → `wasi:keyvalue`, returns `Result<i64>` | ✅ runs — **keyed** `("count", 1)` and keyless both, returning `Result<i64>` |
| `Vec.new()` + `.push` + `for tx in …` | growable Vec + iteration | ✅ runs (the empty growable + fan-out loop) |
| `spawn { … }` (fire-and-forget) | cooperative task, eager v0 | ✅ runs (main / `for` / `if` bodies) |
| method-style actor (`var c = C{}`, `c.m()`) | actor = self-taking fns | ✅ runs |
| `Vec<Sender<…>>` + `subs.push(move tx)` + `for tx in subs { tx.send(n) }` | fan-out over channel endpoints | ✅ runs **standalone** — a Sender is its buffer pointer (i64), pushed/iterated/`.send` works; multi-subscriber broadcast verified. Still a gap *inside an actor's state* (see #2c) |
| `move tx` / `ref x` | ownership qualifiers | ✅ runs (v0 identity — no borrow tracking yet) |
| `for n in rx` | recv loop over a channel | ✅ runs (drains the buffer in order) |
| `actor Counter { state subs: Vec<Sender> … handle Join(tx) handle Bump }` + `tell`/`ask`/`spawn` | **message-style** actor + **live fan-out** | ✅ runs — `state subs: Vec<Sender>`, `handle Join(tx: Sender<…>) { state.subs.push(tx) }`, `handle Bump { for s in state.subs { s.send(n) } }`; two subscribers both receive the broadcast |
| `let twin = Counter.spawn()` **at module level** | one module-lifetime singleton (HOST SEAM 1) | ✅ runs — allocated once by the wasm `start`, self-pointer kept in a module global; every `twin.tell/ask` shares the one instance (`ping()` → 1, 2, 3 verified) |
| `handle Bump @kv` / `handle Join(tx) @kv` (effect spec on a handler) | declared effect set on a handler | ✅ runs — the trailing `@kv` no longer orphans the body; the whole backend **minus** the `@channel_handler` now emits to wasm |
| `@channel_handler pub fn join(session: Channel<i64, Tap>)` | rpc channel entry point | ✅ **emits** — the attribute routes `join` through the full void-body builder, exported by name; the `Channel<Tx, Rx>` session is an i64 handle. **The whole `backend.q` now emits to wasm as written** (imports: `env.kv_increment`, `env.channel_recv`, `env.channel_send`) |
| `session.send(x)` | outbound half of the session | ✅ runs — lowers to the `env.channel_send(handle, x)` host call (verified: one send per inbound message) |
| `for _tap in session { … }` | inbound half of the session | ✅ runs — lowers to `while chan_recv(session) != 0 { … }` (`env.channel_recv`: 1 = message, 0 = closed); the v0 Rx payload is empty (`Tap`) so the binder is ignored |
| `channel<i64>(policy: Unbounded)`, `tx.send`, `rx.recv` | in-process channel | ✅ runs (passes `check` + emits) |
| `for n in rx` | for-in over a channel | ✅ runs (drains the buffer in order) |
| `move tx` | move semantics | ✅ runs (v0 identity) |
| `spawn { for n in rx { session.send(n) } }` (the outbound **pump**) | live re-broadcast | 🟡 emits, but **eager** v0 (drains `rx` once); live interleaving with the tap loop is the runtime ABI's job (the DO drives the pump + recv concurrently) |

### What landed recently (q64-lang/q64)

Codegen slices, each tested end-to-end (`q64 emit` + the wasmtime host / a wasm
instantiation test):

1. **`env.kv.increment`** → an `env.kv_increment` host import (`wasi:keyvalue`),
   marks the fn `@kv`. Returns a boxed **`Result<i64,i64>`**, so the twin's
   `match … { Ok(n) -> n, Err(_) -> 0 }` shape compiles and runs.
2. **`Vec.new()`** — the empty growable, so a subscriber set is built at runtime
   (`var subs = Vec.new(); subs.push(x); for tx in subs { … }`).
3. **fire-and-forget `spawn { … }`** — the body runs eagerly for effect, in
   `main`, a `for` body, or an `if` body.
4. (`env.kv` + `Vec.new` together cover the backend's persistence + fan-out
   *data flow*; the actor/channel/rpc *control flow* is the remaining work.)
5. **module-level actor singleton** (`let twin = Counter.spawn()`, HOST SEAM 1)
   — the instance's state record is allocated once by a synthesized wasm `start`
   function and its self-pointer kept in a module global, so the shared state is
   module-lifetime and every `twin.tell/ask` in any function reaches the one
   instance. Verified end to end (`ping()` → 1, 2, 3).
6. **effect spec on a handler** (`handle Bump @kv { … }`) — a trailing
   `@marker (+ @marker)*` after the handler signature is parsed like a `fn`'s,
   so it no longer orphans the body. With 5 + 6, the actor + kv-store + fan-out
   half of the twin (everything but the `@channel_handler` entry point) emits.
7. **`@channel_handler` + the host-backed remote channel session** — a
   `pub fn` carrying `@channel_handler` is a channel entry point taking one
   `Channel<Tx, Rx>` session (an i64 handle). `for _ in session` lowers to
   `while chan_recv(session) != 0 { … }` (the `env.channel_recv` import: 1 =
   inbound message, 0 = closed) and `session.send(x)` to the `env.channel_send`
   host call — a v0 host-import seam parallel to `env.kv` (the spec's eventual
   lowering is paired WASIp3 streams). The handler builds through the full
   void-callee machinery, so `let (tx, rx) = channel(…)`, `spawn`, `twin.tell`,
   and the session loop all compile. **With 1–7 the entire `backend.q` emits to
   wasm as written**; instantiated with a stub host, a channel handler sends
   once per inbound message and stops on close. The one remaining behavioural
   gap is the **eager** outbound pump (see the table) — correct live
   re-broadcast is the runtime ABI (the DO interleaves pump + recv).
8. **The importer side — `connect` + value-bearing recv + `presses()`** — the
   `frontend.q` half now compiles too. `connect<counter.join>()` opens the dual
   end (the `<…>` turbofish parses; lowers to the nullary `env.channel_connect`),
   `for n in twin` binds each inbound i64 via `env.channel_take` (a
   value-bearing Rx, vs the backend's empty `Tap`), `twin.send(Tap)` is a unit
   `env.channel_send`, and `for _press in presses()` opens a host event stream
   (`env.presses`, HOST SEAM 2). The cross-qube `import counter.{join}` resolves
   against the backend (the `counter` qube) the normal way — `--module
   counter=<backend>` (what the build driver wires from `qube.json5`'s
   `rpc.import`). **The entire example — `backend.q` AND `frontend.q` — now
   emits to wasm as written**; instantiated with a stub host the frontend
   redraws on each broadcast and sends a tap per press (a full
   round-trip is in `q64-test/tests/build.test.ts`).

## The cross-qube wire — the actual mechanism

`connect<iface.fn>()` **is** a builtin now (it opens the channel session — the
spec's importer form, `spec/rpc.md` §"Remote channels"); it lowers to the
`env.channel_connect` host import. The `import counter.{join}` resolves against
the providing qube the standard way (`--module counter=<backend>` locally; the
`rpc.import` binding on deploy) — a bare `q64 emit` with no binding is still an
honest `UnknownModule`, the same boundary `examples/rpc-client` lives at. q64
qubes talk over the **component model + wRPC**, configured in `qube.json5`:

**Export side (the backend, `type: "library"`):**

```jsonc
// backend/qube.json5  (already correct)
component: { emit: true, world: "counter-backend" },
rpc:       { export: true },
```

A qube's `pub fn` surface **is** its served world. `q64 show world --qube
backend.q` already synthesizes the WIT for a value-typed `pub fn` — e.g. a
plain `pub fn` over `i64`/`str`/`Result<value, value>` lowers to the canonical
ABI and travels on the wire unchanged (`spec/rpc.md` §"Wire encoding"). The
constraint that matters: **RPC signatures use value types only** — no `ref T`,
no resources, no closures (`RPC010`). The counter's payloads (`i64`, `Tap`,
streams of `i64`) are all value types, so they qualify.

**Import side (the frontend, `type: "application"`):**

```jsonc
// frontend/qube.json5  (already correct)
rpc: { import: { counter: "wrpc://counter-backend" } },
```

```q64
import counter.{join}        // the remote's re-exported surface
fn main @wire { … }          // any call into it carries @wire
```

The imported world is the *same artifact* the backend built with
`component.emit: true` — no IDL authored on either side. Every call across it
picks up the **`@wire`** effect (propagates up to `main`, implies `@io`,
forbidden under `@realtime`). On qubepods the endpoint doubles as a wRPC server:
a `--component` qube deployed with `rpc.export: true` is reachable as both
`wasi:http` and wRPC at the same address (`spec/rpc.md` §"Addressing").

**Two seams are runtime, not compiler** (the `HOST SEAM` markers in
`backend.q`, and `fan-out.md`):

- the **transport** byte-mover lives in `runtime/<host>/` (WebTransport in the
  browser, QUIC/TCP native) — the same place WASI lowering lives;
- the **per-project singleton twin** (`let twin = Counter.spawn()`) is a host
  concern (a qubepods Durable Object, one instance per project); the planned
  first-class spelling is `@state(scope)`.

## Path forward — ordered by leverage

To compile `backend.q` *as written*, in dependency order:

1. ~~**Keyed `env.kv.increment(key, delta)`**~~ — ✅ **done.** The import takes
   `(key_ptr, key_len, delta)`; the host store is a `map<str,i64>`. The twin's
   `bump()`/`read()` on `"count"` compile and run (verified: `1,2,2,3`).
2. ~~**Message-style actors**~~ — ✅ **done** for the scalar surface. The blocker
   turned out to be the parser: `tell`/`spawn` are keywords (`KW_TELL`/`KW_SPAWN`)
   the path parser didn't admit as segments, so `c.tell(Msg)` / `Counter.spawn()`
   never became calls (and `c.tell`'s text dropped the `tell` token → `"c."`).
   Fixed by admitting both as path segments (in `isPathStart` + `isPathToken`,
   like `Vec.from`'s `KW_FROM`), then dispatching in `build_hir`: `c.tell(Bump)`
   → the `Bump` handler, `c.tell(Add(5))` → `Add` with the payload, `c.ask(Get)`
   → the value handler, `Counter.spawn()` → the default-state record. Runs
   end-to-end (a counter actor: tells, payload, ask, spawn). The twin's payloads
   are non-scalar (`Join(tx: Sender<…>)`, `move tx`) — those ride #2b.
   ~~`CONC050`~~ ✅ also fixed: `channel<i64>(policy: Unbounded)` (the policy is an
   argument, not a type param), so `backend.q` now passes `q64 check` cleanly.

2b. ~~**Senders as first-class values**~~ — ✅ **done, standalone.** A
   `Sender`/`Receiver` used as a value now yields its channel-buffer pointer
   (i64), so it pushes into a Vec, is `move`d, and `.send` works on a sender
   *value* (a Vec element / moved sender — narrowed back to the buffer). The
   broadcast loop `for s in subs { s.send(n) }` and `for n in rx` both run;
   multi-subscriber fan-out verified (push 3 senders, broadcast 42, all 3 recv).
   `move`/`ref` are v0 identity. (One narrow channel limit remains: `recv()` in
   *expression* position with multiple channels — the twin uses `let`/`for`
   forms, so it's unaffected.)
2c. ~~**Actor state as a collection + Sender-typed handler params**~~ — ✅ **done.**
   The twin's exact actor now compiles and runs end-to-end. All sub-pieces:
   - qualified `state.<field>` access (reads + writes) ✅;
   - the struct builder accepts a `Vec<T>` state field as an i64 cell (the vec
     header pointer) ✅;
   - the `= Vec.new()` default builds a `vec_new` into the cell ✅;
   - `state.subs.push(x)` narrows the cell to the buffer pointer and pushes ✅;
   - for-loops now work in handler bodies, and `for s in state.subs` iterates the
     state Vec ✅;
   - a `Sender`/`Receiver`/`Vec`-typed handler param is accepted as i64 ✅.
   Verified: `Twin { state subs: Vec<Sender>; handle Join(tx) { subs.push(tx) };
   handle Bump { for s in subs { s.send(99) } } }` with two subscribers — both
   receive 99.
3. **`@channel_handler` + `Channel<Tx, Rx>`** — the rpc channel entry point.
   Per `rpc.md`, `Channel<Tx, Rx>` is *sugar over a pair of WASIp3 streams*; the
   v0 realization is a **host-import seam** (parallel to `env.kv`), the same
   shape the qubepods DO host implements. Now ✅:
   - **annotation + void general export** ✅ — `@channel_handler` routes `join`
     through the full void-body builder (not the restrictive screen path),
     exported by name; the body gets `let (tx,rx)=channel(…)`, `spawn`,
     `twin.tell`, and the session loop.
   - **`Channel<Tx, Rx>` param + session ops** ✅ — the session is an i64 handle;
     `for _tap in session` → `while chan_recv(session) != 0` (`env.channel_recv`),
     `session.send(x)` → `env.channel_send`. The importer dual works too:
     `connect<…>()` (`env.channel_connect`), value-bearing `for n in twin`
     (`env.channel_take`), `presses()` (`env.presses`).
   - **module-level actor singleton** ✅ — `let twin = Counter.spawn()` allocates
     once via the wasm `start`; the self-pointer lives in a module global.
   - **paired-stream component emission + wRPC serving** ⬜ — exporting as a real
     `stream<Tx>`/`stream<Rx>` component world over wRPC (vs the host-import
     seam) and the transport adapter remain component + **runtime** work.
   So the **whole twin language model compiles and runs**; what's left is the
   runtime/serving boundary (the DO host + the eager→live pump).
4. ~~**for-in over a live channel/stream** (`for n in rx`)~~ — ✅ done.

A **compiles-today** backend (keyless `env.kv`, method-style actor, i64 Vec,
fire-and-forget `spawn`) already exercises the persistence + fan-out data flow
end-to-end on the host; it's the honest floor under the target `backend.q`
above. Items 1–4 close the distance to the file as written.
