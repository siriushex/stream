#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-9062}"
DATA_DIR="${DATA_DIR:-./data_ci_mpts_cat}"
WEB_DIR="${WEB_DIR:-./web}"
LOG_FILE="${LOG_FILE:-./ci_server_mpts_cat.log}"
CONFIG_FILE="${CONFIG_FILE:-./fixtures/mpts_cat.json}"
GEN_DURATION="${GEN_DURATION:-8}"
GEN_PPS="${GEN_PPS:-200}"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  if [[ -n "${GEN1_PID:-}" ]]; then
    kill "$GEN1_PID" 2>/dev/null || true
  fi
  if [[ -n "${GEN2_PID:-}" ]]; then
    kill "$GEN2_PID" 2>/dev/null || true
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
  --port 12355 \
  --pnr 101 \
  --pmt-pid 4096 \
  --video-pid 256 \
  --pcr-pid 256 \
  --pmt-ca-system-id 0x0B00 \
  --pmt-ca-pid 500 \
  --pmt-ca-private-data 010203 \
  --duration "$GEN_DURATION" \
  --pps "$GEN_PPS" \
  > /dev/null 2>&1 &
GEN1_PID=$!

python3 tools/gen_spts.py \
  --port 12357 \
  --pnr 102 \
  --pmt-pid 4096 \
  --video-pid 256 \
  --pcr-pid 256 \
  --pmt-ca-system-id 0x0B00 \
  --pmt-ca-pid 500 \
  --pmt-ca-private-data 010203 \
  --duration "$GEN_DURATION" \
  --pps "$GEN_PPS" \
  > /dev/null 2>&1 &
GEN2_PID=$!

sleep 1

EXPECT_TOT=1 EXPECT_CAT=1 EXPECT_PNRS="101,102" EXPECT_PMT_PNRS="101,102" EXPECT_SDT_SERVICE_NAMES="101=MPTS CA 1,102=MPTS CA 2" EXPECT_SDT_PROVIDER_NAMES="101=Astral,102=Astral" EXPECT_SERVICE_COUNT=2 EXPECT_CAT_CAS="0x0B00:800" EXPECT_PMT_CAS="0x0B00:33,0x0B00:36" tools/verify_mpts.sh "udp://127.0.0.1:12356" 5

