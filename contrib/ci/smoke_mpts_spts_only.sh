#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-9062}"
DATA_DIR="${DATA_DIR:-./data_ci_mpts_spts_only}"
WEB_DIR="${WEB_DIR:-./web}"
LOG_FILE="${LOG_FILE:-./ci_server_mpts_spts_only.log}"
CONFIG_FILE="${CONFIG_FILE:-./fixtures/mpts_spts_only.json}"
GEN_DURATION="${GEN_DURATION:-6}"
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

./astra scripts/server.lua -p "$PORT" --data-dir "$DATA_DIR" --web-dir "$WEB_DIR" --config "$CONFIG_FILE" --import-mode replace > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

sleep 2

python3 tools/gen_spts.py \
  --port 12355 \
  --pnr 101 \
  --pmt-pid 4096 \
  --video-pid 256 \
  --pcr-pid 256 \
  --extra-pnr 102 \
  --extra-pmt-pid 4097 \
  --extra-video-pid 257 \
  --extra-pcr-pid 257 \
  --service-name "SPTS Only" \
  --provider-name "Astral" \
  --emit-sdt \
  --duration "$GEN_DURATION" \
  --pps "$GEN_PPS" \
  > /dev/null 2>&1 &
GEN1_PID=$!

sleep 2

# MPTS должен отклонить multi-PAT при spts_only=true, PAT в выходе отсутствует.
if python3 tools/scan_pid.py --addr 127.0.0.1 --port 12356 --pid 0x0000 --duration 2; then
  echo "unexpected PAT on output with spts_only=true" >&2
  exit 1
fi

# Проверяем лог на причину отказа.
if ! grep -q "spts_only=true" "$LOG_FILE"; then
  echo "expected spts_only warning in log" >&2
  exit 1
fi

exit 0
