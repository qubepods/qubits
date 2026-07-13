# device — the code that runs on your hardware

Two files live here — today's scaffolding and the destination holding its
seat:

- **`thermo_agent.py`** — what the fleet actually runs today. **Requires
  `python3` on the device** (preinstalled on Raspberry Pi OS; not guaranteed
  on generic IoT hardware — that dependency is exactly what the wasm
  destination removes). Stdlib-only for the app plane;
  `pip install websocket-client` enables the node-plane trunk. See the
  [example README](../README.md) for the run commands.
- **`qube.json5` + `src/main.q`** — the device *qube*: a placeholder main
  that compiles to a valid wasm32 component today (`qube build --addr
  wasm32`), and becomes the sensor actor when the `env.sensors` face and the
  ARMv7 device host (wasmtime's Pulley interpreter) land.

**The design principle: enrollment is the last manual act.** Copying
`thermo_agent.py` onto the device by hand is temporary scaffolding, not the
product. Once a node is enrolled and its trunk is up, putting a workload on
it is the *platform's* job — the scheduler places this qube on the fleet the
same way `qube deploy` places the backend on the platform. The device may be
inside a machine on a factory floor or part of a car; there is no user
standing next to it with `scp`.

The qube reads the SoC temperature through the `env.sensors` face — the
**host** reads `/sys/class/thermal` (the sandboxed qube cannot and must
not) and hands the value through the capability. Measurements go up the
trunk; commands come down and are **handled** — set the sample interval,
blink the LED. The device is an actor, not a sensor pipe: imagine a robot
walking around, driven from the browser — same architecture, different
`env.*` face.

