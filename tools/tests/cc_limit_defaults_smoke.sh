#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ASTRA_PORT=19221
TS_PORT=19231

ASTRA_BIN="${ROOT_DIR}/stream"
if [[ ! -x "${ASTRA_BIN}" ]]; then
  echo "ERROR: ${ASTRA_BIN} not found/executable"
  exit 1
fi

TMP_DIR=""
ASTRA_PID=""
GEN_PID=""
KEEP_TMP=""

cleanup() {
  if [[ -n "${ASTRA_PID}" ]]; then
    kill "${ASTRA_PID}" 2>/dev/null || true
  fi
  if [[ -n "${GEN_PID}" ]]; then
    kill "${GEN_PID}" 2>/dev/null || true
  fi
  if [[ -n "${TMP_DIR}" && -z "${KEEP_TMP}" ]]; then
    rm -rf "${TMP_DIR}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

TMP_DIR="$(mktemp -d)"
CFG="${TMP_DIR}/cc_limit_defaults.json"

cat >"${CFG}" <<EOF
{
  "settings": {
    "http_play_stream": true,
    "http_auth_enabled": false,

    "telegram_enabled": true,
    "telegram_detectors_preset": "custom",
    "telegram_detectors_cc_limit_enabled": true,
    "telegram_detectors_cc_limit": 1
  },
  "make_stream": [
    {
      "id": "cc_default",
      "type": "udp",
      "enable": true,
      "input": [
        "udp://127.0.0.1:${TS_PORT}#sync"
      ],
      "output": []
    },
    {
      "id": "cc_override",
      "type": "udp",
      "enable": true,
      "input": [
        "udp://127.0.0.1:${TS_PORT}#cc_limit=3#sync"
      ],
      "output": []
    }
  ]
}
EOF

"${ASTRA_BIN}" scripts/server.lua -a 127.0.0.1 -p "${ASTRA_PORT}" \
  --config "${CFG}" \
  --data-dir "${TMP_DIR}/data" \
  --log "${TMP_DIR}/stream.log" \
  --no-stdout &
ASTRA_PID=$!

for _ in $(seq 1 80); do
  if curl -fsS "http://127.0.0.1:${ASTRA_PORT}/health" >/dev/null 2>&1; then
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

# Start SPTS generator and inject CC errors (2 errors/sec) after warm-up.
python3 "${ROOT_DIR}/tools/gen_spts.py" \
  --addr 127.0.0.1 \
  --port "${TS_PORT}" \
  --duration 20 \
  --pps 200 \
  --payload-per-program 1 \
  --stream-type 0x1B \
  --cc-error-pid 0x0100 \
  --cc-error-every 100 \
  --cc-error-start-sec 4 \
  >/dev/null 2>&1 &
GEN_PID=$!

sleep 7

seen_diff="0"
override_tripped="0"

for _ in $(seq 1 8); do
  S_DEFAULT="$(curl -fsS "http://127.0.0.1:${ASTRA_PORT}/api/v1/stream-status/cc_default?lite=1" -H "Authorization: Bearer ${TOKEN}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("1" if d.get("on_air") else "0")')"
  S_OVERRIDE="$(curl -fsS "http://127.0.0.1:${ASTRA_PORT}/api/v1/stream-status/cc_override?lite=1" -H "Authorization: Bearer ${TOKEN}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("1" if d.get("on_air") else "0")')"
  if [[ "${S_DEFAULT}" == "0" && "${S_OVERRIDE}" == "1" ]]; then
    seen_diff="1"
  fi
  if [[ "${S_OVERRIDE}" == "0" ]]; then
    override_tripped="1"
  fi
  sleep 1
done

if [[ "${seen_diff}" != "1" ]]; then
  KEEP_TMP=1
  echo "ERROR: expected global CC limit default to affect on_air (need cc_default DOWN and cc_override UP)"
  echo "Log: ${TMP_DIR}/stream.log"
  exit 1
fi

if [[ "${override_tripped}" == "1" ]]; then
  KEEP_TMP=1
  echo "ERROR: cc_override (cc_limit=3) tripped (expected to stay UP with <=2 CC errors/sec)"
  echo "Log: ${TMP_DIR}/stream.log"
  exit 1
fi

echo "cc_limit_defaults_smoke OK (global cc_limit=1 trips; explicit cc_limit=3 does not)"

