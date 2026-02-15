#!/usr/bin/env bash
set -euo pipefail

# Linux-only smoke test:
# - starts Stream with dataplane passthrough enabled (auto)
# - sends invalid UDP datagrams (len not divisible by 188)
# - expects dataplane watchdog to fall back to legacy pipeline
#
# Требования:
# - Linux
# - python3
#
# Использование:
#   tools/tests/dataplane_watchdog_smoke.sh
#   STREAM_BIN=/path/to/stream tools/tests/dataplane_watchdog_smoke.sh

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "SKIP: Linux only"
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

STREAM_BIN="${STREAM_BIN:-}"
if [[ -z "${STREAM_BIN}" ]]; then
  if [[ -x "${ROOT_DIR}/stream" ]]; then
    STREAM_BIN="${ROOT_DIR}/stream"
  elif [[ -x "${ROOT_DIR}/astral" ]]; then
    STREAM_BIN="${ROOT_DIR}/astral"
  else
    echo "ERROR: STREAM_BIN not set and no ./stream or ./astral found"
    exit 1
  fi
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  if [[ -n "${STREAM_PID:-}" ]]; then
    kill "${STREAM_PID}" >/dev/null 2>&1 || true
    wait "${STREAM_PID}" >/dev/null 2>&1 || true
  fi
  rm -rf "${TMP_DIR}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

HTTP_PORT="${HTTP_PORT:-18080}"
IN_PORT="${IN_PORT:-19000}"
OUT_PORT="${OUT_PORT:-19001}"

CFG_PATH="${TMP_DIR}/smoke.json"
LOG_PATH="${TMP_DIR}/stream.log"

cat >"${CFG_PATH}" <<JSON
{
  "settings": {
    "performance_passthrough_dataplane": "auto",
    "performance_passthrough_workers": 1,
    "performance_passthrough_rx_batch": 32
  },
  "make_stream": [
    {
      "id": "pt_0001",
      "enable": true,
      "name": "PT Smoke",
      "input": "udp://127.0.0.1:${IN_PORT}",
      "output": ["udp://127.0.0.1:${OUT_PORT}"]
    }
  ]
}
JSON

echo "Starting: ${STREAM_BIN}"
"${STREAM_BIN}" -c "${CFG_PATH}" -p "${HTTP_PORT}" --data-dir "${TMP_DIR}/data" >"${LOG_PATH}" 2>&1 &
STREAM_PID="$!"

sleep 1

echo "Sending invalid UDP datagrams to 127.0.0.1:${IN_PORT} ..."
python3 - <<PY
import socket
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
dst = ("127.0.0.1", int("${IN_PORT}"))
# 1000 bytes: не кратно 188 → dataplane должен считать как bad_datagrams.
payload = b"x" * 1000
for _ in range(200):
    sock.sendto(payload, dst)
sock.close()
PY

echo "Waiting for watchdog tick..."
sleep 7

if grep -q "dataplane fallback to legacy" "${LOG_PATH}"; then
  echo "OK: fallback observed"
  exit 0
fi

echo "FAIL: fallback not observed. Last log lines:"
tail -n 200 "${LOG_PATH}" || true
exit 1

