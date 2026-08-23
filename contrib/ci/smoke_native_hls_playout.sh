#!/bin/sh
set -eu

for cmd in ffmpeg ffprobe python3 curl; do
    command -v "$cmd" >/dev/null 2>&1 || {
        printf '%s\n' "missing dependency: $cmd" >&2
        exit 1
    }
done

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/stream-native-hls.XXXXXX")
SOURCE_PORT=$((25000 + ($$ % 1500) * 2))
OUTPUT_PORT=$((SOURCE_PORT + 1))
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
    -f lavfi -i sine=frequency=1000:sample_rate=48000 \
    -t 25 -c:v mpeg2video -g 25 -c:a mp2 -b:a 128k \
    -f hls -hls_time 2 -hls_list_size 0 "$ROOT/live.m3u8"

python3 -m http.server "$SOURCE_PORT" --bind 127.0.0.1 --directory "$ROOT" \
    >"$ROOT/http.log" 2>&1 &
PIDS="$PIDS $!"

source_ready=0
count=0
while [ "$count" -lt 20 ]; do
    if curl -fsS "http://127.0.0.1:$SOURCE_PORT/live.m3u8" >/dev/null 2>&1; then
        source_ready=1
        break
    fi
    sleep 0.1
    count=$((count + 1))
done
[ "$source_ready" -eq 1 ] || {
    printf '%s\n' 'HLS fixture server did not start' >&2
    sed -n '1,80p' "$ROOT/http.log" >&2 || true
    exit 1
}

HLS_SOURCE_PORT=$SOURCE_PORT HLS_OUTPUT_PORT=$OUTPUT_PORT HLS_STATUS_PATH=$STATUS_PATH \
    ./stream scripts/tests/native_hls_playout_canary.lua \
    >"$ROOT/stream.log" 2>&1 &
PIDS="$PIDS $!"

ready=0
count=0
while [ "$count" -lt 20 ]; do
    if [ -s "$STATUS_PATH" ] && python3 - "$STATUS_PATH" <<'PY'
import json
import sys

try:
    stats = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    raise SystemExit(1)
media = float(stats.get("media_kbps") or 0)
arrival = float(stats.get("arrival_kbps") or 0)
# A localhost burst may finish inside the one-second arrival-rate window; zero
# then means "not sampled", while PCR remains the authoritative pacing clock.
arrival_ok = arrival == 0 or arrival >= media
ok = media > 100 and arrival_ok and stats.get("prebuffering") is False
ok = ok and int(stats.get("underruns_total") or 0) <= 2
raise SystemExit(0 if ok else 1)
PY
    then
        ready=1
        break
    fi
    sleep 1
    count=$((count + 1))
done
[ "$ready" -eq 1 ] || {
    printf '%s\n' "native HLS playout did not become ready" >&2
    [ -f "$STATUS_PATH" ] && sed -n '1,20p' "$STATUS_PATH" >&2 || true
    sed -n '1,160p' "$ROOT/stream.log" >&2 || true
    exit 1
}

ffmpeg -hide_banner -loglevel error -y \
    -i "udp://127.0.0.1:$OUTPUT_PORT?fifo_size=1000000&overrun_nonfatal=1" \
    -c copy "$ROOT/output.ts" >"$ROOT/ffmpeg.log" 2>&1 &
FFMPEG_PID=$!
PIDS="$PIDS $FFMPEG_PID"
(
    sleep 16
    kill -INT "$FFMPEG_PID" >/dev/null 2>&1 || true
) &
WATCHDOG_PID=$!
PIDS="$PIDS $WATCHDOG_PID"

wait "$FFMPEG_PID" || true
PIDS=$(printf '%s\n' "$PIDS" | sed "s/ $FFMPEG_PID//")
wait "$WATCHDOG_PID" || true
PIDS=$(printf '%s\n' "$PIDS" | sed "s/ $WATCHDOG_PID//")

[ -s "$ROOT/output.ts" ] || {
    printf '%s\n' 'FFmpeg did not create HLS playout capture' >&2
    sed -n '1,160p' "$ROOT/ffmpeg.log" >&2 || true
    sed -n '1,200p' "$ROOT/stream.log" >&2 || true
    exit 1
}

ffprobe -v error -select_streams v:0 -show_entries stream=codec_type \
    -of default=nw=1:nk=1 "$ROOT/output.ts" | grep -qx video
ffprobe -v error -select_streams a:0 -show_entries stream=codec_type \
    -of default=nw=1:nk=1 "$ROOT/output.ts" | grep -qx audio

python3 - "$ROOT/http.log" <<'PY'
import collections
import re
import sys

counts = collections.Counter()
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    match = re.search(r'GET /([^ ]+\.ts) HTTP/', line)
    if match:
        counts[match.group(1)] += 1
duplicates = {name: count for name, count in counts.items() if count > 1}
if not counts or duplicates:
    print(f"segment requests={dict(counts)} duplicates={duplicates}", file=sys.stderr)
    raise SystemExit(1)
PY

printf '%s\n' 'Native HLS playout smoke: OK.'
