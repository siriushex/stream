#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-9057}"
DATA_DIR="${DATA_DIR:-./data_ci_mpts_collision}"
WEB_DIR="${WEB_DIR:-./web}"
LOG_FILE="${LOG_FILE:-./ci_server_mpts_collision.log}"
CONFIG_FILE="${CONFIG_FILE:-./fixtures/mpts_collision.json}"
GEN_DURATION="${GEN_DURATION:-6}"
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
  --port 12345 \
  --pnr 101 \
  --pmt-pid 4096 \
  --video-pid 256 \
  --pcr-pid 256 \
  --duration "$GEN_DURATION" \
  --pps "$GEN_PPS" \
  > /dev/null 2>&1 &
GEN1_PID=$!
python3 tools/gen_spts.py \
  --port 12347 \
  --pnr 102 \
  --pmt-pid 4096 \
  --video-pid 256 \
  --pcr-pid 256 \
  --duration "$GEN_DURATION" \
  --pps "$GEN_PPS" \
  > /dev/null 2>&1 &
GEN2_PID=$!

sleep 2

if ! grep -q "PID конфликт при disable_auto_remap" "$LOG_FILE" && ! grep -q "PMT PID конфликт при disable_auto_remap" "$LOG_FILE"; then
  echo "PID collision not detected in logs"
  exit 1
fi
