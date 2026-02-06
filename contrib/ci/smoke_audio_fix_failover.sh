#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${PORT:-}"
if [[ -z "${PORT}" ]]; then
  PORT="$((46000 + (RANDOM % 10000)))"
fi
WEB_DIR="${WEB_DIR:-$ROOT_DIR/web}"
STREAM_ID="${STREAM_ID:-audio_fix_failover}"
TEMPLATE_FILE="${TEMPLATE_FILE:-$ROOT_DIR/fixtures/audio_fix_failover.json}"

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

# Use randomized ports to avoid collisions with existing traffic on shared servers.
# Keep the multicast group stable by default because some environments are picky about local multicast routing.
if [[ -z "${MC_GROUP:-}" ]]; then
  if [[ "${RANDOMIZE_GROUP:-0}" == "1" ]]; then
    # Avoid x.x.0.0/255.* and other edge cases by using 1..254 for octets.
    MC_GROUP="239.255.$((1 + (RANDOM % 254))).$((1 + (RANDOM % 254)))"
  else
    MC_GROUP="239.255.0.10"
  fi
fi
BASE_PORT="${BASE_PORT:-$((20000 + (RANDOM % 20000)))}"
IN_PRIMARY_PORT="${IN_PRIMARY_PORT:-$BASE_PORT}"
IN_BACKUP_PORT="${IN_BACKUP_PORT:-$((BASE_PORT + 1))}"
OUT_PORT="${OUT_PORT:-$((BASE_PORT + 10))}"

OUT_ADDR="${OUT_ADDR:-127.0.0.1}"
echo "smoke_audio_fix_failover: mc_group=$MC_GROUP in_primary=$IN_PRIMARY_PORT in_backup=$IN_BACKUP_PORT out=${OUT_ADDR}:${OUT_PORT} port=$PORT" >&2

export TEMPLATE_FILE RUNTIME_CONFIG_FILE STREAM_ID MC_GROUP IN_PRIMARY_PORT IN_BACKUP_PORT OUT_ADDR OUT_PORT
python3 - <<'PY'
import json, os

template = os.environ["TEMPLATE_FILE"]
out_path = os.environ["RUNTIME_CONFIG_FILE"]
group = os.environ["MC_GROUP"]
out_addr = os.environ.get("OUT_ADDR") or "127.0.0.1"
in_primary = int(os.environ["IN_PRIMARY_PORT"])
in_backup = int(os.environ["IN_BACKUP_PORT"])
out_port = int(os.environ["OUT_PORT"])

cfg = json.load(open(template, "r", encoding="utf-8"))
s = (cfg.get("make_stream") or [{}])[0]
s["id"] = os.environ.get("STREAM_ID") or s.get("id") or "audio_fix_failover"
s["input"] = [f"udp://{group}:{in_primary}", f"udp://{group}:{in_backup}"]
out = (s.get("output") or [{}])[0]
out["addr"] = out_addr
out["port"] = out_port
af = out.get("audio_fix") or {}
# Don't start an internal output probe for this smoke: we need a single local receiver for UDP unicast.
af["probe_interval_sec"] = 0
out["audio_fix"] = af

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
  -f mpegts "udp://${MC_GROUP}:${IN_PRIMARY_PORT}?pkt_size=1316&ttl=1" >/dev/null 2>&1 &
FEED_PRIMARY_PID=$!

# Backup feed: AAC 44.1k stereo (same type 0x0F but different params).
"$FFMPEG_BIN" -hide_banner -loglevel error -re \
  -f lavfi -i testsrc=size=160x90:rate=25 \
  -f lavfi -i sine=frequency=1200:sample_rate=44100 \
  -shortest -c:v mpeg2video -c:a aac -b:a 96k -ac 2 -ar 44100 \
  -f mpegts "udp://${MC_GROUP}:${IN_BACKUP_PORT}?pkt_size=1316&ttl=1" >/dev/null 2>&1 &
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
    if FFMPEG_BIN="$FFMPEG_BIN" python3 - <<'PY'
import os, subprocess, sys

bin = os.environ["FFMPEG_BIN"]
group = os.environ.get("OUT_ADDR") or "127.0.0.1"
port = int(os.environ.get("OUT_PORT") or "12410")
url = f"udp://{group}:{port}?fifo_size=1000000&overrun_nonfatal=1"

argv = [
    bin,
    "-hide_banner",
    "-nostats",
    "-loglevel", "info",
    "-i", url,
    "-t", "0.5",
    "-map", "0:a:0?",
    "-vn",
    "-f", "null",
    "-",
]

try:
    cp = subprocess.run(argv, capture_output=True, text=True, timeout=6)
except subprocess.TimeoutExpired:
    sys.exit(2)

text = (cp.stderr or "") + "\n" + (cp.stdout or "")
audio_lines = [ln for ln in text.splitlines() if "Audio:" in ln]
if not audio_lines:
    sys.exit(2)

line = audio_lines[0]
ok = ("Audio: aac" in line) and ("48000 Hz" in line) and (("stereo" in line) or ("2 channels" in line))
if not ok:
    print(f"probe audio line: {line}", file=sys.stderr)
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
