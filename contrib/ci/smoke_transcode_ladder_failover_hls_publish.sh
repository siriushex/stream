#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${PORT:-}"
if [[ -z "${PORT}" ]]; then
  PORT="$((45000 + (RANDOM % 10000)))"
fi
WEB_DIR="${WEB_DIR:-$ROOT_DIR/web}"
STREAM_ID="${STREAM_ID:-transcode_ladder_failover_hls_publish}"
SRC_PRIMARY_ID="${SRC_PRIMARY_ID:-src_udp_primary}"
SRC_BACKUP_ID="${SRC_BACKUP_ID:-src_udp_backup}"
TEMPLATE_FILE="${TEMPLATE_FILE:-$ROOT_DIR/fixtures/transcode_ladder_failover_hls_publish.json}"

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
print("active_input_id:", info.get("active_input_id"))
print("last_alert:", info.get("last_alert"))
print("profiles_status:", info.get("profiles_status"))
PY
    fi
  fi
  echo "server log tail:" >&2
  tail -n 250 "$LOG_FILE" >&2 || true
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
IN_PRIMARY_PORT="${IN_PRIMARY_PORT:-$BASE_PORT}"
IN_BACKUP_PORT="${IN_BACKUP_PORT:-$((BASE_PORT + 1))}"

echo "smoke_transcode_ladder_failover_hls_publish: group=$MC_GROUP in_primary=$IN_PRIMARY_PORT in_backup=$IN_BACKUP_PORT port=$PORT" >&2

export TEMPLATE_FILE RUNTIME_CONFIG_FILE STREAM_ID SRC_PRIMARY_ID SRC_BACKUP_ID MC_GROUP IN_PRIMARY_PORT IN_BACKUP_PORT
python3 - <<'PY'
import json, os

template = os.environ["TEMPLATE_FILE"]
out_path = os.environ["RUNTIME_CONFIG_FILE"]
group = os.environ["MC_GROUP"]
in_primary = int(os.environ["IN_PRIMARY_PORT"])
in_backup = int(os.environ["IN_BACKUP_PORT"])
stream_id = os.environ["STREAM_ID"]
src_primary = os.environ["SRC_PRIMARY_ID"]
src_backup = os.environ["SRC_BACKUP_ID"]

cfg = json.load(open(template, "r", encoding="utf-8"))
rows = cfg.get("make_stream") or []
for row in rows:
    if row.get("id") == src_primary:
        row["input"] = [f"udp://{group}:{in_primary}?reuse=1"]
        row["enable"] = True
    if row.get("id") == src_backup:
        row["input"] = [f"udp://{group}:{in_backup}?reuse=1"]
        row["enable"] = True
    if row.get("id") == stream_id:
        row["enable"] = True
        row["input"] = [f"stream://{src_primary}", f"stream://{src_backup}"]

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
  if [[ ! -x "$FFMPEG_BIN" ]]; then
    echo "ffmpeg not found: $FFMPEG_BIN" >&2
    exit 1
  fi
fi

"$FFMPEG_BIN" -hide_banner -loglevel error \
  -re -f lavfi -i testsrc=size=640x360:rate=25 \
  -re -f lavfi -i sine=frequency=1000 \
  -shortest -c:v mpeg2video -c:a mp2 \
  -f mpegts "udp://${MC_GROUP}:${IN_PRIMARY_PORT}?pkt_size=1316" >/dev/null 2>&1 &
FEED_PRIMARY_PID=$!

"$FFMPEG_BIN" -hide_banner -loglevel error \
  -re -f lavfi -i testsrc=size=640x360:rate=25 \
  -re -f lavfi -i sine=frequency=1200 \
  -shortest -c:v mpeg2video -c:a mp2 \
  -f mpegts "udp://${MC_GROUP}:${IN_BACKUP_PORT}?pkt_size=1316" >/dev/null 2>&1 &
FEED_BACKUP_PID=$!

STATE_OK=0
for _ in $(seq 1 30); do
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

check_ts_file() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys
path = sys.argv[1]
data = open(path, "rb").read(188 * 20)
if len(data) < 188 * 5:
  print("not enough data:", len(data))
  sys.exit(1)
ok = False
for off in range(188):
  good = True
  for i in range(5):
    idx = off + i * 188
    if idx >= len(data) or data[idx] != 0x47:
      good = False
      break
  if good:
    ok = True
    break
if not ok:
  print("no TS sync found")
  sys.exit(1)
PY
}

