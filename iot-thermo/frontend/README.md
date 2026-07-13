# frontend — the browser twin (remote controller)

Today the dashboard is an HTML page served inline by the [backend](../backend/)
worker, polling `/api/fleet`. This folder holds the twin's seat: `qube.json5`
+ `src/main.q` are a placeholder that already compiles to a valid wasm32
component (`qube build --addr wasm32`), so the member is real to the tooling
while the twin is written.

Where it's headed: a q64 qube compiled to **wasm32**, running in the browser,
holding one wRPC channel over a WebSocket to the backend — exactly the
[twin-counter](../../twin-counter/) frontend pattern, which runs in production
today. The backend *pushes* every change (no polling), and the frontend sends
commands back up the same channel: a browser-based remote controller for the
fleet — set a device's sample interval, blink its LED, or, in the robot
version of this architecture, drive it around.
