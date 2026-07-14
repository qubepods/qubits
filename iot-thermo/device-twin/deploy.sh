#!/usr/bin/env bash
# Deploy the thermo DEVICE TWIN — the per-device backend twin. Same bundle
# shape as ../backend/deploy.sh, plus the `twin` pairing that tells the
# platform to run one instance of this app per device and feed it that
# device's readings.
#
#   QUBEPODS_TOKEN=qube_…  [QUBEPODS_API=https://api.qubepods.com]  ./deploy.sh
set -euo pipefail
cd "$(dirname "$0")"

API="${QUBEPODS_API:-https://api.qubepods.com}"
: "${QUBEPODS_TOKEN:?set QUBEPODS_TOKEN (project token, deploy scope)}"

# Build exits non-zero on the final component-lift step (tracked q64 gap; the
# twin runtime runs the core) — gate on the artifact, not the exit code.
qube build --addr wasm32 || true
KVCORE=$(ls target/debug/wasm32/*.kvcore.wasm | head -1)
[ -f "$KVCORE" ] || { echo "no .kvcore artifact — check the qube/q64 version (needs >= 0.0.11)" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp "$KVCORE" "$WORK/device-twin.kvcore.wasm"
cat > "$WORK/qubepod.jsonc" <<'MANIFEST'
{
  "apiVersion": "qubepods.com/v1",
  "kind": "QubePod",
  "name": "qubepods.examples.thermo_device_twin",
  "project": "iot",
  "version": "0.1.0",
  "runtime": "stateful",
  "twin": { "of": "qubepods.examples.thermo_device" },
  "component": { "wasm": "device-twin.kvcore.wasm" }
}
MANIFEST
( cd "$WORK" && zip -qr bundle.zip qubepod.jsonc device-twin.kvcore.wasm )

curl -fsS -X POST "$API/api/deploy" \
  -H "Authorization: Bearer $QUBEPODS_TOKEN" \
  -F "environment=production" \
  -F "bundle=@$WORK/bundle.zip" -w '\nHTTP %{http_code}\n'
