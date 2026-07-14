// thermo frontend — the aggregated dashboard, a STATELESS qube in a dynamic
// worker. Two data paths, deliberately different:
//
//   • HISTORY — GET /api/history reads the PROJECT DATABASE (env.DB, the same
//     SQLite the device twins' env.db statements land in) and returns the
//     recent readings per device. The page seeds its sparklines from it.
//   • LIVE — the page holds ONE WebSocket to the DASHBOARD TWIN (the project's
//     backend twin) and updates are PUSHED: each frame is a packed
//     (device_id << 32 | temp_mc) i64. No polling.
//
// On a substrate that injects no env.DB (the fleet payload says which via
// `history: false`), the page still works — gauges fill from the twin's
// join snapshot and live frames; only the pre-connect history is missing.

const json = (obj, status = 200) =>
	new Response(JSON.stringify(obj, null, 2) + '\n', {
		status,
		headers: { 'content-type': 'application/json; charset=utf-8' }
	});

export default {
	async fetch(request, env) {
		const url = new URL(request.url);
		if (url.pathname === '/api/history') return history(env);
		if (url.pathname === '/' || url.pathname === '') {
			return new Response(PAGE, {
				headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' }
			});
		}
		return json({ error: 'not found' }, 404);
	}
};

// Recent history per device from the project database. The device twins own
// the schema (thermo_readings: device, temp_mc, at) — this is a pure reader.
async function history(env) {
	if (!env.DB) return json({ history: false, devices: [] });
	try {
		const rows = await env.DB.query(
			'SELECT device, temp_mc, at FROM thermo_readings ORDER BY at DESC LIMIT 600'
		);
		const byDevice = new Map();
		for (const r of rows ?? []) {
			const list = byDevice.get(r.device) ?? [];
			if (list.length < 60) list.push([r.at * 1000, r.temp_mc / 1000]);
			byDevice.set(r.device, list);
		}
		return json({
			history: true,
			devices: [...byDevice].map(([device, readings]) => ({ device, readings: readings.reverse() }))
		});
	} catch (e) {
		return json({ history: false, devices: [], error: String(e?.message ?? e) });
	}
}

