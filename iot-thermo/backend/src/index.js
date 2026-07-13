// Thermo — the fleet side of the IoT example: collect temperature readings
// from a fleet of devices (Raspberry Pis reporting their SoC temperature) and
// serve a live gauge dashboard.
//
// This worker is the CLOUD half. The DEVICE half is device/thermo_agent.py,
// which reads the sensor and reports here over plain HTTPS — and, in parallel,
// streams the same numbers up the qubepods node plane (the /v1/socket trunk)
// so the fleet is visible as devices on the console Nodes page. See README.md
// for how the two paths relate and where this example is headed.
//
// Storage is the project's key-value store (env.KV, injected from the
// manifest's `imports.cache` — see the api-classic example):
//
//   device:<name>     — latest reading + a ring of recent samples (the gauge)
//   devicekey:<name>  — sha256 of the device's key (never the key itself)
//
// Device auth is claim-on-first-report: the first report for a name mints a
// `thermo_…` key, returns it exactly once, and stores only its hash — the
// same shape as the platform's own node enrollment (qnode_ tokens,
// hash-at-rest). Every later report for that name must present the key.

// Same shape as qubepods node names — one convention across both planes.
const DEVICE_NAME_RE = /^[a-z0-9][a-z0-9-]{0,62}$/;
const MAX_READINGS = 120; // ring of recent samples per device (~10 min at 5 s)

// Store: env.KV whenever the substrate injects it (the durable path). Some
// execution substrates don't inject the store bindings yet — there we fall
// back to isolate memory so the example still runs, and we SAY so: the fleet
// payload carries `persistent: false` and the dashboard shows it. Readings in
// the fallback reset when the isolate recycles; nothing pretends otherwise.
const memory = new Map();
const memStore = {
	async get(k) { return memory.has(k) ? memory.get(k) : null; },
	async put(k, v) { memory.set(k, String(v)); },
	async delete(k) { memory.delete(k); },
	async list({ prefix }) {
		return { keys: [...memory.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({ name })) };
	}
};
const store = (env) => env.KV ?? memStore;

export default {
	async fetch(request, env) {
		const url = new URL(request.url);
		try {
			if (url.pathname === '/' && request.method === 'GET') return html(PAGE);
			if (url.pathname === '/api/fleet' && request.method === 'GET') return json(await fleet(env));
			if (url.pathname === '/api/report' && request.method === 'POST') return report(request, env);
			const del = url.pathname.match(/^\/api\/devices\/([a-z0-9-]+)$/);
			if (del && request.method === 'DELETE') return retire(request, env, del[1]);
			return json({ error: 'not found', path: url.pathname }, 404);
		} catch (e) {
			return json({ error: String(e && e.message ? e.message : e) }, 500);
		}
	}
};

// POST /api/report — a device pushes one reading.
//   { device, tempC, hostname?, agentVersion?, node?, key? }
// First report for a name claims it (response carries `deviceKey` once);
// later reports must present that key.
async function report(request, env) {
	const body = await request.json().catch(() => null);
	if (!body || typeof body !== 'object') return json({ error: 'JSON body required' }, 400);

	const device = typeof body.device === 'string' ? body.device : '';
	if (!DEVICE_NAME_RE.test(device)) {
		return json({ error: 'device must be lowercase letters, digits and hyphens (max 63)' }, 400);
	}
	const tempC = Number(body.tempC);
	if (!Number.isFinite(tempC) || tempC < -60 || tempC > 200) {
		return json({ error: 'tempC must be a number in a plausible range (-60..200)' }, 400);
	}

	// Claim-on-first-report. The stored value is a hash: leaking the KV
	// contents never leaks a credential. Enforced only on the durable store —
	// an ephemeral ledger would re-mint on every isolate recycle (and 401 the
	// key it minted a request ago), so without env.KV identity is not policed.
	const kv = store(env);
	let mintedKey = null;
	if (env.KV) {
		const storedHash = await kv.get(keyKey(device));
		if (storedHash === null) {
			mintedKey = 'thermo_' + randomHex(20);
			await kv.put(keyKey(device), await sha256hex(mintedKey));
		} else if (storedHash !== (await sha256hex(String(body.key ?? '')))) {
			return json({ error: `device "${device}" is already claimed — report with its key` }, 401);
		}
	}

	const now = Date.now();
	const prev = JSON.parse((await kv.get(deviceKey(device))) ?? 'null');
	const readings = [...(prev?.readings ?? []), [now, round1(tempC)]].slice(-MAX_READINGS);
	await kv.put(
		deviceKey(device),
		JSON.stringify({
			device,
			tempC: round1(tempC),
			at: now,
			// Metadata is sticky: a report that omits a field keeps the last value.
			hostname: strOrNull(body.hostname) ?? prev?.hostname ?? null,
			agentVersion: strOrNull(body.agentVersion) ?? prev?.agentVersion ?? null,
			// Set when the agent is also enrolled on the node plane — lets the
			// dashboard say "this gauge is the device the console Nodes page shows".
			node: strOrNull(body.node) ?? prev?.node ?? null,
			readings
		})
	);

	return json(
		mintedKey
			? { ok: true, claimed: true, deviceKey: mintedKey, note: 'store this key — it is shown exactly once' }
			: { ok: true },
		mintedKey ? 201 : 200
	);
}

