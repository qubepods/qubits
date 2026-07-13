# device — the code that runs on your hardware

Today this is `thermo_agent.py`, a plain Python script you copy to the device
(any Linux/macOS box; Raspberry Pi 2 or newer) and run — see the
[example README](../README.md) for the exact commands. Stdlib-only for the
app plane; `pip install websocket-client` enables the node-plane trunk.

Where it's headed: this folder becomes a q64 qube compiled to **wasm32**,
placed on your devices by the scheduler and run by the platform's device host
(wasmtime's Pulley interpreter — which is how a 32-bit ARMv7 board from 2015
runs the same wasm substrate as the cloud). It publishes measurements up the
trunk and **handles commands coming down** — the device is an actor, not a
sensor pipe. Imagine a robot walking around, driven from the browser: same
architecture, different `env.*` face.
