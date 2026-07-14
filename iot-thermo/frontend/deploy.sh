#!/usr/bin/env bash
# Deploy the thermo FRONTEND — the aggregated dashboard, a stateless JS qube
# (dynamic worker). No build step: the bundle is the manifest + the module.
#
#   QUBEPODS_TOKEN=qube_…  [QUBEPODS_API=https://api.qubepods.com]  ./deploy.sh
set -euo pipefail
cd "$(dirname "$0")"

API="${QUBEPODS_API:-https://api.qubepods.com}"
: "${QUBEPODS_TOKEN:?set QUBEPODS_TOKEN (project token, deploy scope)}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp src/index.js "$WORK/index.js"
cat > "$WORK/qubepod.jsonc" <<'MANIFEST'
{
  "apiVersion": "qubepods.com/v1",
  "kind": "QubePod",
  "name": "qubepods.examples.thermo_frontend",
  "project": "iot",
  "version": "0.2.0",
  "runtime": "stateless",
  "component": { "module": "index.js" },
  "imports": { "database": [{ "name": "db", "interface": "qubepods:sql/query", "tier": "light-fast" }] }
}
MANIFEST
( cd "$WORK" && zip -qr bundle.zip qubepod.jsonc index.js )

curl -fsS -X POST "$API/api/deploy" \
  -H "Authorization: Bearer $QUBEPODS_TOKEN" \
  -F "environment=production" \
  -F "bundle=@$WORK/bundle.zip" -w '\nHTTP %{http_code}\n'
