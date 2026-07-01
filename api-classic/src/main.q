//! api-classic — a classic request/response HTTP API, the whole thing in one
//! @http_handler.
//!
//! This is the "backend with real storage" example (example-roadmap #4): it uses
//! all three project stores — key-value, SQLite, and object storage — through the
//! ambient capability faces on `env`, and serves them over HTTP. It's the
//! request/response sibling of `twin-counter` (which serves a live wRPC channel);
//! same manifest-driven model, different entry point.
//!
//! The capability boundary is the point. The handler calls `env.kv`, `env.db`,
//! and `env.blob` — but it never names a namespace, a database, or a bucket.
//! qubepods opens each store and pins it to this qube's identity (org/project/app)
//! at boot (env.md §`env.kv`/`env.db`/`env.blob`), and meters the calls. So the
//! data is the project's, can't reach another tenant, and is billed through the
//! platform — not raw Cloudflare a customer could point anywhere.
//!
//! HTTP entry point: `@http_handler` (env.md §"HTTP service entry point"). With
//! `component.worlds: ["wasi:http/proxy"]` in qube.json5, this function is
//! exported as `wasi:http/handler`. `Request`/`Response` are the wasi:http
//! Preview-3 shapes (the same types `env.net` returns on the client side).

// The shared "stats" this API keeps — the same three keys/tables/objects a later
// `api-twin` app in the SAME project would read, so both share one set of stats.
let VISITS_KEY = "visits"        // env.kv  — a monotonic counter
let EVENTS_TABLE = "events"      // env.db  — one row per recorded event
let ASSET_PREFIX = "assets/"     // env.blob — user-uploaded objects

@http_handler
pub fn handle(req: Request) -> Response @network + @kv + @db + @blob {
    match (req.method, path_head(req.path)) {
        // --- key-value (env.kv → KeyValue face, @kv) --------------------------
        // A shared visit counter. `increment` is atomic
        // (wasi:keyvalue/atomics.increment), so concurrent hits never lose one.
        ("POST", "visit") ->
            match env.kv.increment(VISITS_KEY, 1) {
                Ok(n)  -> Response.ok(itoa(n))
                Err(_) -> Response.status(500)
            }
        ("GET", "visits") ->
            match env.kv.get(VISITS_KEY) {
                Ok(Some(v)) -> Response.ok(v)
                Ok(None)    -> Response.ok("0")
                Err(_)      -> Response.status(500)
            }

        // --- SQLite (env.db → Database face, @db) -----------------------------
        // A tiny append-and-list log. First write creates the table; the dialect
        // is SQLite regardless of the project's storage tier (env.md §`env.db`).
        ("POST", "events") -> record_event(req.body_text())
        ("GET", "events") ->
            match env.db.query("SELECT id, body, at FROM " + EVENTS_TABLE + " ORDER BY id DESC LIMIT 50", []) {
                Ok(rows) -> Response.json(rows)
                Err(_)   -> Response.status(500)
            }

        // --- object storage (env.blob → BlobStore face, @blob) ----------------
        // PUT/GET an opaque object under this project's bucket. `asset_key`
        // extracts the trailing path segment; the bucket is never named.
        ("PUT", "assets") ->
            match env.blob.put(ASSET_PREFIX + asset_key(req.path), req.body_bytes()) {
                Ok(())  -> Response.status(201)
                Err(_)  -> Response.status(500)
            }
        ("GET", "assets") ->
            match env.blob.get(ASSET_PREFIX + asset_key(req.path)) {
                Ok(Some(b)) -> Response.ok(b)
                Ok(None)    -> Response.status(404)
                Err(_)      -> Response.status(500)
            }

        // A tiny index so `qube run` shows something at `/`.
        ("GET", "") -> Response.ok("api-classic: POST /visit, GET /visits, POST|GET /events, PUT|GET /assets/<key>")

        _ -> Response.status(404)
    }
}

// Create the events table on first write, then append one row. `execute` returns
// the affected-row count; `?` params are bound positionally (no string-building
// of values — the SQL injection boundary).
fn record_event(body: str) -> Response @db {
    match env.db.execute("CREATE TABLE IF NOT EXISTS " + EVENTS_TABLE + " (id INTEGER PRIMARY KEY AUTOINCREMENT, body TEXT, at INTEGER DEFAULT (unixepoch()))", []) {
        Ok(_)  -> {}
        Err(_) -> return Response.status(500)
    }
    match env.db.execute("INSERT INTO " + EVENTS_TABLE + " (body) VALUES (?)", [Value.text(body)]) {
        Ok(_)  -> Response.status(201)
        Err(_) -> Response.status(500)
    }
}

// The first path segment ("/events" → "events", "/assets/logo.png" → "assets"),
// used to route. The path is already normalized by the wasi:http layer.
fn path_head(path: str) -> str {
    let trimmed = path.trim_start("/")
    match trimmed.find("/") {
        Some(i) -> trimmed.slice(0, i)
        None    -> trimmed
    }
}

// The trailing segment after "assets/" ("/assets/logo.png" → "logo.png").
fn asset_key(path: str) -> str {
    let trimmed = path.trim_start("/")
    match trimmed.find("/") {
        Some(i) -> trimmed.slice(i + 1, trimmed.len())
        None    -> ""
    }
}
