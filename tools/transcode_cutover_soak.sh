#!/usr/bin/env bash
set -euo pipefail

# Long-running warm-switch soak test for transcode seamless UDP proxy cutover.
#
# Usage examples:
#   tools/transcode_cutover_soak.sh
#   DURATION_SEC=7200 SWITCH_INTERVAL_SEC=120 tools/transcode_cutover_soak.sh
#
# Notes:
# - Uses multicast inputs by default (multiple receivers can bind).
# - Runs its own server + ffmpeg feeds in a temp work dir and cleans up on exit.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="${WEB_DIR:-$ROOT_DIR/web}"
TEMPLATE_FILE="${TEMPLATE_FILE:-$ROOT_DIR/fixtures/transcode_seamless_failover.json}"
STREAM_ID="${STREAM_ID:-transcode_cutover_soak}"

PORT="${PORT:-}"
if [[ -z "${PORT}" ]]; then
  PORT="$((49000 + (RANDOM % 10000)))"
fi

MC_GROUP="${MC_GROUP:-239.255.0.1}"
BASE_PORT="${BASE_PORT:-$((23000 + (RANDOM % 20000)))}"
IN_PRIMARY_PORT="${IN_PRIMARY_PORT:-$BASE_PORT}"
IN_BACKUP_PORT="${IN_BACKUP_PORT:-$((BASE_PORT + 1))}"
OUT1_PORT="${OUT1_PORT:-$((BASE_PORT + 40))}"
OUT2_PORT="${OUT2_PORT:-$((BASE_PORT + 41))}"

DURATION_SEC="${DURATION_SEC:-3600}"
SWITCH_INTERVAL_SEC="${SWITCH_INTERVAL_SEC:-300}"
RETURN_WAIT_SEC="${RETURN_WAIT_SEC:-15}"
CHECK_OUTPUT="${CHECK_OUTPUT:-1}"

WORK_DIR="$(mktemp -d)"
DATA_DIR="$WORK_DIR/data"
LOG_FILE="$WORK_DIR/server.log"
COOKIE_JAR="$WORK_DIR/cookies.txt"
RUNTIME_CONFIG_FILE="$WORK_DIR/config.json"
RESULTS_JSONL="$WORK_DIR/results.jsonl"
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
  echo "work_dir=$WORK_DIR"
  echo "server_log=$LOG_FILE"
  echo "results=$RESULTS_JSONL"
}
trap cleanup EXIT

cd "$ROOT_DIR"

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Missing fixture: $TEMPLATE_FILE" >&2
  exit 1
fi

./configure.sh
make

echo "transcode_cutover_soak: port=$PORT mc_group=$MC_GROUP in_primary=$IN_PRIMARY_PORT in_backup=$IN_BACKUP_PORT out1=$OUT1_PORT out2=$OUT2_PORT duration=$DURATION_SEC switch_interval=$SWITCH_INTERVAL_SEC" >&2

export TEMPLATE_FILE RUNTIME_CONFIG_FILE STREAM_ID MC_GROUP IN_PRIMARY_PORT IN_BACKUP_PORT OUT1_PORT OUT2_PORT
python3 - <<'PY'
import json, os

template = os.environ["TEMPLATE_FILE"]
out_path = os.environ["RUNTIME_CONFIG_FILE"]
group = os.environ["MC_GROUP"]
in_primary = int(os.environ["IN_PRIMARY_PORT"])
in_backup = int(os.environ["IN_BACKUP_PORT"])
out1 = int(os.environ["OUT1_PORT"])
out2 = int(os.environ["OUT2_PORT"])

cfg = json.load(open(template, "r", encoding="utf-8"))
s = (cfg.get("make_stream") or [{}])[0]
s["id"] = os.environ.get("STREAM_ID") or s.get("id") or "transcode_cutover_soak"
s["name"] = "Transcode Cutover Soak"
s["input"] = [f"udp://{group}:{in_primary}", f"udp://{group}:{in_backup}"]

tc = s.get("transcode") or {}
outs = tc.get("outputs") or []
if len(outs) >= 2:
  outs[0]["url"] = f"udp://127.0.0.1:{out1}?pkt_size=1316"
  outs[1]["url"] = f"udp://127.0.0.1:{out2}?pkt_size=1316"

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