// GET /api/fleet — everything the dashboard renders. Keys never leave KV.
async function fleet(env) {
	const kv = store(env);
	const listed = await kv.list({ prefix: 'device:' });
	const devices = [];
	for (const k of listed.keys ?? []) {
		const state = JSON.parse((await kv.get(k.name)) ?? 'null');
		if (state) devices.push(state);
	}
	devices.sort((a, b) => a.device.localeCompare(b.device));
	return { at: Date.now(), devices, persistent: !!env.KV };
}

// DELETE /api/devices/:name — retire a device, authorized by its own key.
async function retire(request, env, device) {
	const auth = request.headers.get('authorization') ?? '';
	const key = auth.startsWith('Bearer ') ? auth.slice(7) : '';
	const kv = store(env);
	const storedHash = await kv.get(keyKey(device));
	if (storedHash === null) return json({ error: 'unknown device' }, 404);
	if (storedHash !== (await sha256hex(key))) return json({ error: 'device key required (Bearer thermo_…)' }, 401);
	await kv.delete(deviceKey(device));
	await kv.delete(keyKey(device));
	return json({ ok: true, retired: device });
}

// --- helpers -----------------------------------------------------------------
const deviceKey = (name) => `device:${name}`;
const keyKey = (name) => `devicekey:${name}`;
const strOrNull = (v) => (typeof v === 'string' && v.length > 0 ? v.slice(0, 120) : null);
const round1 = (n) => Math.round(n * 10) / 10;

