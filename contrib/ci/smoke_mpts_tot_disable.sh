#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-9063}"
DATA_DIR="${DATA_DIR:-./data_ci_mpts_tot_disable}"
WEB_DIR="${WEB_DIR:-./web}"
LOG_FILE="${LOG_FILE:-./ci_server_mpts_tot_disable.log}"

INPUT_PORT="${INPUT_PORT:-12511}"
OUTPUT_PORT="${OUTPUT_PORT:-12512}"
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

input_port = int(os.environ.get("INPUT_PORT", "12511"))
output_port = int(os.environ.get("OUTPUT_PORT", "12512"))

config = {
    "settings": {},
    "make_stream": [
        {
            "id": "mpts_tot_disable",
            "name": "MPTS TOT Disable",
            "type": "spts",
            "enable": True,
            "mpts": True,
            "mpts_services": [
                {
                    "input": f"udp://127.0.0.1:{input_port}",
                    "pnr": 101,
                    "service_name": "TOT Disable 101",
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
                    # minutes (new UI)
                    "utc_offset": 180,
                },
                "advanced": {
                    "si_interval_ms": 500,
                    "disable_tot": True,
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

EXPECT_NO_TOT=1 EXPECT_PNRS="101" EXPECT_PMT_PNRS="101" EXPECT_SERVICE_COUNT=1 tools/verify_mpts.sh "udp://127.0.0.1:${OUTPUT_PORT}" 5

echo "OK"