# Primary and backup multicast feeds.
"$FFMPEG_BIN" -hide_banner -loglevel error -re \
  -f lavfi -i testsrc=size=160x90:rate=25 \
  -f lavfi -i sine=frequency=1000 \
  -shortest -c:v mpeg2video -c:a mp2 \
  -f mpegts "udp://${MC_GROUP}:${IN_PRIMARY_PORT}?pkt_size=1316" >/dev/null 2>&1 &
FEED_PRIMARY_PID=$!

"$FFMPEG_BIN" -hide_banner -loglevel error -re \
  -f lavfi -i testsrc=size=160x90:rate=25 \
  -f lavfi -i sine=frequency=1200 \
  -shortest -c:v mpeg2video -c:a mp2 \
  -f mpegts "udp://${MC_GROUP}:${IN_BACKUP_PORT}?pkt_size=1316" >/dev/null 2>&1 &
FEED_BACKUP_PID=$!

STATE_OK=0
for _ in $(seq 1 40); do
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

wait_pat() {
  local url="$1"
  local ok=0
  for _ in $(seq 1 10); do
    set +e
    local out
    out="$(./astra scripts/analyze.lua -n 2 "$url" 2>/dev/null)"
    set -e
    if grep -q "PAT:" <<<"$out"; then
      ok=1
      break
    fi
    sleep 1
  done
  if [[ "$ok" -ne 1 ]]; then
    echo "No PAT detected on $url" >&2
    return 1
  fi
  return 0
}

if [[ "$CHECK_OUTPUT" == "1" ]]; then
  wait_pat "udp://127.0.0.1:${OUT1_PORT}"
fi

NOW="$(date +%s)"
END="$((NOW + DURATION_SEC))"
ITER=0
LAST_SINCE="$NOW"
LAST_ALERT_ID=0

echo '{"ts":'"$NOW"',"event":"start","port":'"$PORT"',"stream_id":"'"$STREAM_ID"'"}' >>"$RESULTS_JSONL"

while [[ "$(date +%s)" -lt "$END" ]]; do
  ITER=$((ITER + 1))
  TS0="$(date +%s)"

  # 1) Kill primary and wait for cutover OK.
  if [[ -n "${FEED_PRIMARY_PID:-}" ]]; then
    kill "$FEED_PRIMARY_PID" 2>/dev/null || true
    wait "$FEED_PRIMARY_PID" 2>/dev/null || true
    unset FEED_PRIMARY_PID
  fi

  CUTOVER_OK=0
  CUTOVER_TS=""
  CUTOVER_ALERT_ID=""
  CUTOVER_ID=""
  CUTOVER_DUR_SEC=""
  CUTOVER_READY_SEC=""
  CUTOVER_STABLE_OK_SEC=""
  for _ in $(seq 1 40); do
    ALERTS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/api/v1/alerts?stream_id=${STREAM_ID}&code=TRANSCODE_CUTOVER_OK&since=${LAST_SINCE}&limit=50" "${AUTH_ARGS[@]}")"
    IFS=$'\t' read -r FOUND CUTOVER_ALERT_ID CUTOVER_TS CUTOVER_ID CUTOVER_DUR_SEC CUTOVER_READY_SEC CUTOVER_STABLE_OK_SEC <<<"$(ALERTS_JSON="$ALERTS_JSON" LAST_ID="$LAST_ALERT_ID" python3 - <<'PY'
import json, os
rows = json.loads(os.environ.get("ALERTS_JSON") or "[]") or []
last_id = int(os.environ.get("LAST_ID") or "0")
best = None
best_id = 0
for r in rows:
  try:
    rid = int(r.get("id") or 0)
  except Exception:
    rid = 0
  if rid > last_id and rid > best_id:
    best = r
    best_id = rid

if not best:
  print("0\t\t\t\t\t\t")
  raise SystemExit(0)

