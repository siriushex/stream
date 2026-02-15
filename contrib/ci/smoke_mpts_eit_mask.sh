#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-9064}"
DATA_DIR="${DATA_DIR:-./data_ci_mpts_eit_mask}"
WEB_DIR="${WEB_DIR:-./web}"
LOG_FILE="${LOG_FILE:-./ci_server_mpts_eit_mask.log}"

INPUT_PORT="${INPUT_PORT:-12521}"
OUTPUT_PORT="${OUTPUT_PORT:-12522}"
GEN_DURATION="${GEN_DURATION:-8}"
GEN_PPS="${GEN_PPS:-200}"

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

input_port = int(os.environ.get("INPUT_PORT", "12521"))
output_port = int(os.environ.get("OUTPUT_PORT", "12522"))

config = {
    "settings": {},
    "make_stream": [
        {
            "id": "mpts_eit_mask",
            "name": "MPTS EIT Mask",
            "type": "spts",
            "enable": True,
            "mpts": True,
            "mpts_services": [
                {
                    "input": f"udp://127.0.0.1:{input_port}",
                    "pnr": 101,
                    "service_name": "EIT Mask 101",
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
                "advanced": {
                    "si_interval_ms": 500,
                    "pass_eit": True,
                    "eit_source": 1,
                    # Разрешаем только EIT p/f actual, чтобы schedule (0x50) не проходил.
                    "eit_table_ids": "0x4E",
                },
            },
        }
    ],
}

json.dump(config, sys.stdout, ensure_ascii=False)
PY

./stream scripts/server.lua -p "$PORT" --data-dir "$DATA_DIR" --web-dir "$WEB_DIR" --config "$CONFIG_FILE" --import-mode replace > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

sleep 2

python3 tools/gen_spts.py \
  --port "$INPUT_PORT" \
  --pnr 101 \
  --pmt-pid 4096 \
  --video-pid 256 \
  --pcr-pid 256 \
  --emit-eit \
  --eit-table-ids 0x4E,0x50 \
  --duration "$GEN_DURATION" \
  --pps "$GEN_PPS" \
  > /dev/null 2>&1 &
GEN_PID=$!

sleep 1

EXPECT_TOT=1 EXPECT_PNRS="101" EXPECT_PMT_PNRS="101" EXPECT_SERVICE_COUNT=1 tools/verify_mpts.sh "udp://127.0.0.1:${OUTPUT_PORT}" 5

# В выходе должен быть EIT actual (PID 0x12, table_id 0x4E)...
python3 tools/scan_pid.py --addr 127.0.0.1 --port "$OUTPUT_PORT" --pid 0x12 --table-id 0x4E --duration 3

# ...но EIT schedule (0x50) должен быть отфильтрован.
if python3 tools/scan_pid.py --addr 127.0.0.1 --port "$OUTPUT_PORT" --pid 0x12 --table-id 0x50 --duration 3; then
  echo "Unexpected EIT schedule table_id 0x50 present on PID 0x12"
  exit 1
fi

echo "OK"

