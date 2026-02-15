#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-9059}"
DATA_DIR="${DATA_DIR:-./data_ci_mpts_multisection}"
WEB_DIR="${WEB_DIR:-./web}"
LOG_FILE="${LOG_FILE:-./ci_server_mpts_multisection.log}"

INPUT_PORT="${INPUT_PORT:-12505}"
OUTPUT_PORT="${OUTPUT_PORT:-12506}"
PNR_START="${PNR_START:-101}"
PROGRAM_COUNT="${PROGRAM_COUNT:-260}"
GEN_DURATION="${GEN_DURATION:-10}"
GEN_PPS="${GEN_PPS:-1}"

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
  if [[ -n "${GEN_LOG:-}" ]] && [[ -f "$GEN_LOG" ]]; then
    rm -f "$GEN_LOG"
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

input_port = int(os.environ.get("INPUT_PORT", "12505"))
output_port = int(os.environ.get("OUTPUT_PORT", "12506"))
pnr_start = int(os.environ.get("PNR_START", "101"))
count = int(os.environ.get("PROGRAM_COUNT", "260"))

services = []
for i in range(count):
    pnr = pnr_start + i
    services.append({
        "input": f"udp://127.0.0.1:{input_port}",
        "pnr": pnr,
        "service_name": f"MS {pnr}",
        "service_provider": "Astral",
        "service_type_id": 1,
        "lcn": pnr,
    })

config = {
    "settings": {},
    "make_stream": [
        {
            "id": "mpts_multisection",
            "name": "MPTS MultiSection",
            "type": "spts",
            "enable": True,
            "input": [f"udp://127.0.0.1:{input_port}"],
            "mpts": True,
            "mpts_services": services,
            "output": [f"udp://127.0.0.1:{output_port}"],
            "mpts_config": {
                "general": {
                    "codepage": "utf-8",
                    "provider_name": "Astral",
                    "tsid": 1,
                    "onid": 1,
                    "network_id": 1,
                    "network_name": "Astral",
                    "country": "RUS",
                    "utc_offset": 3,
                },
                "nit": {
                    "delivery": "cable",
                    "frequency": 650000,
                    "symbolrate": 6875,
                    "modulation": "256qam",
                    "fec": "auto",
                },
                "advanced": {
                    "si_interval_ms": 500,
                    "spts_only": False,
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

GEN_LOG="$(mktemp)"
python3 tools/gen_spts.py \
  --port "$INPUT_PORT" \
  --pnr "$PNR_START" \
  --pmt-pid 4096 \
  --video-pid 256 \
  --program-count "$PROGRAM_COUNT" \
  --payload-per-program 0 \
  --duration "$GEN_DURATION" \
  --pps "$GEN_PPS" \
  > "$GEN_LOG" 2>&1 &
GEN_PID=$!

sleep 2

python3 tools/mpts_si_verify.py \
  --port "$OUTPUT_PORT" \
  --duration 4 \
  --expect-programs "$PROGRAM_COUNT" \
  --expect-sdt "$PROGRAM_COUNT" \
  --expect-nit-services "$PROGRAM_COUNT" \
  --expect-nit-lcn "$PROGRAM_COUNT"

echo "OK"