meta = best.get("meta") or {}
print("1\t%s\t%s\t%s\t%s\t%s\t%s" % (
  str(best.get("id") or ""),
  str(best.get("ts") or ""),
  str(meta.get("cutover_id") or ""),
  str(meta.get("duration_sec") or ""),
  str(meta.get("ready_sec") or ""),
  str(meta.get("stable_ok_sec") or ""),
))
PY
)"
    if [[ "${FOUND:-0}" -gt 0 ]]; then
      CUTOVER_OK=1
      break
    fi
    sleep 1
  done

  TS1="$(date +%s)"
  echo '{"ts":'"$TS1"',"iter":'"$ITER"',"event":"failover","ok":'"$CUTOVER_OK"',"wait_sec":'"$((TS1-TS0))"',"alert_id":"'"$CUTOVER_ALERT_ID"'","cutover_ts":"'"$CUTOVER_TS"'","cutover_id":"'"$CUTOVER_ID"'","duration_sec":"'"$CUTOVER_DUR_SEC"'","ready_sec":"'"$CUTOVER_READY_SEC"'","stable_ok_sec":"'"$CUTOVER_STABLE_OK_SEC"'"}' >>"$RESULTS_JSONL"
  if [[ "$CUTOVER_OK" -ne 1 ]]; then
    echo "FAIL: no cutover OK after primary stop (iter=$ITER)" >&2
    tail -n 200 "$LOG_FILE" >&2 || true
    exit 1
  fi
  if [[ -n "${CUTOVER_ALERT_ID:-}" ]]; then
    LAST_ALERT_ID="$CUTOVER_ALERT_ID"
  fi
  LAST_SINCE="$TS1"

  # 2) Bring primary back, wait a bit for return cutover (optional).
  "$FFMPEG_BIN" -hide_banner -loglevel error -re \
    -f lavfi -i testsrc=size=160x90:rate=25 \
    -f lavfi -i sine=frequency=1000 \
    -shortest -c:v mpeg2video -c:a mp2 \
    -f mpegts "udp://${MC_GROUP}:${IN_PRIMARY_PORT}?pkt_size=1316" >/dev/null 2>&1 &
  FEED_PRIMARY_PID=$!

  RETURN_OK=0
  RETURN_ALERT_ID=""
  RETURN_TS=""
  RETURN_CUTOVER_ID=""
  for _ in $(seq 1 "$RETURN_WAIT_SEC"); do
    ALERTS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/api/v1/alerts?stream_id=${STREAM_ID}&code=TRANSCODE_CUTOVER_OK&since=${LAST_SINCE}&limit=50" "${AUTH_ARGS[@]}")"
    IFS=$'\t' read -r FOUND RETURN_ALERT_ID RETURN_TS RETURN_CUTOVER_ID _REST <<<"$(ALERTS_JSON="$ALERTS_JSON" LAST_ID="$LAST_ALERT_ID" python3 - <<'PY'
import json, os
rows = json.loads(os.environ.get("ALERTS_JSON") or "[]") or []
last_id = int(os.environ.get("LAST_ID") or "0")
best = None
best_id = 0
for r in rows:
  try:
    rid = int(r.get("id") or 0)
  except Exception:
    rid = 0
  if rid > last_id and rid > best_id:
    best = r
    best_id = rid

if not best:
  print("0\t\t\t\t")
  raise SystemExit(0)

meta = best.get("meta") or {}
print("1\t%s\t%s\t%s\t" % (
  str(best.get("id") or ""),
  str(best.get("ts") or ""),
  str(meta.get("cutover_id") or ""),
))
PY
)"
    if [[ "${FOUND:-0}" -gt 0 ]]; then
      RETURN_OK=1
      break
    fi
    sleep 1
  done

  TS2="$(date +%s)"
  echo '{"ts":'"$TS2"',"iter":'"$ITER"',"event":"return","ok":'"$RETURN_OK"',"wait_sec":'"$((TS2-TS1))"',"alert_id":"'"$RETURN_ALERT_ID"'","cutover_ts":"'"$RETURN_TS"'","cutover_id":"'"$RETURN_CUTOVER_ID"'"}' >>"$RESULTS_JSONL"
  if [[ "$RETURN_OK" -eq 1 && -n "${RETURN_ALERT_ID:-}" ]]; then
    LAST_ALERT_ID="$RETURN_ALERT_ID"
  fi
  LAST_SINCE="$TS2"

  if [[ "$CHECK_OUTPUT" == "1" ]]; then
    wait_pat "udp://127.0.0.1:${OUT1_PORT}"
  fi

  sleep "$SWITCH_INTERVAL_SEC"
done

echo '{"ts":'"$(date +%s)"',"event":"done","iters":'"$ITER"'}' >>"$RESULTS_JSONL"
