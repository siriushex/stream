#!/usr/bin/env bash
set -euo pipefail

# CAM / Softcam stats smoke test (Linux recommended).
# Требования: curl, ffmpeg, python3, bash.
#
# Проверяет:
# - /api/v1/streams/<id>/cam-stats возвращает decrypt + softcam_id
# - при newcamd softcam доступен cam:stats() (ready/status/queue/reconnects/timeouts/...)
# - split_cam_pool_size не ломает запуск (pool-клоны создаются lazy)

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

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STREAM_BIN="${STREAM_BIN:-$ROOT_DIR/stream}"
WEB_DIR="${WEB_DIR:-$ROOT_DIR/web}"

[[ -x "$STREAM_BIN" ]] || die "stream binary not found or not executable: $STREAM_BIN"
[[ -d "$WEB_DIR" ]] || die "web dir not found: $WEB_DIR"

PORT="${PORT:-$(pick_free_port)}"
UDP_PORT="${UDP_PORT:-$(pick_free_port)}"

STREAM_ID="${STREAM_ID:-cam_demo}"
SOFTCAM_ID="${SOFTCAM_ID:-sc_demo}"
POOL_SIZE="${POOL_SIZE:-4}"

WORKDIR="${WORKDIR:-$(mktemp -d -t stream_cam_stats_smoke.XXXXXX)}"
DATA_DIR="$WORKDIR/data"
CFG="$WORKDIR/cam_stats_smoke.json"
STREAM_LOG="$WORKDIR/stream.log"
FFMPEG_LOG="$WORKDIR/ffmpeg.log"

STREAM_PID=""
FFMPEG_PID=""

cleanup() {
  set +e
  if [[ -n "$STREAM_PID" ]]; then
    kill "$STREAM_PID" >/dev/null 2>&1 || true
    sleep 0.3
    kill -9 "$STREAM_PID" >/dev/null 2>&1 || true
    wait "$STREAM_PID" >/dev/null 2>&1 || true
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

mkdir -p "$DATA_DIR"

cat >"$CFG" <<JSON
{
  "settings": {},
  "users": {},
  "splitters": [],
  "softcam": [
    {
      "id": "${SOFTCAM_ID}",
      "name": "Smoke CAM",
      "type": "newcamd",
      "enable": true,
      "host": "127.0.0.1",
      "port": 65535,
      "user": "user",
      "pass": "pass",
      "key": "0102030405060708091011121314",
      "timeout": 8000,
      "split_cam": true,
      "split_cam_pool_size": ${POOL_SIZE}
    }
  ],
  "make_stream": [
    {
      "id": "${STREAM_ID}",
      "name": "CAM Smoke",
      "type": "udp",
      "enable": true,
      "input": ["udp://127.0.0.1:${UDP_PORT}"],
      "output": [],
      "cam": "${SOFTCAM_ID}",
      "shift": 200
    }
  ],
  "dvb_tune": []
}
JSON

echo "Starting ffmpeg UDP input on 127.0.0.1:${UDP_PORT}..." >&2
ffmpeg -loglevel error -re \
  -f lavfi -i testsrc=size=160x90:rate=25 \
  -f lavfi -i sine=frequency=1000 \
  -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:${UDP_PORT}?pkt_size=1316" \
  >"$FFMPEG_LOG" 2>&1 &
FFMPEG_PID="$!"

echo "Starting Stream on 127.0.0.1:${PORT} (data-dir=${DATA_DIR})..." >&2
"$STREAM_BIN" "$CFG" -p "$PORT" --data-dir "$DATA_DIR" --web-dir "$WEB_DIR" >"$STREAM_LOG" 2>&1 &
STREAM_PID="$!"

HEALTH_URL="http://127.0.0.1:${PORT}/api/v1/health"
echo "Waiting for health: $HEALTH_URL" >&2
for _ in $(seq 1 80); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$HEALTH_URL" || true)"
  if [[ "$code" == "200" ]]; then
    break
  fi
  sleep 0.25
done

code="$(curl -s -o /dev/null -w '%{http_code}' "$HEALTH_URL" || true)"
[[ "$code" == "200" ]] || die "health endpoint not ready (see $STREAM_LOG)"

LOGIN_URL="http://127.0.0.1:${PORT}/api/v1/auth/login"
echo "Logging in via API (admin/admin)..." >&2
LOGIN_JSON="$WORKDIR/login.json"
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' \
  "$LOGIN_URL" >"$LOGIN_JSON"

TOKEN="$(python3 - <<PY
import json,sys
data=json.load(open("$LOGIN_JSON"))
token=data.get("token") or ""
print(token)
PY
)"
[[ -n "$TOKEN" ]] || die "login failed (see $LOGIN_JSON / $STREAM_LOG)"

CAM_URL="http://127.0.0.1:${PORT}/api/v1/streams/${STREAM_ID}/cam-stats"
OUT_JSON="$WORKDIR/cam_stats.json"
echo "Fetching CAM stats: $CAM_URL" >&2
curl -s -H "Authorization: Bearer $TOKEN" "$CAM_URL" >"$OUT_JSON"

python3 - <<PY
import json,sys
path="$OUT_JSON"
data=json.load(open(path))
inputs=data.get("inputs") or []
assert isinstance(inputs, list) and inputs, "no inputs in cam-stats"
active_id=int(data.get("active_input_id") or 0)
active=None
for it in inputs:
    if not isinstance(it, dict):
        continue
    if int(it.get("input_id") or 0) == active_id:
        active=it
        break
if active is None:
    active=inputs[0]

softcam_id=active.get("softcam_id") or ""
assert str(softcam_id) == "${SOFTCAM_ID}", f"softcam_id mismatch: {softcam_id}"

cam=active.get("cam")
assert isinstance(cam, dict), "cam stats missing (newcamd:stats() not available?)"

required=["ready","status","host","port","timeout_ms","caid","ua","queue_len","in_flight","reconnects","timeouts"]
missing=[k for k in required if k not in cam]
assert not missing, f"missing cam fields: {missing}"

# Pool metadata should be present when split_cam_pool_size > 1.
assert "pool_index" in cam and "pool_size" in cam, "missing pool_index/pool_size"
assert int(cam.get("pool_size") or 0) == int(${POOL_SIZE}), f"pool_size mismatch: {cam.get('pool_size')}"
print("OK")
PY

echo "OK: CAM stats smoke passed (port=${PORT})." >&2
