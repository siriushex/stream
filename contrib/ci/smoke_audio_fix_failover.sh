#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${PORT:-9077}"
WEB_DIR="${WEB_DIR:-$ROOT_DIR/web}"
STREAM_ID="${STREAM_ID:-audio_fix_failover}"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/fixtures/audio_fix_failover.json}"

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
FFPROBE_BIN="$(TOOLS_JSON="$TOOLS_JSON" python3 - <<'PY'
import json, os
info = json.loads(os.environ.get("TOOLS_JSON") or "{}")
print(info.get("ffprobe_path_resolved") or "ffprobe")
PY
)"

for BIN in "$FFMPEG_BIN" "$FFPROBE_BIN"; do
  if ! command -v "$BIN" >/dev/null 2>&1; then
    if [[ ! -x "$BIN" ]]; then
      echo "tool not found: $BIN" >&2
      exit 1
    fi
  fi
done

# Primary feed: AAC 48k stereo.
"$FFMPEG_BIN" -hide_banner -loglevel error -re \
  -f lavfi -i testsrc=size=160x90:rate=25 \
  -f lavfi -i sine=frequency=1000:sample_rate=48000 \
  -shortest -c:v mpeg2video -c:a aac -b:a 128k -ac 2 -ar 48000 \
  -f mpegts "udp://239.255.0.10:12400?pkt_size=1316&ttl=1" >/dev/null 2>&1 &
FEED_PRIMARY_PID=$!

# Backup feed: AAC 44.1k stereo (same type 0x0F but different params).
"$FFMPEG_BIN" -hide_banner -loglevel error -re \
  -f lavfi -i testsrc=size=160x90:rate=25 \
  -f lavfi -i sine=frequency=1200:sample_rate=44100 \
  -shortest -c:v mpeg2video -c:a aac -b:a 96k -ac 2 -ar 44100 \
  -f mpegts "udp://239.255.0.10:12401?pkt_size=1316&ttl=1" >/dev/null 2>&1 &
FEED_BACKUP_PID=$!

wait_for_effective_mode() {
  local expected="$1"
  local tries="${2:-30}"
  for _ in $(seq 1 "$tries"); do
    STATUS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/api/v1/stream-status/${STREAM_ID}" "${AUTH_ARGS[@]}")"
    read -r ACTIVE MODE STATE < <(STATUS_JSON="$STATUS_JSON" python3 - <<'PY'
import json, os
st = json.loads(os.environ.get("STATUS_JSON") or "{}")
active = st.get("active_input_index")
outs = st.get("outputs_status") or []
out0 = outs[0] if outs else {}
mode = out0.get("audio_fix_effective_mode") or ""
state = out0.get("audio_fix_state") or ""
print(active if active is not None else -1, mode, state)
PY
)
    if [[ "$MODE" == "$expected" && "$STATE" == "RUNNING" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

probe_output_audio() {
  local tries="${1:-10}"
  for _ in $(seq 1 "$tries"); do
    if FFPROBE_BIN="$FFPROBE_BIN" python3 - <<'PY'
import json, os, subprocess, sys
bin = os.environ["FFPROBE_BIN"]
url = "udp://239.255.0.10:12410?fifo_size=1000000&overrun_nonfatal=1"
try:
    cp = subprocess.run(
        [bin, "-v", "error", "-print_format", "json", "-show_streams", "-select_streams", "a:0", url],
        capture_output=True, text=True, timeout=5,
    )
except subprocess.TimeoutExpired:
    sys.exit(2)
if cp.returncode != 0:
    sys.exit(2)
data = json.loads(cp.stdout or "{}")
streams = data.get("streams") or []
if not streams:
    sys.exit(2)
s = streams[0]
codec = (s.get("codec_name") or "").strip()
sr = int(s.get("sample_rate") or 0)
ch = int(s.get("channels") or 0)
if codec != "aac" or sr != 48000 or ch != 2:
    sys.exit(1)
PY
    then
      return 0
    fi
    sleep 1
  done
  return 1
}

# Wait for auto-mode to settle into copy on primary.
if ! wait_for_effective_mode "copy" 40; then
  echo "audio_fix did not reach effective_mode=copy on primary" >&2
  tail -n 200 "$LOG_FILE" >&2 || true
  exit 1
fi

if ! probe_output_audio 10; then
  echo "output audio is not AAC 48k stereo on primary" >&2
  tail -n 200 "$LOG_FILE" >&2 || true
  exit 1
fi

kill "$FEED_PRIMARY_PID" 2>/dev/null || true
wait "$FEED_PRIMARY_PID" 2>/dev/null || true
unset FEED_PRIMARY_PID

# After failover, we expect transcode mode (aac).
if ! wait_for_effective_mode "aac" 50; then
  echo "audio_fix did not reach effective_mode=aac on backup" >&2
  tail -n 200 "$LOG_FILE" >&2 || true
  exit 1
fi

if ! probe_output_audio 10; then
  echo "output audio is not AAC 48k stereo on backup" >&2
  tail -n 200 "$LOG_FILE" >&2 || true
  exit 1
fi
