#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "SKIP: udp_relay dataplane smoke test is Linux-only"
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

HTTP_PORT=19340
IN_PORT=19350
OUT_PORT=19351

STREAM_BIN="${ROOT_DIR}/stream"
if [[ ! -x "${STREAM_BIN}" ]]; then
  echo "ERROR: stream binary not found/executable: ${STREAM_BIN}"
  exit 1
fi

TMP_DIR=""
STREAM_PID=""
GEN_PID=""

cleanup() {
  if [[ -n "${STREAM_PID}" ]]; then
    kill "${STREAM_PID}" 2>/dev/null || true
  fi
  if [[ -n "${GEN_PID}" ]]; then
    kill "${GEN_PID}" 2>/dev/null || true
  fi
  if [[ -n "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

TMP_DIR="$(mktemp -d)"
CFG="${TMP_DIR}/udp_relay.json"

cat >"${CFG}" <<EOF
{
  "settings": {
    "http_auth_enabled": false,
    "http_play_allow": false,

    "performance_passthrough_dataplane": "force",
    "performance_passthrough_workers": 2,
    "performance_passthrough_rx_batch": 32
  },
  "make_stream": [
    {
      "id": "dp",
      "type": "udp",
      "enable": true,
      "input": [
        "udp://127.0.0.1:${IN_PORT}"
      ],
      "output": [
        "udp://127.0.0.1:${OUT_PORT}"
      ]
    }
  ]
}
EOF

"${STREAM_BIN}" scripts/server.lua -a 127.0.0.1 -p "${HTTP_PORT}" \
  --config "${CFG}" \
  --data-dir "${TMP_DIR}/data" \
  --log "${TMP_DIR}/stream.log" \
  --no-stdout &
STREAM_PID=$!

# Ждём готовности HTTP сервера. У нас нет отдельного /health, поэтому проверяем root.
for _ in $(seq 1 80); do
  if curl -fsS "http://127.0.0.1:${HTTP_PORT}/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

# Запускаем генератор TS и проверяем, что на выходном UDP порту реально появляются датаграммы.
python3 "${ROOT_DIR}/tools/gen_spts.py" \
  --addr 127.0.0.1 \
  --port "${IN_PORT}" \
  --duration 4 \
  --pps 200 \
  --payload-per-program 1 \
  --stream-type 0x1B \
  >/dev/null 2>&1 &
GEN_PID=$!

python3 - <<PY
import socket, time, sys

OUT_PORT = ${OUT_PORT}

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("127.0.0.1", OUT_PORT))
sock.settimeout(0.5)

count = 0
deadline = time.time() + 3.0
while time.time() < deadline:
    try:
        data, _ = sock.recvfrom(2048)
        if data:
            count += 1
    except socket.timeout:
        pass

if count < 5:
    print("ERROR: expected UDP packets on output, got:", count)
    sys.exit(1)
print("OK: received UDP packets:", count)
PY

echo "OK"
