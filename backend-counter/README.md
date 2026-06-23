# backend-counter

The **backend starter** for qubepods: one page, one button, one number —
shared by everyone.

Every click bumps a counter that lives in the project's backend, so the
number is the same for every visitor. Open the page on your phone and your
laptop at once: click on one, watch it move on the other.

It's about 100 lines of [q64](https://q64.dev) in
[`src/main.q`](./src/main.q) — a single `wasi:http` handler that serves its
own page *and* keeps the count. No framework, no build step, no separate
backend service to wire up.

```
GET  /            → the HTML page (button + live count)
GET  /api/count   → the current count, as plain text
POST /api/click   → add one atomically, return the new count
```

---

## What this teaches

1. **Turning on a backend for a project** — the one switch that gives a
   project persistent, shared state.
2. **A qube that paints its own UI and keeps its own state** — frontend and
   backend are the same artifact, with the count reached through one
   capability (`env.kv`) and nothing else.

---

## 1. Create a project with the backend enabled

In the qubepods app, create a new project. On the create form there's a
**Backend** switch:

> **Backend** — provision a database, storage & key-value plus a live
> frontend↔backend connection.

Turn it **on**. This is chosen once at creation and can't be flipped later —
a project either has a backend twin or it doesn't, because turning one on
later would be a data migration, not a toggle.

A backend-enabled project is anchored by a single **backend instance**. That's
the whole trick behind "everyone shares this count": there is exactly one
backend per project, it has its own durable store, and every request to the
project's endpoint lands on it.

## 2. Run it — in the browser (no desktop needed)

You don't need a desktop, a local toolchain, or even a laptop. qubepods is
browser-first: a mobile or iPad is enough. The IDE — **Qubonaut** — runs at
`app.qubepods.com` as an installable PWA, and you're **already signed in**
there, so there's no login step and no token to save.

1. Open your backend-enabled project from step 1 and tap **Edit** to open it
   in **Qubonaut**.
2. In Qubonaut's terminal, clone this example into your workspace:

   ```sh
   git clone https://github.com/qubepods/qubepods-examples.git
   cd qubepods-examples/backend-counter
   ```

   Qubonaut has a built-in terminal with `git` (it talks to GitHub over the
   API, so it works on iPad too — no desktop git needed).
3. Run it:

   ```sh
   qube run
   ```

   `qube run` compiles the qube to WebAssembly on-device — the q64 compiler is
   itself wasm, so this works on iPad Safari. You're already signed in, so
   there's no separate login.

Your project already has its address on **`*.qubepod.app`**, shown on the
project page.

### Prefer a desktop terminal?

Same thing from a laptop — `qube run` is all you need:

```sh
git clone https://github.com/qubepods/qubepods-examples.git
cd qubepods-examples/backend-counter
qube run
```

## 3. How the shared count works

The handler is the entire app:

```q64
@http_handler
pub fn handle(req: Request) -> Response @kv {
    match (req.method(), req.path()) {
        ("GET",  "/")          -> Response.html(page())
        ("GET",  "/api/count") -> Response.ok("{bump(0)}")
        ("POST", "/api/click") -> Response.ok("{bump(1)}")
        _                      -> Response.not_found()
    }
}

fn bump(delta: i64) -> i64 @kv {
    match env.kv.increment(COUNTER_KEY, delta) {
        Ok(n)  -> n
        Err(_) -> 0
    }
}
```

- The count is a single key in the project's key-value store, reached through
  the `env.kv` capability.
- `env.kv.increment(key, delta)` is **atomic**. Two people clicking at the
  same moment both get counted — the host applies both bumps without losing
  one. Reading the current value is just a bump of `0`.
- The page (served by `GET /`) is plain HTML + a few lines of JavaScript: on
  load it fetches `/api/count`, the button `POST`s to `/api/click`, and it
  polls every ~1.5s so clicks from *other* people show up on your screen too.

Because there's one backend per project and one count inside it, every browser
pointed at the endpoint is reading and writing the same number.

---

## Files

| File | What it is |
|------|------------|
| [`src/main.q`](./src/main.q) | The whole app — handler, counter, and page. |
| [`qube.json5`](./qube.json5) | Manifest: application type, `wasi:http/proxy` component, `@kv` capability. |