fetch_live() {
  local profile_id="$1"
  local out_file="$WORK_DIR/live_${profile_id}.ts"
  # Keep a small HTTP upstream buffer so the client starts receiving quickly.
  local live_url="http://127.0.0.1:${PORT}/live/${STREAM_ID}~${profile_id}.ts?internal=1&buf_kb=256&buf_fill_kb=16"
  # /live is an endless stream. curl may exit with 28 (timeout) even when it received data.
  local ok=0
  for _ in $(seq 1 25); do
    rm -f "$out_file" 2>/dev/null || true
    set +e
    curl -fsS "$live_url" --max-time 3 --output "$out_file" 2>/dev/null
    local code=$?
    set -e

    if [[ "$code" -ne 0 && "$code" -ne 28 ]]; then
      sleep 0.5
      continue
    fi
    if [[ -f "$out_file" ]]; then
      if check_ts_file "$out_file"; then
        ok=1
        break
      fi
    fi
    sleep 0.5
  done

  if [[ "$ok" -ne 1 ]]; then
    echo "LIVE not ready ($profile_id): $live_url" >&2
    dump_debug
    return 1
  fi
}

MASTER_URL="http://127.0.0.1:${PORT}/hls/${STREAM_ID}/index.m3u8"

MASTER_OK=0
for _ in $(seq 1 25); do
  set +e
  MASTER_BODY="$(curl -fsS "$MASTER_URL" "${AUTH_ARGS[@]}" 2>/dev/null)"
  CODE=$?
  set -e
  if [[ "$CODE" -eq 0 ]] && grep -q "#EXT-X-STREAM-INF" <<<"$MASTER_BODY"; then
    MASTER_OK=1
    break
  fi
  sleep 0.5
done
if [[ "$MASTER_OK" -ne 1 ]]; then
  echo "Master playlist not ready: $MASTER_URL" >&2
  dump_debug
  exit 1
fi

VARIANTS=(HDHigh HDMed)
for pid in "${VARIANTS[@]}"; do
  VAR_URL="http://127.0.0.1:${PORT}/hls/${STREAM_ID}~${pid}/index.m3u8"
  VAR_OK=0
  for _ in $(seq 1 40); do
    set +e
    VAR_BODY="$(curl -fsS "$VAR_URL" "${AUTH_ARGS[@]}" 2>/dev/null)"
    CODE=$?
    set -e
    if [[ "$CODE" -eq 0 ]] && grep -q "#EXTINF" <<<"$VAR_BODY"; then
      VAR_OK=1
      break
    fi
    sleep 0.5
  done
  if [[ "$VAR_OK" -ne 1 ]]; then
    echo "Variant playlist not ready ($pid): $VAR_URL" >&2
    dump_debug
    exit 1
  fi
done

fetch_live "HDHigh"

kill "$FEED_PRIMARY_PID" 2>/dev/null || true
wait "$FEED_PRIMARY_PID" 2>/dev/null || true
unset FEED_PRIMARY_PID

CUTOVER_OK=0
for _ in $(seq 1 80); do
  STATUS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/api/v1/transcode-status/${STREAM_ID}" "${AUTH_ARGS[@]}")"
  RESULT="$(STATUS_JSON="$STATUS_JSON" python3 - <<'PY'
import json, os
payload = os.environ.get("STATUS_JSON") or ""
try:
  info = json.loads(payload)
except Exception:
  print("ERR|0")
  raise SystemExit(0)

active = info.get("active_input_id")
profiles = info.get("profiles_status") or []
cut_ok = True
for p in profiles:
  c = p.get("last_cutover")
  if not c or c.get("state") != "OK" or c.get("target_input_id") != 2:
    cut_ok = False
    break
print(f"{active}|{1 if cut_ok else 0}")
PY
)"
  ACTIVE_ID="${RESULT%%|*}"
  CUT_OK="${RESULT##*|}"
  if [[ "${ACTIVE_ID:-}" == "2" && "${CUT_OK:-0}" == "1" ]]; then
    CUTOVER_OK=1
    break
  fi
  sleep 1
done
if [[ "$CUTOVER_OK" -ne 1 ]]; then
  echo "Expected cutover to backup input (#2), but it did not complete in time." >&2
  dump_debug
  exit 1
fi

fetch_live "HDHigh"

# HLS should still be readable after cutover.
for pid in "${VARIANTS[@]}"; do
  VAR_URL="http://127.0.0.1:${PORT}/hls/${STREAM_ID}~${pid}/index.m3u8"
  VAR_BODY="$(curl -fsS "$VAR_URL" "${AUTH_ARGS[@]}")"
  if ! grep -q "#EXTINF" <<<"$VAR_BODY"; then
    echo "Variant playlist missing EXTINF after cutover ($pid): $VAR_URL" >&2
    dump_debug
    exit 1
  fi
done

echo "smoke_transcode_ladder_failover_hls_publish: ok" >&2
