#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${PORT:-}"
if [[ -z "${PORT}" ]]; then
  PORT="$((45000 + (RANDOM % 10000)))"
fi
WEB_DIR="${WEB_DIR:-$ROOT_DIR/web}"
STREAM_ID="${STREAM_ID:-transcode_seamless_failover}"
SRC_PRIMARY_ID="${SRC_PRIMARY_ID:-src_primary}"
SRC_BACKUP_ID="${SRC_BACKUP_ID:-src_backup}"
TEMPLATE_FILE="${TEMPLATE_FILE:-$ROOT_DIR/fixtures/transcode_seamless_failover.json}"
CHECK_OUTPUT="${CHECK_OUTPUT:-1}"

WORK_DIR="$(mktemp -d)"
DATA_DIR="$WORK_DIR/data"
LOG_FILE="$WORK_DIR/server.log"
COOKIE_JAR="$WORK_DIR/cookies.txt"
RUNTIME_CONFIG_FILE="$WORK_DIR/config.json"
SERVER_USE_SETSID=0

cleanup() {
  if [[ -n "${FEED_PRIMARY_PID:-}" ]]; then
    kill "$FEED_PRIMARY_PID" 2>/dev/null || true
  fi
  if [[ -n "${FEED_BACKUP_PID:-}" ]]; then
    kill "$FEED_BACKUP_PID" 2>/dev/null || true
  fi
  if [[ -n "${SERVER_PID:-}" ]]; then
    if [[ "${SERVER_USE_SETSID:-0}" == "1" ]]; then
      kill -- -"$SERVER_PID" 2>/dev/null || true
    else
      kill "$SERVER_PID" 2>/dev/null || true
    fi
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Missing fixture: $TEMPLATE_FILE" >&2
  exit 1
fi

./configure.sh
make

# Randomize ports to avoid collisions on shared servers.
if [[ -z "${MC_GROUP:-}" ]]; then
  MC_GROUP="127.0.0.1"
fi
BASE_PORT="${BASE_PORT:-$((21000 + (RANDOM % 20000)))}"
IN_PRIMARY_PORT="${IN_PRIMARY_PORT:-$BASE_PORT}"
IN_BACKUP_PORT="${IN_BACKUP_PORT:-$((BASE_PORT + 1))}"
OUT1_PORT="${OUT1_PORT:-$((BASE_PORT + 40))}"
OUT2_PORT="${OUT2_PORT:-$((BASE_PORT + 41))}"

echo "smoke_transcode_seamless_failover: group=$MC_GROUP in_primary=$IN_PRIMARY_PORT in_backup=$IN_BACKUP_PORT out1=$OUT1_PORT out2=$OUT2_PORT port=$PORT" >&2

export TEMPLATE_FILE RUNTIME_CONFIG_FILE STREAM_ID SRC_PRIMARY_ID SRC_BACKUP_ID MC_GROUP IN_PRIMARY_PORT IN_BACKUP_PORT OUT1_PORT OUT2_PORT
python3 - <<'PY'
import json, os

template = os.environ["TEMPLATE_FILE"]
out_path = os.environ["RUNTIME_CONFIG_FILE"]
group = os.environ["MC_GROUP"]
in_primary = int(os.environ["IN_PRIMARY_PORT"])
in_backup = int(os.environ["IN_BACKUP_PORT"])
out1 = int(os.environ["OUT1_PORT"])
out2 = int(os.environ["OUT2_PORT"])
stream_id = os.environ["STREAM_ID"]
src_primary_id = os.environ["SRC_PRIMARY_ID"]
src_backup_id = os.environ["SRC_BACKUP_ID"]

cfg = json.load(open(template, "r", encoding="utf-8"))
rows = cfg.get("make_stream") or []
for row in rows:
    rid = row.get("id")
    if rid == src_primary_id:
        row["input"] = [f"udp://{group}:{in_primary}?reuse=1"]
        row["enable"] = True
    elif rid == src_backup_id:
        row["input"] = [f"udp://{group}:{in_backup}?reuse=1"]
        row["enable"] = True
    elif rid == stream_id:
        row["enable"] = True
        row["input"] = [f"stream://{src_primary_id}", f"stream://{src_backup_id}"]
        tc = row.get("transcode") or {}
        outs = tc.get("outputs") or []
        if len(outs) >= 2:
            outs[0]["url"] = f"udp://127.0.0.1:{out1}?pkt_size=1316"
            outs[1]["url"] = f"udp://127.0.0.1:{out2}?pkt_size=1316"

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
PY

SERVER_CMD=( ./stream scripts/server.lua -p "$PORT" --data-dir "$DATA_DIR" --web-dir "$WEB_DIR" --config "$RUNTIME_CONFIG_FILE" )
if command -v setsid >/dev/null 2>&1; then
  setsid "${SERVER_CMD[@]}" >"$LOG_FILE" 2>&1 &
  SERVER_USE_SETSID=1
else
  "${SERVER_CMD[@]}" >"$LOG_FILE" 2>&1 &
fi
SERVER_PID=$!

SERVER_READY=0
for _ in $(seq 1 40); do
  if curl -fsS "http://127.0.0.1:${PORT}/index.html" >/dev/null 2>&1; then
    SERVER_READY=1
    break
  fi
  sleep 0.5
done
if [[ "$SERVER_READY" -ne 1 ]]; then
  echo "Server did not start (port=$PORT)" >&2
  tail -n 200 "$LOG_FILE" >&2 || true
  exit 1
fi

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
"$FFMPEG_BIN" -hide_banner -loglevel error \
  -re -f lavfi -i testsrc=size=160x90:rate=25 \
  -re -f lavfi -i sine=frequency=1000 \
  -shortest -c:v mpeg2video -c:a mp2 \
  -f mpegts "udp://${MC_GROUP}:${IN_PRIMARY_PORT}?pkt_size=1316" >/dev/null 2>&1 &
FEED_PRIMARY_PID=$!

"$FFMPEG_BIN" -hide_banner -loglevel error \
  -re -f lavfi -i testsrc=size=160x90:rate=25 \
  -re -f lavfi -i sine=frequency=1200 \
  -shortest -c:v mpeg2video -c:a mp2 \
  -f mpegts "udp://${MC_GROUP}:${IN_BACKUP_PORT}?pkt_size=1316" >/dev/null 2>&1 &
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
    ANALYZE_PRE="$(./stream scripts/analyze.lua -n 2 udp://127.0.0.1:${OUT1_PORT} 2>/dev/null)"
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
    ANALYZE_POST="$(./stream scripts/analyze.lua -n 2 udp://127.0.0.1:${OUT1_PORT} 2>/dev/null)"
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
