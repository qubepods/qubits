#!/usr/bin/env bash
# Deploy the thermo backend TWIN — builds the store-component core and ships
# it as a STATEFUL deployment (the qubekit-editor deploy.sh pattern, plus the
# component). Until `qube deploy` packs the `.kvcore` artifact itself, this
# script is the deploy path for a twin backend.
#
#   QUBEPODS_TOKEN=qube_…  [QUBEPODS_API=https://api.qubepods.com]  ./deploy.sh
#
# The token is a project token with the deploy scope, minted in the console.
# Never commit it.
set -euo pipefail
cd "$(dirname "$0")"

API="${QUBEPODS_API:-https://api.qubepods.com}"
: "${QUBEPODS_TOKEN:?set QUBEPODS_TOKEN (project token, deploy scope)}"

# 1. Build (CLEAN — a stale artifact from an older source must never ship).
#    A db/kv-using qube emits the .kvcore store-component core; a pure
#    channel qube (this fleet twin) emits only the raw core — the twin
#    runtime runs either. The build exits non-zero on the final
#    component-lift step (a tracked q64 gap), so gate on the artifact, not
#    the exit code. q64 ≥ 0.0.11 required (0.0.9 emits a module that traps
#    on its first state-Vec write).
rm -rf target
qube build --addr wasm32 || true
KVCORE=$(ls target/debug/wasm32/*.kvcore.wasm 2>/dev/null | head -1 || true)
RAWCORE=$(ls target/debug/wasm32/*.wasm 2>/dev/null | grep -v '\.component\.' | head -1 || true)
ARTIFACT="${KVCORE:-$RAWCORE}"
[ -n "$ARTIFACT" ] && [ -f "$ARTIFACT" ] || { echo "no wasm artifact — check the qube/q64 version" >&2; exit 1; }

# 2. Bundle: the deploy manifest + the artifact. `runtime: "stateful"` is the
#    line that makes this a twin — the platform routes the app's WebSocket to
#    the project's ProjectTwin, which runs this wasm per message.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp "$ARTIFACT" "$WORK/thermo.kvcore.wasm"
cat > "$WORK/qubepod.jsonc" <<'MANIFEST'
{
  "apiVersion": "qubepods.com/v1",
  "kind": "QubePod",
  "name": "qubepods.examples.thermo",
  "project": "iot",
  "version": "0.2.2",
  "runtime": "stateful",
  "component": { "wasm": "thermo.kvcore.wasm" }
}
MANIFEST
( cd "$WORK" && zip -qr bundle.zip qubepod.jsonc thermo.kvcore.wasm )

# 3. Ship.
curl -fsS -X POST "$API/api/deploy" \
  -H "Authorization: Bearer $QUBEPODS_TOKEN" \
  -F "environment=production" \
  -F "bundle=@$WORK/bundle.zip" -w '\nHTTP %{http_code}\n'
