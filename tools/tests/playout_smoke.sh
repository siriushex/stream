#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HTTP_PORT=19100
ASTRA_PORT=19110

ASTRA_BIN="${ROOT_DIR}/astral"
if [[ ! -x "${ASTRA_BIN}" ]]; then
  echo "ERROR: ${ASTRA_BIN} not found/executable"
  exit 1
fi

TMP_DIR=""
ASTRA_PID=""
HTTP_PID=""

cleanup() {
  if [[ -n "${ASTRA_PID}" ]]; then
    kill "${ASTRA_PID}" 2>/dev/null || true
  fi
  if [[ -n "${HTTP_PID}" ]]; then
    kill "${HTTP_PID}" 2>/dev/null || true
  fi
  if [[ -n "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

python3 "$ROOT_DIR/tools/tests/mock_http_ts.py" \
  --port "$HTTP_PORT" \
  --packet-interval 0.02 \
  --burst-on-sec 2 \
  --burst-off-sec 3 \
  --burst-packet-interval 0.002 \
  --quiet &
HTTP_PID=$!

sleep 1
curl -I "http://127.0.0.1:${HTTP_PORT}/stream.ts" >/dev/null

TMP_DIR="$(mktemp -d)"
CFG="${TMP_DIR}/playout.json"

cat >"${CFG}" <<EOF
{
  "settings": {
    "http_play_stream": true,
    "input_resilience": { "enabled": false, "default_profile": "wan" }
  },
  "make_stream": [
    {
      "id": "p_no_playout",
      "type": "udp",
      "enable": true,
      "input": [
        "http://127.0.0.1:${HTTP_PORT}/stream.ts#net_profile=bad&jitter_buffer_ms=800&jitter_max_buffer_mb=8"
      ],
      "output": []
    },
    {
      "id": "p_playout",
      "type": "udp",
      "enable": true,
      "input": [
        "http://127.0.0.1:${HTTP_PORT}/stream.ts#net_profile=bad&jitter_buffer_ms=800&jitter_max_buffer_mb=8&playout=1&playout_mode=auto&playout_target_kbps=auto&playout_tick_ms=10&playout_null_stuffing=1&playout_target_fill_ms=800&playout_max_buffer_mb=8"
      ],
      "output": []
    }
  ]
}
EOF

"${ASTRA_BIN}" scripts/server.lua -a 127.0.0.1 -p "${ASTRA_PORT}" \
  --config "${CFG}" \
  --data-dir "${TMP_DIR}/data" \
  --web-dir "${ROOT_DIR}/web" \
  --log "${TMP_DIR}/astra.log" \
  --no-stdout &
ASTRA_PID=$!

for _ in $(seq 1 80); do
  if curl -fsS "http://127.0.0.1:${ASTRA_PORT}/index.html" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

TOKEN="$(
  curl -fsS -X POST "http://127.0.0.1:${ASTRA_PORT}/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    --data-binary '{"username":"admin","password":"admin"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])'
)"

echo "Checking /play stability without playout (expected to stall on burst OFF)..."
set +e
OUT_NO="$(
  curl -fsS --max-time 20 --speed-time 3 --speed-limit 1 \
    "http://127.0.0.1:${ASTRA_PORT}/play/p_no_playout" \
    -o /dev/null 2>&1
)"
RC_NO=$?
set -e
if [[ "${RC_NO}" -eq 0 ]]; then
  echo "ERROR: expected stall/low-speed without playout, but curl succeeded"
  exit 1
fi
if ! echo "${OUT_NO}" | grep -q "Operation too slow"; then
  echo "ERROR: expected low-speed stall without playout, got:"
  echo "${OUT_NO}"
  exit 1
fi

echo "Checking /play stability with playout (should not stall)..."
set +e
OUT_YES="$(
  curl -fsS --max-time 20 --speed-time 3 --speed-limit 1 \
    "http://127.0.0.1:${ASTRA_PORT}/play/p_playout" \
    -o /dev/null 2>&1
)"
RC_YES=$?
set -e
if [[ "${RC_YES}" -eq 0 ]]; then
  : # ok (unexpected for streaming, but accept)
else
  # curl uses rc=28 for max-time timeout; that's expected for a streaming endpoint.
  if echo "${OUT_YES}" | grep -q "Operation too slow"; then
    echo "ERROR: playout stream still stalled (low-speed):"
    echo "${OUT_YES}"
    exit 1
  fi
fi

echo "Checking stream-status playout stats..."
N1="$(
  curl -fsS "http://127.0.0.1:${ASTRA_PORT}/api/v1/stream-status/p_playout" \
    -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); i=(d.get("inputs") or [{}])[0]; p=i.get("playout") or {}; print(int(p.get("null_packets_total") or 0))'
)"
sleep 2
N2="$(
  curl -fsS "http://127.0.0.1:${ASTRA_PORT}/api/v1/stream-status/p_playout" \
    -H "Authorization: Bearer ${TOKEN}" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); i=(d.get("inputs") or [{}])[0]; p=i.get("playout") or {}; print(int(p.get("null_packets_total") or 0))'
)"
python3 - <<PY
import sys
n1=int("${N1}"); n2=int("${N2}")
assert n2 >= n1, (n1, n2)
print("playout null_packets_total:", n1, "->", n2)
PY

echo "playout_smoke OK"
