#!/usr/bin/env bash
set -euo pipefail

# HLS memfd smoke test (Linux recommended).
# Требования: curl, ffmpeg, python3, bash.
#
# Проверяет:
# - HLS memfd on-demand: playlist/segments отдаются, сегменты не пишутся на диск (hls_dir)
# - idle timeout: генерация останавливается, старый сегмент после idle даёт 404
# - нагрузочная sanity: 10 параллельных клиентов на playlist/segment

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

pick_free_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()
PY
}

need_cmd bash
need_cmd curl
need_cmd python3
need_cmd ffmpeg
need_cmd grep
need_cmd awk

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASTRA_BIN="${ASTRA_BIN:-$ROOT_DIR/astra}"
WEB_DIR="${WEB_DIR:-$ROOT_DIR/web}"

[[ -x "$ASTRA_BIN" ]] || die "astra binary not found or not executable: $ASTRA_BIN"
[[ -d "$WEB_DIR" ]] || die "web dir not found: $WEB_DIR"

PORT="${PORT:-$(pick_free_port)}"
UDP_PORT="${UDP_PORT:-$(pick_free_port)}"
IDLE_TIMEOUT_SEC="${IDLE_TIMEOUT_SEC:-4}"
STREAM_ID="${STREAM_ID:-hls_demo}"

WORKDIR="${WORKDIR:-$(mktemp -d -t astra_hls_memfd_smoke.XXXXXX)}"
DATA_DIR="$WORKDIR/data"
CFG="$WORKDIR/hls_memfd_smoke.json"
ASTRA_LOG="$WORKDIR/astra.log"
FFMPEG_LOG="$WORKDIR/ffmpeg.log"

ASTRA_PID=""
FFMPEG_PID=""

cleanup() {
  set +e
  if [[ -n "$ASTRA_PID" ]]; then
    kill "$ASTRA_PID" >/dev/null 2>&1 || true
    sleep 0.3
    kill -9 "$ASTRA_PID" >/dev/null 2>&1 || true
    wait "$ASTRA_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "$FFMPEG_PID" ]]; then
    kill "$FFMPEG_PID" >/dev/null 2>&1 || true
    sleep 0.3
    kill -9 "$FFMPEG_PID" >/dev/null 2>&1 || true
    wait "$FFMPEG_PID" >/dev/null 2>&1 || true
  fi
  if [[ "${KEEP_WORKDIR:-}" != "1" ]]; then
    rm -rf "$WORKDIR" >/dev/null 2>&1 || true
  else
    echo "WORKDIR kept: $WORKDIR" >&2
  fi
}
trap cleanup EXIT

cat >"$CFG" <<JSON
{
  "settings": {
    "http_play_hls": true,
    "hls_storage": "memfd",
    "hls_on_demand": true,
    "hls_idle_timeout_sec": ${IDLE_TIMEOUT_SEC},
    "hls_max_bytes_per_stream": 67108864,
    "hls_max_segments": 12,
    "hls_duration": 2,
    "hls_quantity": 5
  },
  "make_stream": [
    {
      "id": "${STREAM_ID}",
      "name": "HLS Demo",
      "type": "udp",
      "enable": true,
      "input": ["udp://127.0.0.1:${UDP_PORT}"],
      "output": []
    }
  ]
}
JSON

echo "Starting ffmpeg UDP input on 127.0.0.1:${UDP_PORT}..." >&2
ffmpeg -loglevel error -re \
  -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=1000 \
  -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:${UDP_PORT}?pkt_size=1316" \
  >"$FFMPEG_LOG" 2>&1 &
FFMPEG_PID="$!"

echo "Starting Astra on 127.0.0.1:${PORT} (data-dir=${DATA_DIR})..." >&2
mkdir -p "$DATA_DIR"
"$ASTRA_BIN" "$CFG" -p "$PORT" --data-dir "$DATA_DIR" --web-dir "$WEB_DIR" >"$ASTRA_LOG" 2>&1 &
ASTRA_PID="$!"

PLAYLIST_URL="http://127.0.0.1:${PORT}/hls/${STREAM_ID}/index.m3u8"

echo "Waiting for playlist to become ready: $PLAYLIST_URL" >&2
SEGMENTS=()
for _ in $(seq 1 80); do
  code="$(curl -s -o "$WORKDIR/index.m3u8" -w '%{http_code}' "$PLAYLIST_URL" || true)"
  if [[ "$code" == "200" ]]; then
    mapfile -t SEGMENTS < <(grep -v '^#' "$WORKDIR/index.m3u8" | tr -d '\r' | awk 'NF{print $0}' | head -n 3)
    if [[ "${#SEGMENTS[@]}" -gt 0 ]]; then
      break
    fi
  fi
  sleep 0.25
done

[[ "${#SEGMENTS[@]}" -gt 0 ]] || die "playlist not ready (see $ASTRA_LOG)"
echo "Playlist ok; segments: ${SEGMENTS[*]}" >&2

echo "Downloading segments..." >&2
for seg in "${SEGMENTS[@]}"; do
  out_name="${seg##*/}"
  out_name="${out_name%%\\?*}"
  if [[ "${seg#'/'}" != "$seg" ]]; then
    url="http://127.0.0.1:${PORT}${seg}"
  else
    url="http://127.0.0.1:${PORT}/hls/${STREAM_ID}/${seg}"
  fi
  code="$(curl -s -o "$WORKDIR/$out_name" -w '%{http_code}' "$url" || true)"
  [[ "$code" == "200" ]] || die "segment fetch failed ($code): $url"
done

echo "Checking that no HLS files were created on disk under data-dir/hls..." >&2
if [[ -d "$DATA_DIR/hls" ]]; then
  files="$(find "$DATA_DIR/hls" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$files" == "0" ]] || die "unexpected HLS files on disk: $files (data-dir=$DATA_DIR)"
fi

echo "Load sanity: 10 clients playlist..." >&2
pids=()
for _ in $(seq 1 10); do
  curl -s "$PLAYLIST_URL" >/dev/null &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid"
done

echo "Load sanity: 10 clients segment..." >&2
if [[ "${SEGMENTS[0]#'/'}" != "${SEGMENTS[0]}" ]]; then
  SEG_URL="http://127.0.0.1:${PORT}${SEGMENTS[0]}"
else
  SEG_URL="http://127.0.0.1:${PORT}/hls/${STREAM_ID}/${SEGMENTS[0]}"
fi
pids=()
for _ in $(seq 1 10); do
  curl -s "$SEG_URL" >/dev/null &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid"
done

echo "Waiting for idle deactivation (idle_timeout=${IDLE_TIMEOUT_SEC}s)..." >&2
# Sweep interval is 2..5 seconds, so wait a bit longer than 2x idle.
sleep "$((IDLE_TIMEOUT_SEC * 2 + 2))"

grep -q "HLS deactivate stream=${STREAM_ID} reason=idle" "$ASTRA_LOG" \
  || die "idle deactivation log not found (see $ASTRA_LOG)"

echo "Checking that old segment returns 404 after idle..." >&2
code="$(curl -s -o /dev/null -w '%{http_code}' "$SEG_URL" || true)"
[[ "$code" == "404" ]] || die "expected 404 for old segment after idle, got $code: $SEG_URL"

echo "OK: HLS memfd smoke passed (port=${PORT})." >&2
