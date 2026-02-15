#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ASTRA_PORT=19320
IN_PORT=19330
OUT_PORT=19331

STREAM_BIN="${ROOT_DIR}/stream"
if [[ ! -x "${STREAM_BIN}" ]]; then
  echo "ERROR: ${STREAM_BIN} not found/executable"
  exit 1
fi

TMP_DIR=""
STREAM_PID=""
GEN_PID=""
KEEP_TMP=""

cleanup() {
  if [[ -n "${STREAM_PID}" ]]; then
    kill "${STREAM_PID}" 2>/dev/null || true
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
CFG="${TMP_DIR}/udp_mmsg.json"

cat >"${CFG}" <<EOF
{
  "settings": {
    "http_auth_enabled": false
  },
  "make_stream": [
    {
      "id": "mmsg",
      "type": "udp",
      "enable": true,
      "input": [
        "udp://127.0.0.1:${IN_PORT}#use_recvmmsg=1&rx_batch=32"
      ],
      "output": [
        "udp://127.0.0.1:${OUT_PORT}#use_sendmmsg=1&tx_batch=8"
      ]
    }
  ]
}
EOF

"${STREAM_BIN}" scripts/server.lua -a 127.0.0.1 -p "${ASTRA_PORT}" \
  --config "${CFG}" \
  --data-dir "${TMP_DIR}/data" \
  --log "${TMP_DIR}/stream.log" \
  --no-stdout &
STREAM_PID=$!

# Ждём готовности HTTP сервера. У нас нет отдельного /health, поэтому проверяем root.
for _ in $(seq 1 80); do
  if curl -fsS "http://127.0.0.1:${ASTRA_PORT}/" >/dev/null 2>&1; then
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

