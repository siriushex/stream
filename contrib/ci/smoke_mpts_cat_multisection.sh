#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-9065}"
DATA_DIR="${DATA_DIR:-./data_ci_mpts_cat_multisection}"
WEB_DIR="${WEB_DIR:-./web}"
LOG_FILE="${LOG_FILE:-./ci_server_mpts_cat_multisection.log}"

INPUT_PORT="${INPUT_PORT:-12531}"
OUTPUT_PORT="${OUTPUT_PORT:-12532}"
GEN_DURATION="${GEN_DURATION:-8}"
GEN_PPS="${GEN_PPS:-200}"
CA_COUNT="${CA_COUNT:-220}"
CA_PID_START="${CA_PID_START:-600}"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  if [[ -n "${GEN_PID:-}" ]]; then
    kill "$GEN_PID" 2>/dev/null || true
  fi
  if [[ -n "${CONFIG_FILE:-}" ]] && [[ -f "$CONFIG_FILE" ]]; then
    rm -f "$CONFIG_FILE"
  fi
  rm -f "$LOG_FILE"
  rm -rf "$DATA_DIR"
}
trap cleanup EXIT

./configure.sh
make

CONFIG_FILE="$(mktemp)"
python3 - <<'PY' >"$CONFIG_FILE"
import json
import os
import sys

input_port = int(os.environ.get("INPUT_PORT", "12531"))
output_port = int(os.environ.get("OUTPUT_PORT", "12532"))
count = int(os.environ.get("CA_COUNT", "220"))
pid_start = int(os.environ.get("CA_PID_START", "600"))

ca = []
for i in range(count):
    ca.append({
        "ca_system_id": 0x0B00,
        "ca_pid": pid_start + i,
        # Делает дескриптор не слишком маленьким, чтобы форсировать multi-section.
        "private_data": "0102030405060708090A0B0C0D0E0F10",
    })

config = {
    "settings": {},
    "make_stream": [
        {
            "id": "mpts_cat_multisection",
            "name": "MPTS CAT MultiSection",
            "type": "spts",
            "enable": True,
            "mpts": True,
            "mpts_services": [
                {
                    "input": f"udp://127.0.0.1:{input_port}",
                    "pnr": 101,
                    "service_name": "CAT MS 101",
                    "service_provider": "Astral",
                    "service_type_id": 1,
                }
            ],
            "output": [f"udp://127.0.0.1:{output_port}"],
            "mpts_config": {
                "general": {
                    "provider_name": "Astral",
                    "tsid": 1,
                    "onid": 1,
                    "network_id": 1,
                    "network_name": "Astral",
                    "country": "RUS",
                    "utc_offset": 180,
                },
                "ca": ca,
                "advanced": {
                    "si_interval_ms": 500,
                },
            },
        }
    ],
}

json.dump(config, sys.stdout, ensure_ascii=False)
PY

./astra scripts/server.lua -p "$PORT" --data-dir "$DATA_DIR" --web-dir "$WEB_DIR" --config "$CONFIG_FILE" --import-mode replace > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

sleep 2

python3 tools/gen_spts.py \
  --port "$INPUT_PORT" \
  --pnr 101 \
  --pmt-pid 4096 \
  --video-pid 256 \
  --pcr-pid 256 \
  --duration "$GEN_DURATION" \
  --pps "$GEN_PPS" \
  > /dev/null 2>&1 &
GEN_PID=$!

sleep 1

# Проверяем, что в CAT не обрезаны CA descriptors и присутствует запись из "хвоста" списка.
last_pid="$((CA_PID_START + CA_COUNT - 1))"
EXPECT_TOT=1 EXPECT_CAT=1 EXPECT_PNRS="101" EXPECT_PMT_PNRS="101" EXPECT_SERVICE_COUNT=1 \
  EXPECT_CAT_CAS="0x0B00:${last_pid}" \
  tools/verify_mpts.sh "udp://127.0.0.1:${OUTPUT_PORT}" 5

echo "OK"

