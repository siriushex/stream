#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-9057}"
DATA_DIR="${DATA_DIR:-./data_ci_mpts_strict_pnr}"
WEB_DIR="${WEB_DIR:-./web}"
LOG_FILE="${LOG_FILE:-./ci_server_mpts_strict_pnr.log}"
CONFIG_FILE="${CONFIG_FILE:-./fixtures/mpts_strict_pnr.json}"
GEN_DURATION="${GEN_DURATION:-6}"
GEN_PPS="${GEN_PPS:-200}"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  if [[ -n "${GEN_PID:-}" ]]; then
    kill "$GEN_PID" 2>/dev/null || true
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

# Генерируем вход с multi-program PAT для проверки strict_pnr.
python3 tools/gen_spts.py \
  --port 12349 \
  --pnr 101 \
  --pmt-pid 4096 \
  --video-pid 256 \
  --pcr-pid 256 \
  --extra-pnr 102 \
  --extra-pmt-pid 4097 \
  --extra-video-pid 257 \
  --extra-pcr-pid 257 \
  --duration "$GEN_DURATION" \
  --pps "$GEN_PPS" \
  > /dev/null 2>&1 &
GEN_PID=$!

sleep 2

if ! grep -q "strict_pnr=true -> поток отклонён" "$LOG_FILE"; then
  echo "strict_pnr error not found in log"
  exit 1
fi
