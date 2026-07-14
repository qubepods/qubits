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

# 1. Build: q64 ≥ 0.0.10 emits the .kvcore store-component core (0.0.9 emits
#    a module that traps on its first state-Vec write — don't ship it).
#    The build exits non-zero on the final component-lift step (a tracked q64
#    gap — the twin runtime runs the core directly), so gate on the artifact,
#    not the exit code.
qube build --addr wasm32 || true
KVCORE=$(ls target/debug/wasm32/*.kvcore.wasm | head -1)
[ -f "$KVCORE" ] || { echo "no .kvcore artifact — check the qube/q64 version" >&2; exit 1; }

# 2. Bundle: the deploy manifest + the artifact. `runtime: "stateful"` is the
#    line that makes this a twin — the platform routes the app's WebSocket to
#    the project's ProjectTwin, which runs this wasm per message.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp "$KVCORE" "$WORK/thermo.kvcore.wasm"
cat > "$WORK/qubepod.jsonc" <<'MANIFEST'
{
  "apiVersion": "qubepods.com/v1",
  "kind": "QubePod",
  "name": "qubepods.examples.thermo",
  "project": "iot",
  "version": "0.2.0",
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
