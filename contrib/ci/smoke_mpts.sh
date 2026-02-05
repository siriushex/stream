#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-9056}"
DATA_DIR="${DATA_DIR:-./data_ci_mpts}"
WEB_DIR="${WEB_DIR:-./web}"
LOG_FILE="${LOG_FILE:-./ci_server_mpts.log}"
CONFIG_FILE="${CONFIG_FILE:-./fixtures/mpts.json}"
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
  if [[ -n "${COOKIE_JAR:-}" ]] && [[ -f "$COOKIE_JAR" ]]; then
    rm -f "$COOKIE_JAR"
  fi
  if [[ -n "${GEN1_LOG:-}" ]] && [[ -f "$GEN1_LOG" ]]; then
    rm -f "$GEN1_LOG"
  fi
  if [[ -n "${GEN2_LOG:-}" ]] && [[ -f "$GEN2_LOG" ]]; then
    rm -f "$GEN2_LOG"
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

GEN1_LOG="$(mktemp)"
GEN2_LOG="$(mktemp)"
python3 tools/gen_spts.py \
  --port 12345 \
  --pnr 101 \
  --pmt-pid 4096 \
  --video-pid 256 \
  --pcr-pid 256 \
  --duration "$GEN_DURATION" \
  --pps "$GEN_PPS" \
  > "$GEN1_LOG" 2>&1 &
GEN1_PID=$!
python3 tools/gen_spts.py \
  --port 12347 \
  --pnr 102 \
  --pmt-pid 4096 \
  --video-pid 256 \
  --pcr-pid 256 \
  --duration "$GEN_DURATION" \
  --pps "$GEN_PPS" \
  > "$GEN2_LOG" 2>&1 &
GEN2_PID=$!

sleep 1

COOKIE_JAR="$(mktemp)"
if curl -s -c "$COOKIE_JAR" -X POST "http://127.0.0.1:${PORT}/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"admin","password":"admin"}' >/dev/null 2>&1; then
  AUTH_ARGS=( -b "$COOKIE_JAR" )
else
  AUTH_ARGS=()
fi

curl -fsS "http://127.0.0.1:${PORT}/api/v1/streams" "${AUTH_ARGS[@]}" | head -n 1

EXPECT_TOT=1 EXPECT_CAT=1 EXPECT_PNRS="101,102" EXPECT_PMT_PNRS="101,102" EXPECT_SERVICE_COUNT=2 EXPECT_PMT_STREAMS="101=1,102=1" EXPECT_PMT_VIDEO="101=1,102=1" EXPECT_PMT_AUDIO="101=0,102=0" EXPECT_PMT_DATA="101=0,102=0" EXPECT_PMT_PCR="101=256,102=256" EXPECT_NO_CC_ERRORS=1 EXPECT_NO_PES_ERRORS=1 EXPECT_NO_SCRAMBLED=1 EXPECT_SERVICES="MPTS Test 1,MPTS Test 2" EXPECT_PROVIDERS="Astral" EXPECT_NETWORK_ID=1 EXPECT_NETWORK_NAME="Astral" EXPECT_TSID=1 EXPECT_DELIVERY="cable" EXPECT_FREQUENCY_KHZ=650000 EXPECT_SYMBOLRATE_KSPS=6875 EXPECT_MODULATION="256qam" EXPECT_FEC="auto" EXPECT_LCN="101=101,102=102" EXPECT_FREE_CA="101=0,102=0" EXPECT_SERVICE_TYPE="101=1,102=1" EXPECT_BITRATE_KBIT=50000 EXPECT_BITRATE_TOL_PCT=15 tools/verify_mpts.sh "udp://127.0.0.1:12346" 5