function randomHex(bytes) {
	const buf = crypto.getRandomValues(new Uint8Array(bytes));
	return [...buf].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function sha256hex(input) {
	const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
	return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

const json = (obj, status = 200) =>
	new Response(JSON.stringify(obj, null, 2) + '\n', {
		status,
		headers: { 'content-type': 'application/json; charset=utf-8' }
	});

const html = (body) =>
	new Response(body, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });

// --- the dashboard ------------------------------------------------------------
// One self-contained page, no build step, no framework (the api-classic
// pattern). Polls /api/fleet and renders a gauge card per device: current
// temperature, a colour that tracks it, a sparkline of the recent ring, and a
// freshness pill — a device that stops reporting fades to stale, then offline,
// without the gauges of the others ever flickering.
const PAGE = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Thermo — qubepods</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; background: #0b0d10; color: #e6e8eb; font: 15px/1.5 ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, sans-serif; }
  main { max-width: 860px; margin: 0 auto; padding: 40px 20px 80px; }
  h1 { font-size: 22px; margin: 0 0 4px; }
  p.sub { color: #9aa4b2; margin: 0 0 24px; }
  code { background: #171a1f; padding: 1px 6px; border-radius: 5px; color: #b9c2cf; }
  .summary { display: flex; gap: 12px; flex-wrap: wrap; margin: 0 0 20px; }
  .stat { background: #12151a; border: 1px solid #1e232b; border-radius: 12px; padding: 12px 18px; min-width: 110px; }
  .stat .n { font-size: 24px; font-weight: 700; }
  .stat .l { color: #9aa4b2; font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
  .fleet { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 14px; }
  .card { background: #12151a; border: 1px solid #1e232b; border-radius: 14px; padding: 16px 18px; }
  .card.gone { opacity: .55; }
  .head { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
  .name { font-weight: 650; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .pill { font-size: 11px; font-weight: 600; padding: 2px 8px; border-radius: 999px; white-space: nowrap; }
  .live { background: #10371f; color: #4ade80; }
  .stale { background: #3a2f14; color: #fbbf24; }
  .off { background: #3a1417; color: #f87171; }
  .temp { font-size: 42px; font-weight: 750; letter-spacing: -.02em; margin: 6px 0 2px; font-variant-numeric: tabular-nums; }
  .temp small { font-size: 20px; font-weight: 600; color: #9aa4b2; }
  .meta { color: #9aa4b2; font-size: 12px; min-height: 18px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  svg.spark { display: block; width: 100%; height: 44px; margin-top: 10px; }
  .empty { background: #12151a; border: 1px dashed #2a2f38; border-radius: 14px; padding: 28px; color: #9aa4b2; text-align: center; }
  .empty code { display: inline-block; margin-top: 8px; }
  .note { display: none; background: #2a2410; border: 1px solid #4a3d14; color: #fbbf24; border-radius: 10px; padding: 8px 14px; font-size: 13px; margin: 0 0 16px; }
</style>
</head>
<body>
<main>
  <h1>Thermo</h1>
  <p class="sub">Live fleet thermometer — each gauge is a device reporting its SoC temperature. Readings land in the project's KV via <code>POST /api/report</code>; this page polls <code>/api/fleet</code>.</p>

  <div class="note" id="note">Ephemeral store: this substrate injects no KV binding, so readings live in isolate memory and reset when it recycles.</div>

  <div class="summary">
    <div class="stat"><div class="n" id="s-devices">–</div><div class="l">devices</div></div>
    <div class="stat"><div class="n" id="s-live">–</div><div class="l">reporting</div></div>
    <div class="stat"><div class="n" id="s-max">–</div><div class="l">hottest</div></div>
  </div>

  <div class="fleet" id="fleet"></div>
</main>
<script>
  const STALE_MS = 20e3, OFF_MS = 120e3;   // 4 missed 5 s reports = stale; 2 min = offline

  // Cool blue -> green -> amber -> red across the range a Pi SoC actually spans.
  function colorFor(t) {
    const stops = [[35,'#38bdf8'],[50,'#4ade80'],[65,'#fbbf24'],[80,'#f87171']];
    if (t <= stops[0][0]) return stops[0][1];
    for (let i = 1; i < stops.length; i++) if (t <= stops[i][0]) return stops[i][1];
    return stops[stops.length-1][1];
  }

  function spark(readings, color) {
    if (!readings || readings.length < 2) return '<svg class="spark"></svg>';
    const ts = readings.map(r => r[0]), vs = readings.map(r => r[1]);
    const t0 = Math.min(...ts), t1 = Math.max(...ts);
    const lo = Math.min(...vs) - 1, hi = Math.max(...vs) + 1;
    const X = t => 2 + 196 * (t - t0) / Math.max(1, t1 - t0);
    const Y = v => 40 - 36 * (v - lo) / Math.max(.5, hi - lo);
    const d = readings.map((r, i) => (i ? 'L' : 'M') + X(r[0]).toFixed(1) + ' ' + Y(r[1]).toFixed(1)).join(' ');
    return '<svg class="spark" viewBox="0 0 200 44" preserveAspectRatio="none">' +
      '<path d="' + d + '" fill="none" stroke="' + color + '" stroke-width="1.6" stroke-linejoin="round"/></svg>';
  }

  function card(dev, now) {
    const age = now - dev.at;
    const state = age < STALE_MS ? ['live','live'] : age < OFF_MS ? ['stale','stale'] : ['off','offline'];
    const color = colorFor(dev.tempC);
    const meta = [dev.hostname, dev.node ? 'node: ' + dev.node : null].filter(Boolean).join(' · ');
    return '<div class="card' + (state[0] === 'off' ? ' gone' : '') + '">' +
      '<div class="head"><span class="name">' + esc(dev.device) + '</span>' +
      '<span class="pill ' + state[0] + '">' + state[1] + '</span></div>' +
      '<div class="temp" style="color:' + color + '">' + dev.tempC.toFixed(1) + '<small> °C</small></div>' +
      '<div class="meta">' + esc(meta) + '</div>' +
      spark(dev.readings, color) + '</div>';
  }

  const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

  async function refresh() {
    try {
      const res = await fetch('/api/fleet').then(r => r.json());
      const now = res.at ?? Date.now();
      const devs = res.devices ?? [];
      document.getElementById('note').style.display = res.persistent === false ? 'block' : 'none';
      const live = devs.filter(d => now - d.at < STALE_MS);
      document.getElementById('s-devices').textContent = devs.length;
      document.getElementById('s-live').textContent = live.length;
      document.getElementById('s-max').textContent = devs.length
        ? Math.max(...devs.map(d => d.tempC)).toFixed(1) + ' °C' : '–';
      document.getElementById('fleet').innerHTML = devs.length
        ? devs.map(d => card(d, now)).join('')
        : '<div class="empty">No devices yet.<br/><code>python3 device/thermo_agent.py --report-url ' +
          location.origin + ' --simulate</code></div>';
    } catch (e) { /* keep the last good render; the next poll retries */ }
  }
  refresh();
  setInterval(refresh, 3000);
</script>
</body>
</html>`;
