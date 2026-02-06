#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${PORT:-}"
if [[ -z "${PORT}" ]]; then
  PORT="$((47000 + (RANDOM % 10000)))"
fi
WEB_DIR="${WEB_DIR:-$ROOT_DIR/web}"
STREAM_ID="${STREAM_ID:-transcode_per_output_isolation}"
TEMPLATE_FILE="${TEMPLATE_FILE:-$ROOT_DIR/fixtures/transcode_per_output_isolation.json}"

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
      # Kill the whole process group (server + any spawned ffmpeg/ffprobe).
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
BASE_PORT="${BASE_PORT:-$((22000 + (RANDOM % 20000)))}"
if [[ -z "${MC_GROUP:-}" ]]; then
  MC_GROUP="239.255.0.1"
fi
IN_PORT="${IN_PORT:-$BASE_PORT}"
OUT1_PORT="${OUT1_PORT:-$((BASE_PORT + 40))}"
OUT2_PORT="${OUT2_PORT:-$((BASE_PORT + 41))}"

echo "smoke_transcode_per_output_isolation: mc_group=$MC_GROUP in=$IN_PORT out1=$OUT1_PORT out2=$OUT2_PORT port=$PORT" >&2

export TEMPLATE_FILE RUNTIME_CONFIG_FILE STREAM_ID MC_GROUP IN_PORT OUT1_PORT OUT2_PORT
python3 - <<'PY'
import json, os

template = os.environ["TEMPLATE_FILE"]
out_path = os.environ["RUNTIME_CONFIG_FILE"]
group = os.environ["MC_GROUP"]
in_port = int(os.environ["IN_PORT"])
out1 = int(os.environ["OUT1_PORT"])
out2 = int(os.environ["OUT2_PORT"])

cfg = json.load(open(template, "r", encoding="utf-8"))
s = (cfg.get("make_stream") or [{}])[0]
s["id"] = os.environ.get("STREAM_ID") or s.get("id") or "transcode_per_output_isolation"
s["input"] = [f"udp://{group}:{in_port}"]

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
for _ in $(seq 1 30); do
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

# Unicast feed.
"$FFMPEG_BIN" -hide_banner -loglevel error -re \
  -f lavfi -i testsrc=size=160x90:rate=25 \
  -f lavfi -i sine=frequency=1000 \
  -shortest -c:v mpeg2video -c:a mp2 \
  -f mpegts "udp://${MC_GROUP}:${IN_PORT}?pkt_size=1316" >/dev/null 2>&1 &
FEED_PID=$!

# Wait for RUNNING.
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
  tail -n 200 "$LOG_FILE" >&2 || true
  exit 1
fi

WORKERS_OK=0
for _ in $(seq 1 30); do
  STATUS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/api/v1/transcode-status/${STREAM_ID}" "${AUTH_ARGS[@]}")"
  read -r OUT1_PID OUT1_STATE OUT2_PID OUT2_STATE <<<"$(STATUS_JSON="$STATUS_JSON" python3 - <<'PY'
import json, os
info = json.loads(os.environ.get("STATUS_JSON") or "{}")
workers = info.get("workers") or []
m = {}
for w in workers:
  idx = w.get("output_index")
  if isinstance(idx, int):
    m[idx] = w
def get(idx, key):
  w = m.get(idx) or {}
  v = w.get(key)
  return "" if v is None else str(v)
print(f"{get(1,'pid')} {get(1,'state')} {get(2,'pid')} {get(2,'state')}".strip())
PY
)"
  if [[ -n "${OUT1_PID:-}" && -n "${OUT2_PID:-}" && "${OUT1_STATE:-}" == "RUNNING" && "${OUT2_STATE:-}" == "RUNNING" ]]; then
    WORKERS_OK=1
    break
  fi
  sleep 1
done

if [[ "$WORKERS_OK" -ne 1 ]]; then
  echo "Transcode workers not RUNNING (stream_id=$STREAM_ID)" >&2
  echo "$STATUS_JSON" >&2
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
    tail -n 200 "$LOG_FILE" >&2 || true
    return 1
  fi
  return 0
}

wait_pat "udp://127.0.0.1:${OUT1_PORT}"
wait_pat "udp://127.0.0.1:${OUT2_PORT}"

echo "out1_pid=$OUT1_PID out2_pid=$OUT2_PID (killing out2 worker)" >&2

# Kill out2 worker and ensure out1 keeps running (fault isolation).
kill "$OUT2_PID" 2>/dev/null || true
wait "$OUT2_PID" 2>/dev/null || true

# Output #1 must remain valid.
wait_pat "udp://127.0.0.1:${OUT1_PORT}"

PID_OK=0
for _ in $(seq 1 10); do
  STATUS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/api/v1/transcode-status/${STREAM_ID}" "${AUTH_ARGS[@]}")"
  CUR_PID0="$(STATUS_JSON="$STATUS_JSON" python3 - <<'PY'
import json, os
info = json.loads(os.environ.get("STATUS_JSON") or "{}")
workers = info.get("workers") or []
for w in workers:
  if w.get("output_index") == 1:
    print(w.get("pid") or "")
    break
PY
)"
  if [[ "$CUR_PID0" == "$OUT1_PID" ]]; then
    PID_OK=1
    break
  fi
  sleep 1
done

if [[ "$PID_OK" -ne 1 ]]; then
  echo "Out1 worker PID changed after killing out2 worker (expected isolation)." >&2
  echo "$STATUS_JSON" >&2
  tail -n 200 "$LOG_FILE" >&2 || true
  exit 1
fi

# Output #2 should recover (worker restart).
wait_pat "udp://127.0.0.1:${OUT2_PORT}"

echo "OK: per-output isolation verified (out1 stayed up, out2 recovered)" >&2
