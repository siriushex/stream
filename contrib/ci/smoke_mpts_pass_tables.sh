#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-9058}"
DATA_DIR="${DATA_DIR:-./data_ci_mpts_pass}"
WEB_DIR="${WEB_DIR:-./web}"
LOG_FILE="${LOG_FILE:-./ci_server_mpts_pass.log}"
CONFIG_FILE="${CONFIG_FILE:-./fixtures/mpts_pass.json}"
GEN_DURATION="${GEN_DURATION:-8}"
GEN_PPS="${GEN_PPS:-200}"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  if [[ -n "${GEN1_PID:-}" ]]; then
    kill "$GEN1_PID" 2>/dev/null || true
  fi
  rm -f "$LOG_FILE"
  rm -rf "$DATA_DIR"
}
trap cleanup EXIT

./configure.sh
make

./stream scripts/server.lua -p "$PORT" --data-dir "$DATA_DIR" --web-dir "$WEB_DIR" --config "$CONFIG_FILE" --import-mode replace > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

sleep 2

python3 tools/gen_spts.py \
  --port 12345 \
  --pnr 101 \
  --pmt-pid 4096 \
  --video-pid 256 \
  --pcr-pid 256 \
  --service-name "Pass Service" \
  --provider-name "Astral" \
  --emit-sdt \
  --emit-eit \
  --emit-cat \
  --duration "$GEN_DURATION" \
  --pps "$GEN_PPS" \
  > /dev/null 2>&1 &
GEN1_PID=$!

sleep 1

EXPECT_CAT=1 EXPECT_PNRS="101" EXPECT_PMT_PNRS="101" EXPECT_SDT_SERVICE_NAMES="101=Pass Service" EXPECT_SDT_PROVIDER_NAMES="101=Astral" EXPECT_SERVICE_COUNT=1 tools/verify_mpts.sh "udp://127.0.0.1:12346" 4

# Проверяем, что в выходе есть EIT actual (PID 0x12, table_id 0x4E).
python3 tools/scan_pid.py --addr 127.0.0.1 --port 12346 --pid 0x12 --table-id 0x4E --duration 3
