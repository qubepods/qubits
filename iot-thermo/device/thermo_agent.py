#!/usr/bin/env python3
"""thermo_agent — the device half of the thermo example.

Runs on each device in the fleet (a Raspberry Pi, or any Linux/macOS box) and
does two independent things with the same thermometer reading:

  1. APP PLANE (always): POST the reading to your deployed thermo Qube
     (`--report-url https://<project>.qubepod.app`) so the dashboard gauges
     move. The first report for a device name claims it and returns a
     `thermo_…` key exactly once; the agent stores it in its state file and
     signs every later report with it.

  2. NODE PLANE (optional): speak qubepods' device protocol, so this box also
     shows up as a *device node* on the console Nodes page — enrolled, online,
     geo-located, with its temperature in the platform telemetry. Register a
     node (console -> project -> Nodes, role "device"), then pass the one-time
     `--enroll-token qp_enroll_…`. The agent exchanges it for a private
     `qnode_` token and from then on holds the node TRUNK: one outbound
     WebSocket to /v1/socket carrying JSON control frames on channel 0 —
     `hello` and periodic `telemetry` up, `config` down. If the socket can't
     be established (or `websocket-client` isn't installed), it falls back to
     the 5-minute heartbeat poll — the same fallback the platform itself
     defines. No inbound port is ever opened on the device.

Dependencies: none for the app plane (stdlib only). The node-plane trunk uses
`websocket-client` (`pip install websocket-client`); without it the agent
still enrolls and heartbeats.

Examples:

  # laptop demo, no hardware, no node plane — two fake devices:
  python3 thermo_agent.py --report-url https://thermo.qubepod.app --device demo-1 --simulate
  python3 thermo_agent.py --report-url https://thermo.qubepod.app --device demo-2 --simulate

  # on a Pi, first run (claims the dashboard name AND enrolls the node):
  python3 thermo_agent.py --report-url https://thermo.qubepod.app \
      --device pi-milano-1 --enroll-token qp_enroll_…

  # every later run (identity + keys live in the state file):
  python3 thermo_agent.py --report-url https://thermo.qubepod.app --device pi-milano-1
"""

import argparse
import glob
import hashlib
import json
import math
import os
import platform
import random
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

AGENT_VERSION = "thermo-agent/0.1.0"
DEFAULT_API = "https://api.qubepods.com"
DEVICE_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")

# The trunk is optional equipment; everything else is stdlib.
try:
    import websocket  # type: ignore  # pip install websocket-client
except ImportError:
    websocket = None


# --- tiny HTTP JSON client (stdlib) ------------------------------------------

def http_json(method, url, body=None, bearer=None, timeout=15):
    """One JSON round-trip. Returns (status, parsed-body-or-None)."""
    # Identify honestly: default library UAs trip edge bot filters (CF 1010).
    headers = {"content-type": "application/json", "user-agent": AGENT_VERSION}
    if bearer:
        headers["authorization"] = f"Bearer {bearer}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            return res.status, json.loads(res.read().decode() or "null")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode() or "null")
        except (ValueError, OSError):
            return e.code, None


# --- state file ----------------------------------------------------------------
# One small JSON file per device holds everything minted for it: the app-plane
# deviceKey and the node-plane identity (nodeId + qnode_ token). 0600 — these
# are credentials.

def state_path(args):
    if args.state:
        return args.state
    base = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    return os.path.join(base, "thermo-agent", f"{args.device}.json")


