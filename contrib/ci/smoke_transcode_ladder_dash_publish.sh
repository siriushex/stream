#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${PORT:-}"
if [[ -z "${PORT}" ]]; then
  PORT="$((45000 + (RANDOM % 10000)))"
fi
WEB_DIR="${WEB_DIR:-$ROOT_DIR/web}"
STREAM_ID="${STREAM_ID:-transcode_ladder_dash_publish}"
SRC_ID="${SRC_ID:-src_udp}"
TEMPLATE_FILE="${TEMPLATE_FILE:-$ROOT_DIR/fixtures/transcode_ladder_dash_publish.json}"

WORK_DIR="$(mktemp -d)"
DATA_DIR="$WORK_DIR/data"
LOG_FILE="$WORK_DIR/server.log"
COOKIE_JAR="$WORK_DIR/cookies.txt"
RUNTIME_CONFIG_FILE="$WORK_DIR/config.json"
SERVER_USE_SETSID=0

cleanup() {
  if [[ -n "${FEED_PID:-}" ]]; then
    kill "$FEED_PID" 2>/dev/null || true
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

dump_debug() {
  echo "---- DEBUG ----" >&2
  if [[ -n "${PORT:-}" ]]; then
    echo "transcode-status: $STREAM_ID" >&2
    STATUS_JSON="$(curl -sS "http://127.0.0.1:${PORT}/api/v1/transcode-status/${STREAM_ID}" "${AUTH_ARGS[@]:-}" 2>/dev/null || true)"
    if [[ -n "$STATUS_JSON" ]]; then
      STATUS_JSON="$STATUS_JSON" python3 - <<'PY' || true
import json, os
payload = os.environ.get("STATUS_JSON") or ""
try:
  info = json.loads(payload)
except Exception as e:
  print("transcode-status: failed to parse:", e)
  print(payload[:400])
  raise SystemExit(0)
print("state:", info.get("state"))
print("publish_status:", info.get("publish_status"))
workers = info.get("profile_workers") or []
print("profile_workers:", len(workers))
for w in workers:
  print("worker:", w.get("index"), w.get("profile_id"), "pid=", w.get("pid"), "state=", w.get("state"), "out_ms=", w.get("last_out_time_ms"))
PY
    else
      echo "transcode-status: empty response" >&2
    fi
  fi
  echo "server log tail:" >&2
  tail -n 200 "$LOG_FILE" >&2 || true
}

cd "$ROOT_DIR"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Missing fixture: $TEMPLATE_FILE" >&2
  exit 1
fi

./configure.sh
make

if [[ -z "${MC_GROUP:-}" ]]; then
  MC_GROUP="127.0.0.1"
fi
BASE_PORT="${BASE_PORT:-$((21000 + (RANDOM % 20000)))}"
IN_PORT="${IN_PORT:-$BASE_PORT}"

echo "smoke_transcode_ladder_dash_publish: group=$MC_GROUP in=$IN_PORT port=$PORT" >&2

export TEMPLATE_FILE RUNTIME_CONFIG_FILE STREAM_ID SRC_ID MC_GROUP IN_PORT
python3 - <<'PY'
import json, os

template = os.environ["TEMPLATE_FILE"]
out_path = os.environ["RUNTIME_CONFIG_FILE"]
group = os.environ["MC_GROUP"]
in_port = int(os.environ["IN_PORT"])
stream_id = os.environ["STREAM_ID"]
src_id = os.environ["SRC_ID"]

cfg = json.load(open(template, "r", encoding="utf-8"))
rows = cfg.get("make_stream") or []
for row in rows:
    if row.get("id") == src_id:
        row["input"] = [f"udp://{group}:{in_port}?reuse=1"]
        row["enable"] = True
    if row.get("id") == stream_id:
        row["enable"] = True
        row["input"] = [f"stream://{src_id}"]

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
PY

SERVER_CMD=( ./astra scripts/server.lua -p "$PORT" --data-dir "$DATA_DIR" --web-dir "$WEB_DIR" --config "$RUNTIME_CONFIG_FILE" )
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
  if [[ ! -x "$FFMPEG_BIN" ]]; then
    echo "ffmpeg not found: $FFMPEG_BIN" >&2
    exit 1
  fi
fi

"$FFMPEG_BIN" -hide_banner -loglevel error \
  -re -f lavfi -i testsrc=size=640x360:rate=25 \
  -re -f lavfi -i sine=frequency=1000 \
  -shortest -c:v mpeg2video -c:a mp2 \
  -f mpegts "udp://${MC_GROUP}:${IN_PORT}?pkt_size=1316" >/dev/null 2>&1 &
FEED_PID=$!

STATE_OK=0
for _ in $(seq 1 25); do
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
  dump_debug
  exit 1
fi

MPD_URL="http://127.0.0.1:${PORT}/dash/${STREAM_ID}/manifest.mpd"

MPD_OK=0
MPD_BODY=""
for _ in $(seq 1 40); do
  set +e
  MPD_BODY="$(curl -fsS "$MPD_URL" "${AUTH_ARGS[@]}" 2>/dev/null)"
  CODE=$?
  set -e
  if [[ "$CODE" -eq 0 ]] && grep -q "<MPD" <<<"$MPD_BODY"; then
    MPD_OK=1
    break
  fi
  sleep 0.5
done
if [[ "$MPD_OK" -ne 1 ]]; then
  echo "DASH manifest not ready: $MPD_URL" >&2
  echo "$MPD_BODY" >&2 || true
  dump_debug
  exit 1
fi

DASH_DIR="$DATA_DIR/dash/$STREAM_ID"
if [[ ! -d "$DASH_DIR" ]]; then
  echo "DASH output dir missing: $DASH_DIR" >&2
  dump_debug
  exit 1
fi

SEG_FILE="$(ls -1 "$DASH_DIR"/*.m4s 2>/dev/null | head -n 1 || true)"
if [[ -z "$SEG_FILE" ]]; then
  echo "No DASH segments found in: $DASH_DIR" >&2
  ls -la "$DASH_DIR" >&2 || true
  dump_debug
  exit 1
fi

SEG_NAME="$(basename "$SEG_FILE")"
curl -fsS "http://127.0.0.1:${PORT}/dash/${STREAM_ID}/${SEG_NAME}" "${AUTH_ARGS[@]}" >/dev/null

echo "smoke_transcode_ladder_dash_publish: ok" >&2

