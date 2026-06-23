//! backend-counter — the qubepods backend starter.
//!
//! A single page with a button and a number. Every click bumps a counter
//! that lives in the project's *backend*, so everyone looking at the page
//! sees the same number climb — no matter which device, browser, or tab the
//! click came from.
//!
//! The whole app is one `wasi:http` handler. qubepods serves it as the
//! project's per-qube HTTPS endpoint. Because a backend-enabled project is
//! anchored by a single Durable Object, every request lands on the same
//! instance, and the count is kept in that DO's SQLite-backed store —
//! reached here through the `env.kv` capability (which lowers to
//! `wasi:keyvalue`). That host wiring — the qube's WASI import bound to the
//! project's Durable Object — is the "WASI connection" this example exists
//! to demonstrate.
//!
//! Routes:
//!   GET  /            -> the HTML page (button + live count)
//!   GET  /api/count   -> the current count as plain text
//!   POST /api/click   -> atomically add one, return the new count
//!
//! Build:  qube build --component
//! Deploy: qube pod deploy           (into a backend-enabled project)
//!
//! See ../README.md for the full walkthrough.

// One key in the project's key-value store. The whole demo is this counter.
const COUNTER_KEY: str = "clicks"

@http_handler
pub fn handle(req: Request) -> Response @kv {
    match (req.method(), req.path()) {
        ("GET",  "/")          -> Response.html(page())
        ("GET",  "/api/count") -> Response.ok("{bump(0)}")
        ("POST", "/api/click") -> Response.ok("{bump(1)}")
        _                      -> Response.not_found()
    }
}

// Add `delta` to the shared counter and return the new total.
//
// `increment` lowers to `wasi:keyvalue/atomics.increment`, so two visitors
// clicking at the same instant never lose an update — the host applies both
// bumps atomically. Reading is just a bump of 0. A key that was never set
// starts at 0, so the first ever view shows 0 and the first click shows 1.
fn bump(delta: i64) -> i64 @kv {
    match env.kv.increment(COUNTER_KEY, delta) {
        Ok(n)  -> n
        Err(_) -> 0
    }
}

// The page paints itself: the qube *is* the frontend too. The browser loads
// the current count, bumps it on click, and polls so clicks from other
// people show up within a second or two. Plain single-context HTML/JS — no
// build step, no framework. Served as a raw string so its braces and quotes
// pass through untouched.
fn page() -> str {
    r##"<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>qubepods · shared counter</title>
  <style>
    :root { color-scheme: dark; }
    * { box-sizing: border-box; }
    body {
      margin: 0; min-height: 100vh;
      display: grid; place-items: center;
      font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
      background: #0b0d12; color: #e7e9ee;
    }
    main { text-align: center; padding: 2rem; }
    h1 { font-size: 0.95rem; font-weight: 600; letter-spacing: 0.12em;
         text-transform: uppercase; color: #7b8194; margin: 0 0 1.25rem; }
    .count {
      font-variant-numeric: tabular-nums;
      font-size: clamp(4rem, 22vw, 11rem); font-weight: 800; line-height: 1;
      margin: 0 0 1.75rem; color: #fff;
    }
    button {
      appearance: none; border: 0; cursor: pointer;
      font: inherit; font-weight: 700; font-size: 1.05rem;
      padding: 0.85rem 2.4rem; border-radius: 999px; color: #0b0d12;
      background: linear-gradient(180deg, #8ab4ff, #5b8cff);
      transition: transform 0.08s ease, filter 0.15s ease;
    }
    button:hover { filter: brightness(1.08); }
    button:active { transform: translateY(1px) scale(0.985); }
    p.note { margin: 1.75rem 0 0; font-size: 0.85rem; color: #5d6273; max-width: 24rem; }
    footer { margin-top: 2.5rem; font-size: 0.8rem; color: #5d6273; }
    footer a { color: #8ab4ff; text-decoration: none; font-weight: 600; }
    footer a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <main>
    <h1>Everyone shares this count</h1>
    <div class="count" id="count" aria-live="polite">·</div>
    <button id="click" type="button">Click me</button>
    <p class="note">
      The number lives in this project's backend. Open this page on another
      device and watch it move when anyone clicks.
    </p>
    <footer>
      Deploy your own backend in seconds at
      <a href="https://qubepods.com">qubepods.com</a>
    </footer>
  </main>
  <script>
    const el = document.getElementById('count');
    const btn = document.getElementById('click');

    async function show(res) {
      if (res.ok) el.textContent = (await res.text()).trim();
    }
    const refresh = () => fetch('/api/count').then(show).catch(() => {});

    btn.addEventListener('click', () => {
      btn.disabled = true;
      fetch('/api/click', { method: 'POST' })
        .then(show)
        .catch(() => {})
        .finally(() => { btn.disabled = false; });
    });

    refresh();
    setInterval(refresh, 1500);
  </script>
</body>
</html>
"##
}
