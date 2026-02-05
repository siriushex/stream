#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${PORT:-9072}"
WEB_DIR="${WEB_DIR:-$ROOT_DIR/web}"
STREAM_ID="${STREAM_ID:-transcode_seamless_failover}"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/fixtures/transcode_seamless_failover.json}"
CHECK_OUTPUT="${CHECK_OUTPUT:-1}"

WORK_DIR="$(mktemp -d)"
DATA_DIR="$WORK_DIR/data"
LOG_FILE="$WORK_DIR/server.log"
COOKIE_JAR="$WORK_DIR/cookies.txt"

cleanup() {
  if [[ -n "${FEED_PRIMARY_PID:-}" ]]; then
    kill "$FEED_PRIMARY_PID" 2>/dev/null || true
  fi
  if [[ -n "${FEED_BACKUP_PID:-}" ]]; then
    kill "$FEED_BACKUP_PID" 2>/dev/null || true
  fi
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing fixture: $CONFIG_FILE" >&2
  exit 1
fi

./configure.sh
make

./astra scripts/server.lua -p "$PORT" --data-dir "$DATA_DIR" --web-dir "$WEB_DIR" --config "$CONFIG_FILE" >"$LOG_FILE" 2>&1 &
SERVER_PID=$!
sleep 2

# Try login (ok even if auth disabled)
AUTH_ARGS=()
if curl -fsS -c "$COOKIE_JAR" -X POST "http://127.0.0.1:${PORT}/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"admin","password":"admin"}' >/dev/null 2>&1; then
  AUTH_ARGS=( -b "$COOKIE_JAR" )
fi

TOOLS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/api/v1/tools" "${AUTH_ARGS[@]}")"
FFMPEG_BIN="$(TOOLS_JSON="$TOOLS_JSON" python3 - <<'PY'
import json, os
info = json.loads(os.environ.get("TOOLS_JSON") or "{}")
print(info.get("ffmpeg_path_resolved") or "ffmpeg")
PY
)"

if ! command -v "$FFMPEG_BIN" >/dev/null 2>&1; then
  # If ffmpeg_path_resolved is absolute, command -v will not find it; check executable.
  if [[ ! -x "$FFMPEG_BIN" ]]; then
    echo "ffmpeg not found: $FFMPEG_BIN" >&2
    exit 1
  fi
fi

# Primary and backup multicast feeds.
"$FFMPEG_BIN" -hide_banner -loglevel error -re \
  -f lavfi -i testsrc=size=160x90:rate=25 \
  -f lavfi -i sine=frequency=1000 \
  -shortest -c:v mpeg2video -c:a mp2 \
  -f mpegts "udp://239.255.0.1:12100?pkt_size=1316" >/dev/null 2>&1 &
FEED_PRIMARY_PID=$!

"$FFMPEG_BIN" -hide_banner -loglevel error -re \
  -f lavfi -i testsrc=size=160x90:rate=25 \
  -f lavfi -i sine=frequency=1200 \
  -shortest -c:v mpeg2video -c:a mp2 \
  -f mpegts "udp://239.255.0.1:12101?pkt_size=1316" >/dev/null 2>&1 &
FEED_BACKUP_PID=$!

STATE_OK=0
for _ in $(seq 1 20); do
  STATUS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/api/v1/transcode-status/${STREAM_ID}" "${AUTH_ARGS[@]}")"
  STATE="$(STATUS_JSON="$STATUS_JSON" python3 - <<'PY'
import json, os
info = json.loads(os.environ.get("STATUS_JSON") or "{}")
print(info.get("state") or "")
PY
)"
  if [[ "$STATE" == "RUNNING" ]]; then
    STATE_OK=1
    break
  fi
  sleep 1
done

if [[ "$STATE_OK" -ne 1 ]]; then
  echo "Transcode state not RUNNING (stream_id=$STREAM_ID)" >&2
  tail -n 200 "$LOG_FILE" >&2 || true
  exit 1
fi

if [[ "$CHECK_OUTPUT" == "1" ]]; then
  OUTPUT_OK=0
  for _ in $(seq 1 8); do
    set +e
    ANALYZE_PRE="$(./astra scripts/analyze.lua -n 2 udp://127.0.0.1:12340 2>/dev/null)"
    set -e
    if grep -q "PAT:" <<<"$ANALYZE_PRE"; then
      OUTPUT_OK=1
      break
    fi
    sleep 1
  done
  if [[ "$OUTPUT_OK" -ne 1 ]]; then
    echo "No PAT detected on output before cutover" >&2
    exit 1
  fi
fi

kill "$FEED_PRIMARY_PID" 2>/dev/null || true
wait "$FEED_PRIMARY_PID" 2>/dev/null || true
unset FEED_PRIMARY_PID

CUTOVER_OK=0
for _ in $(seq 1 25); do
  ALERTS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/api/v1/alerts?stream_id=${STREAM_ID}&code=TRANSCODE_CUTOVER_OK&limit=1" "${AUTH_ARGS[@]}")"
  COUNT="$(ALERTS_JSON="$ALERTS_JSON" python3 - <<'PY'
import json, os
rows = json.loads(os.environ.get("ALERTS_JSON") or "[]")
print(len(rows))
PY
)"
  if [[ "$COUNT" -gt 0 ]]; then
    CUTOVER_OK=1
    break
  fi
  sleep 1
done

if [[ "$CUTOVER_OK" -ne 1 ]]; then
  echo "Cutover OK alert not found (stream_id=$STREAM_ID)" >&2
  tail -n 200 "$LOG_FILE" >&2 || true
  exit 1
fi

if [[ "$CHECK_OUTPUT" == "1" ]]; then
  OUTPUT_OK=0
  for _ in $(seq 1 8); do
    set +e
    ANALYZE_POST="$(./astra scripts/analyze.lua -n 2 udp://127.0.0.1:12340 2>/dev/null)"
    set -e
    if grep -q "PAT:" <<<"$ANALYZE_POST"; then
      OUTPUT_OK=1
      break
    fi
    sleep 1
  done
  if [[ "$OUTPUT_OK" -ne 1 ]]; then
    echo "No PAT detected on output after cutover" >&2
    exit 1
  fi
fi