def load_state(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(path, state):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(state, f, indent=2)


# --- the thermometer -----------------------------------------------------------

def read_temp_c(sim_phase=None):
    """SoC temperature in °C. Simulated when sim_phase is set."""
    if sim_phase is not None:
        t = time.time()
        # A believable Pi: ~45 °C, a slow thermal wave, sensor noise, and the
        # occasional load spike so the dashboard has something to show.
        base = 45 + 8 * math.sin(2 * math.pi * (t / 600) + sim_phase)
        spike = 12 * max(0, math.sin(2 * math.pi * (t / 97) + sim_phase * 3)) ** 8
        return base + spike + random.uniform(-0.4, 0.4)
    for zone in sorted(glob.glob("/sys/class/thermal/thermal_zone*/temp")):
        try:
            with open(zone) as f:
                return int(f.read().strip()) / 1000.0
        except (OSError, ValueError):
            continue
    try:  # Raspberry Pi fallback: vcgencmd measure_temp -> "temp=47.2'C"
        out = subprocess.run(["vcgencmd", "measure_temp"], capture_output=True, text=True, timeout=5).stdout
        m = re.search(r"temp=([\d.]+)", out)
        if m:
            return float(m.group(1))
    except (OSError, subprocess.SubprocessError):
        pass
    return None


def read_mem_mb():
    """(used, total) in MB from /proc/meminfo, or (None, None)."""
    try:
        info = {}
        with open("/proc/meminfo") as f:
            for line in f:
                parts = line.split()
                info[parts[0].rstrip(":")] = int(parts[1])  # kB
        total = info["MemTotal"] // 1024
        used = (info["MemTotal"] - info.get("MemAvailable", info["MemTotal"])) // 1024
        return used, total
    except (OSError, KeyError, ValueError, IndexError):
        return None, None


# --- node plane: enroll, heartbeat, trunk ---------------------------------------

def platform_ids():
    """(os, arch) in the enum the enroll API expects, or (None, None)."""
    os_id = {"linux": "linux", "darwin": "macos", "win32": "windows"}.get(sys.platform)
    arch_id = {"x86_64": "x86_64", "amd64": "x86_64", "aarch64": "aarch64", "arm64": "aarch64"}.get(
        platform.machine().lower()
    )
    return os_id, arch_id


def enroll(api, token):
    """Exchange the one-time qp_enroll_ token for this node's identity."""
    os_id, arch_id = platform_ids()
    if not os_id or not arch_id:
        sys.exit(f"unsupported platform for enrollment: {sys.platform}/{platform.machine()} "
                 "(devices need a 64-bit OS — on a Pi use 64-bit Raspberry Pi OS)")
    status, body = http_json("POST", f"{api}/v1/enroll", {
        "token": token,
        "host": {"os": os_id, "arch": arch_id, "hostname": socket.gethostname(), "hostVersion": AGENT_VERSION},
    })
    if status != 201 or not body or not body.get("ok"):
        sys.exit(f"enroll failed (HTTP {status}): {body and body.get('error')}"
                 "\nenrollment tokens are single-use and expire in 30 min — re-mint one on the node's page")
    print(f"[node] enrolled as {body['name']} (node {body['nodeId']})")
    return {
        "nodeId": body["nodeId"],
        "nodeName": body["name"],
        "nodeToken": body["nodeToken"],
        "heartbeatSeconds": body.get("config", {}).get("heartbeatSeconds", 300),
    }


def heartbeat(api, state):
    """The polling backup path. Returns False if the node must stand down."""
    status, body = http_json("POST", f"{api}/v1/heartbeat", {"agentVersion": AGENT_VERSION},
                             bearer=state["nodeToken"])
    if status == 403:
        print(f"[node] platform says this node is {body and body.get('status')} — standing down the node plane")
        return False
    if status == 200 and body:
        state["heartbeatSeconds"] = body.get("config", {}).get("heartbeatSeconds", state.get("heartbeatSeconds", 300))
    return True


class Trunk:
    """The node's single outbound WebSocket to /v1/socket (channel-0 JSON frames)."""

    def __init__(self, api, node_token):
        self.url = re.sub(r"^http", "ws", api, count=1) + "/v1/socket"
        self.token = node_token
        self.ws = None

    @staticmethod
    def proxy_kwargs():
        """Honor the same https_proxy env urllib honors — a device behind an
        egress proxy still gets its trunk (CONNECT tunnel, TLS end to end)."""
        proxy = os.environ.get("https_proxy") or os.environ.get("HTTPS_PROXY")
        if not proxy:
            return {}
        from urllib.parse import urlparse
        p = urlparse(proxy)
        return {"http_proxy_host": p.hostname, "http_proxy_port": p.port or 8080, "proxy_type": "http"}

    def connect(self):
        self.ws = websocket.create_connection(
            self.url,
            header=[f"Authorization: Bearer {self.token}", f"User-Agent: {AGENT_VERSION}"],
            timeout=10,
            **self.proxy_kwargs()
        )
        self.ws.settimeout(0.1)  # recv() below is a poll, not a wait
        self.send({"ch": 0, "t": "hello", "agentVersion": AGENT_VERSION})
        print(f"[node] trunk up ({self.url})")

    def send(self, frame):
        self.ws.send(json.dumps(frame))

    def telemetry(self, temp_c):
        metrics = {}
        if temp_c is not None:
            metrics["tempC"] = round(temp_c, 1)
        used, total = read_mem_mb()
        if total:
            metrics["memUsedMb"], metrics["memTotalMb"] = used, total
        if metrics:
            self.send({"ch": 0, "t": "telemetry", "metrics": metrics})

    def poll(self):
        """Drain anything the hub pushed down (v0: the config frame)."""
        while True:
            try:
                raw = self.ws.recv()
            except websocket.WebSocketTimeoutException:
                return
            if isinstance(raw, bytes):
                continue  # binary = future data channels; ignore on v0
            try:
                frame = json.loads(raw)
            except ValueError:
                continue
            if frame.get("ch") == 0 and frame.get("t") == "config":
                print(f"[node] config: heartbeat every {frame.get('heartbeatSeconds')} s (poll is the backup)")

    def close(self):
        if self.ws:
            try:
                self.ws.close()
            except (OSError, websocket.WebSocketException):
                pass
            self.ws = None


# --- app plane: report to the thermo Qube ---------------------------------------

def report(args, state, temp_c):
    body = {
        "device": args.device,
        "tempC": round(temp_c, 1),
        "hostname": socket.gethostname(),
        "agentVersion": AGENT_VERSION,
    }
    if state.get("nodeName"):
        body["node"] = state["nodeName"]
    if state.get("deviceKey"):
        body["key"] = state["deviceKey"]
    status, res = http_json("POST", f"{args.report_url}/api/report", body)
    if status == 201 and res and res.get("deviceKey"):
        state["deviceKey"] = res["deviceKey"]
        print(f"[app] claimed device name \"{args.device}\" — key stored in the state file")
        return True
    if status == 200:
        return True
    if status == 401:
        sys.exit(f"[app] \"{args.device}\" is claimed by another key — pick a new --device name, "
                 "point --state at the original file, or retire the old device (see README)")
    print(f"[app] report failed (HTTP {status}): {res and res.get('error')}")
    return False


# --- main -----------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser(description="thermo device agent — see the module docstring")
    p.add_argument("--report-url", required=True, help="your deployed thermo Qube, e.g. https://thermo.qubepod.app")
    p.add_argument("--device", default=None, help="device name on the dashboard (default: this hostname)")
    p.add_argument("--api-url", default=DEFAULT_API, help=f"qubepods node-plane origin (default {DEFAULT_API})")
    p.add_argument("--enroll-token", default=None, help="one-time qp_enroll_… token from the console node wizard")
    p.add_argument("--state", default=None, help="state file (default ~/.config/thermo-agent/<device>.json)")
    p.add_argument("--interval", type=float, default=5.0, help="seconds between dashboard reports (default 5)")
    p.add_argument("--telemetry-interval", type=float, default=60.0,
                   help="seconds between node-plane telemetry frames (default 60)")
    p.add_argument("--simulate", action="store_true", help="fake the sensor (demo without hardware)")
    p.add_argument("--once", action="store_true", help="read + report once, then exit")
    args = p.parse_args()

    args.report_url = args.report_url.rstrip("/")
    args.api_url = args.api_url.rstrip("/")
    if not args.device:
        args.device = re.sub(r"[^a-z0-9-]", "-", socket.gethostname().lower()).strip("-") or "device"
    if not DEVICE_NAME_RE.match(args.device):
        sys.exit("--device must be lowercase letters, digits and hyphens (max 63)")

    sim_phase = (int(hashlib.sha256(args.device.encode()).hexdigest(), 16) % 628) / 100 if args.simulate else None
    if read_temp_c(sim_phase) is None:
        sys.exit("no thermal sensor found (/sys/class/thermal, vcgencmd) — pass --simulate to demo without one")

    path = state_path(args)
    state = load_state(path)

    # Node plane is armed by enrolling once (or by an identity already on disk).
    if args.enroll_token:
        if state.get("nodeToken"):
            print("[node] already enrolled — ignoring --enroll-token (delete the state file to start over)")
        else:
            state.update(enroll(args.api_url, args.enroll_token))
            save_state(path, state)
    node_plane = bool(state.get("nodeToken"))
    if node_plane and websocket is None:
        print("[node] websocket-client not installed — trunk unavailable, using the heartbeat poll "
              "(pip install websocket-client)")

    trunk = Trunk(args.api_url, state["nodeToken"]) if node_plane and websocket else None
    trunk_retry_at, trunk_backoff = 0.0, 5.0
    next_report = next_telemetry = 0.0
    next_heartbeat = 0.0  # poll immediately once, so a trunk-less node is online right away

    print(f"[app] reporting as \"{args.device}\" to {args.report_url} every {args.interval:g} s"
          + (" (simulated sensor)" if args.simulate else ""))
    try:
        while True:
            now = time.time()

            # Trunk lifecycle: keep it up when we can; heartbeat-poll when we can't.
            if trunk:
                if trunk.ws is None and now >= trunk_retry_at:
                    try:
                        trunk.connect()
                        trunk_backoff = 5.0
                        next_telemetry = 0.0  # a fresh trunk gets a sample immediately
                    except (OSError, websocket.WebSocketException) as e:
                        print(f"[node] trunk connect failed ({e}) — retrying in {trunk_backoff:g} s")
                        trunk_retry_at = now + trunk_backoff
                        trunk_backoff = min(trunk_backoff * 2, 300)
                if trunk.ws is not None:
                    try:
                        trunk.poll()
                    except (OSError, websocket.WebSocketException):
                        print("[node] trunk dropped — falling back to the heartbeat poll until it's back")
                        trunk.close()
                        trunk_retry_at = now + trunk_backoff

            temp_c = read_temp_c(sim_phase)

            if now >= next_report and temp_c is not None:
                if report(args, state, temp_c):
                    save_state(path, state)
                next_report = now + args.interval

            if node_plane and now >= next_telemetry and trunk and trunk.ws is not None:
                try:
                    trunk.telemetry(temp_c)
                except (OSError, websocket.WebSocketException):
                    trunk.close()
                    trunk_retry_at = now + trunk_backoff
                next_telemetry = now + args.telemetry_interval

            if node_plane and (trunk is None or trunk.ws is None) and now >= next_heartbeat:
                if not heartbeat(args.api_url, state):
                    node_plane = False  # revoked/disabled: node plane stops, app reports continue
                    if trunk:
                        trunk.close()
                        trunk = None
                next_heartbeat = now + state.get("heartbeatSeconds", 300)

            if args.once:
                break
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\nbye")
    finally:
        if trunk:
            trunk.close()


if __name__ == "__main__":
    main()
