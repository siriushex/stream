#!/bin/sh
set -eu

for cmd in ffmpeg ffprobe python3 curl; do
    command -v "$cmd" >/dev/null 2>&1 || {
        printf '%s\n' "missing dependency: $cmd" >&2
        exit 1
    }
done

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stream-buffer-av.XXXXXX")
BASE_PORT=$((21000 + ($$ % 1000) * 3))
PRIMARY_PORT=$BASE_PORT
BACKUP_PORT=$((BASE_PORT + 1))
OUTPUT_PORT=$((BASE_PORT + 2))
DROP_AUDIO_FLAG="$ROOT/drop-primary-audio"
STATUS_PATH="$ROOT/status.json"
PIDS=""

cleanup() {
    for pid in $PIDS; do
        kill "$pid" >/dev/null 2>&1 || true
    done
    wait >/dev/null 2>&1 || true
    rm -rf "$ROOT"
}
trap cleanup EXIT INT TERM

ffmpeg -hide_banner -loglevel error \
    -f lavfi -i testsrc=size=320x180:rate=25 \
    -f lavfi -i sine=frequency=700:sample_rate=48000 \
    -t 12 -c:v mpeg2video -g 25 -c:a mp2 -b:a 128k \
    -muxrate 1200k -f mpegts "$ROOT/primary.ts"
ffmpeg -hide_banner -loglevel error \
    -f lavfi -i color=c=blue:size=320x180:rate=25 \
    -f lavfi -i sine=frequency=1200:sample_rate=48000 \
    -t 12 -c:v mpeg2video -g 25 -c:a mp2 -b:a 128k \
    -muxrate 1200k -f mpegts "$ROOT/backup.ts"

PRIMARY_AUDIO_HEX=$(ffprobe -v error -select_streams a:0 \
    -show_entries stream=id -of default=nw=1:nk=1 "$ROOT/primary.ts" | sed -n '1p')
PRIMARY_AUDIO_PID=$(python3 - "$PRIMARY_AUDIO_HEX" <<'PY'
import sys
print(int(sys.argv[1], 0))
PY
)

python3 tools/loop_ts_http.py \
    --file "$ROOT/primary.ts" --port "$PRIMARY_PORT" --bitrate-kbps 1200 \
    --drop-audio-pid "$PRIMARY_AUDIO_PID" --drop-audio-flag "$DROP_AUDIO_FLAG" \
    >"$ROOT/primary.log" 2>&1 &
PIDS="$PIDS $!"
python3 tools/loop_ts_http.py \
    --file "$ROOT/backup.ts" --port "$BACKUP_PORT" --bitrate-kbps 1200 \
    >"$ROOT/backup.log" 2>&1 &
PIDS="$PIDS $!"

BUFFER_PRIMARY_PORT=$PRIMARY_PORT \
BUFFER_BACKUP_PORT=$BACKUP_PORT \
BUFFER_OUTPUT_PORT=$OUTPUT_PORT \
BUFFER_STATUS_PATH=$STATUS_PATH \
    ./stream scripts/tests/buffer_av_health_canary.lua \
    >"$ROOT/stream.log" 2>&1 &
PIDS="$PIDS $!"

wait_state() {
    mode=$1
    limit=$2
    count=0
    while [ "$count" -lt "$limit" ]; do
        if [ -s "$STATUS_PATH" ] && python3 - "$STATUS_PATH" "$mode" <<'PY'
import json
import sys

try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    raise SystemExit(1)
mode = sys.argv[2]
inputs = data.get("inputs") or []
health = data.get("health") or {}
active = data.get("active_input_index")
if mode == "primary_ok":
    ok = active == 0 and health.get("current_ok") is True
    ok = ok and inputs and int(inputs[0].get("video_pid") or 0) > 0
    ok = ok and int(inputs[0].get("audio_pid") or 0) > 0
elif mode == "no_audio":
    ok = health.get("reason") == "no_audio"
elif mode == "backup_ok":
    ok = active == 1 and health.get("current_ok") is True
elif mode == "primary_recovered":
    ok = active == 0 and health.get("current_ok") is True
else:
    ok = False
raise SystemExit(0 if ok else 1)
PY
        then
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    printf '%s\n' "timed out waiting for state: $mode" >&2
    [ -f "$STATUS_PATH" ] && sed -n '1,20p' "$STATUS_PATH" >&2 || true
    sed -n '1,160p' "$ROOT/stream.log" >&2 || true
    return 1
}

wait_state primary_ok 20

ffmpeg -hide_banner -loglevel error -y \
    -i "http://127.0.0.1:$OUTPUT_PORT/canary" -t 22 -c copy "$ROOT/output.ts" \
    >"$ROOT/ffmpeg.log" 2>&1 &
FFMPEG_PID=$!
PIDS="$PIDS $FFMPEG_PID"

touch "$DROP_AUDIO_FLAG"
FAILURE_STARTED=$(date +%s)
wait_state no_audio 10
wait_state backup_ok 12
FAILOVER_ELAPSED=$(($(date +%s) - FAILURE_STARTED))
[ "$FAILOVER_ELAPSED" -ge 3 ] || {
    printf '%s\n' "failover was too early: ${FAILOVER_ELAPSED}s" >&2
    exit 1
}

rm -f "$DROP_AUDIO_FLAG"
RECOVERY_STARTED=$(date +%s)
wait_state primary_recovered 18
RECOVERY_ELAPSED=$(($(date +%s) - RECOVERY_STARTED))
[ "$RECOVERY_ELAPSED" -ge 5 ] || {
    printf '%s\n' "recovery was too early: ${RECOVERY_ELAPSED}s" >&2
    exit 1
}

wait "$FFMPEG_PID"
PIDS=$(printf '%s\n' "$PIDS" | sed "s/ $FFMPEG_PID//")

ffprobe -v error -select_streams v:0 -show_entries stream=codec_type \
    -of default=nw=1:nk=1 "$ROOT/output.ts" | grep -qx video
ffprobe -v error -select_streams a:0 -show_entries stream=codec_type \
    -of default=nw=1:nk=1 "$ROOT/output.ts" | grep -qx audio
grep -q 'ts_rewrite_cc_enabled = false' scripts/tests/buffer_av_health_canary.lua

printf '%s\n' "HTTP buffer A/V failover smoke: OK (failover=${FAILOVER_ELAPSED}s recovery=${RECOVERY_ELAPSED}s)"