// --- the dashboard --------------------------------------------------------
// One self-contained page, no build step, no framework. Gauges are keyed by
// the platform-assigned device id (identity never rides the wire).
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
  .fleet { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 14px; }
  .card { background: #12151a; border: 1px solid #1e232b; border-radius: 14px; padding: 16px 20px; }
  .meta { color: #9aa4b2; font-size: 12px; line-height: 1.7; font-variant-numeric: tabular-nums; }
  .meta b { color: #b9c2cf; font-weight: 550; }
  .card.gone { opacity: .55; }
  .head { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }
  .name { font-weight: 650; }
  .pill { font-size: 11px; font-weight: 600; padding: 2px 8px; border-radius: 999px; white-space: nowrap; }
  .live { background: #10371f; color: #4ade80; }
  .stale { background: #3a2f14; color: #fbbf24; }
  .off { background: #3a1417; color: #f87171; }
  .temp { font-size: 42px; font-weight: 750; letter-spacing: -.02em; margin: 6px 0 2px; font-variant-numeric: tabular-nums; }
  .temp small { font-size: 20px; font-weight: 600; color: #9aa4b2; }
  svg.spark { display: block; width: 100%; height: 44px; margin-top: 10px; }
  .empty { background: #12151a; border: 1px dashed #2a2f38; border-radius: 14px; padding: 28px; color: #9aa4b2; text-align: center; }
  .conn { font-size: 12px; color: #9aa4b2; margin: 0 0 16px; }
  .conn b.ok { color: #4ade80; } .conn b.bad { color: #f87171; }
</style>
</head>
<body>
<main>
  <h1>Thermo</h1>
  <p class="sub">A live view of your entire fleet. Measurements flow twin-to-twin, are stored by the backend twin in the project database, and appear instantly in the dashboard. A single dashboard twin combines live updates with the fleet's full history.</p>
  <p class="conn">twin: <b id="conn" class="bad">connecting…</b> · history: <b id="hist">–</b> · v0.2.4</p>
  <div class="summary">
    <div class="stat"><div class="n" id="s-devices">–</div><div class="l">devices</div></div>
    <div class="stat"><div class="n" id="s-live">–</div><div class="l">reporting</div></div>
    <div class="stat"><div class="n" id="s-max">–</div><div class="l">hottest</div></div>
  </div>
  <div class="fleet" id="fleet"></div>
</main>
<script>
  const STALE_MS = 20e3, OFF_MS = 120e3;
  const FLEET_APP = 'qubepods.examples.thermo';
  // deviceId -> { tempC, at, readings: [[ms, C], …], meta: {name, os, arch, hostname, ip} }
  const fleet = new Map();

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
  function render() {
    const now = Date.now();
    const devs = [...fleet.entries()].sort((a, b) => a[0] - b[0]);
    const live = devs.filter(([, d]) => now - d.at < STALE_MS);
    document.getElementById('s-devices').textContent = devs.length;
    document.getElementById('s-live').textContent = live.length;
    document.getElementById('s-max').textContent = devs.length
      ? Math.max(...devs.map(([, d]) => d.tempC)).toFixed(1) + ' °C' : '–';
    document.getElementById('fleet').innerHTML = devs.length
      ? devs.map(([id, d]) => {
          const age = now - d.at;
          const state = age < STALE_MS ? ['live','live'] : age < OFF_MS ? ['stale','stale'] : ['off','offline'];
          const color = colorFor(d.tempC);
          const m = d.meta ?? {};
          const os = [m.os, m.arch].filter(Boolean).join('/');
          return '<div class="card' + (state[0] === 'off' ? ' gone' : '') + '">' +
            '<div class="head"><span class="name">' + esc(m.name ?? 'device ' + id) + '</span>' +
            '<span class="pill ' + state[0] + '">' + state[1] + '</span></div>' +
            '<div class="temp" style="color:' + color + '">' + d.tempC.toFixed(1) + '<small> °C</small></div>' +
            '<div class="meta">' +
              (m.ip ? '<b>ip</b> ' + esc(m.ip) + '<br/>' : '') +
              (os ? '<b>os</b> ' + esc(os) + (m.hostname ? ' (' + esc(m.hostname) + ')' : '') + '<br/>' : '') +
              '<b>last reading</b> ' + (d.at ? new Date(d.at).toLocaleTimeString() : '–') +
            '</div>' +
            spark(d.readings, color) + '</div>';
        }).join('')
      : '<div class="empty">No devices yet — enroll one and it appears here the moment it reports.</div>';
  }
  const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
  function feed(id, tempC, at, isLive) {
    const d = fleet.get(id) ?? { tempC: 0, at: 0, readings: [], meta: null };
    d.tempC = tempC; if (at > d.at) d.at = at;
    d.readings.push([at, tempC]); if (d.readings.length > 60) d.readings.shift();
    fleet.set(id, d);
    if (isLive) render();
  }

  // The dashboard twin's socket URL: same gate, the fleet app's segment. Under the
  // stage gate the page lives at /q/<org>/<proj>/<app>/<env>/ — swap the app.
  // Elsewhere pass ?twin=wss://… explicitly.
  function twinUrl() {
    const u = new URL(location.href);
    const q = u.searchParams.get('twin'); if (q) return q;
    const parts = u.pathname.split('/');
    if (parts[1] === 'q' && parts.length >= 6) {
      parts[4] = FLEET_APP;
      u.pathname = parts.slice(0, 6).join('/') + '/';
    }
    u.protocol = u.protocol === 'http:' ? 'ws:' : 'wss:';
    u.search = ''; u.hash = '';
    return u.href;
  }
  function connect() {
    const ws = new WebSocket(twinUrl());
    ws.binaryType = 'arraybuffer';
    const conn = document.getElementById('conn');
    ws.onopen = () => { conn.textContent = 'live'; conn.className = 'ok'; };
    ws.onmessage = (ev) => {
      if (!(ev.data instanceof ArrayBuffer) || ev.data.byteLength < 8) return;
      const v = new DataView(ev.data).getBigInt64(0, true);
      const id = Number(v >> 32n);
      const mc = Number(BigInt.asIntN(32, v & 0xffffffffn));
      feed(id, mc / 1000, Date.now(), true);
    };
    ws.onclose = () => { conn.textContent = 'reconnecting…'; conn.className = 'bad'; setTimeout(connect, 2000); };
    ws.onerror = () => { try { ws.close(); } catch {} };
    setInterval(() => { try { ws.send('ping'); } catch {} }, 25e3);
  }

  // The fleet ROSTER — device identity (name, ip, os) + last-reading time,
  // served by the platform at /.well-known/fleet on the dashboard twin's route.
  // Same URL derivation as the socket, over https.
  function rosterUrl() {
    const u = new URL(twinUrl());
    u.protocol = u.protocol === 'ws:' ? 'http:' : 'https:';
    u.pathname = u.pathname.replace(/\\/?$/, '/') + '.well-known/fleet';
    return u.href;
  }
  async function refreshRoster() {
    try {
      const r = await fetch(rosterUrl()).then(r => r.json());
      for (const dev of r.devices ?? []) {
        const d = fleet.get(dev.id) ?? { tempC: dev.value / 1000, at: 0, readings: [], meta: null };
        d.meta = dev;
        if (dev.at && dev.at > d.at) { d.at = dev.at; d.tempC = dev.value / 1000; }
        fleet.set(dev.id, d);
      }
      render();
    } catch { /* roster is enrichment — the gauges live without it */ }
  }
  refreshRoster();
  setInterval(refreshRoster, 30e3);

  // Seed the sparklines from the project database, then go live.
  fetch(new URL('api/history', document.baseURI)).then(r => r.json()).then(h => {
    document.getElementById('hist').textContent = h.history ? 'project db' : 'live-only';
    for (const d of h.devices ?? []) for (const [ms, c] of d.readings) feed(d.device, c, ms, false);
    render();
  }).catch(() => { document.getElementById('hist').textContent = 'live-only'; render(); });
  connect();
  setInterval(render, 5000); // freshness pills tick even without frames
</script>
</body>
</html>`;
