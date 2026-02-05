#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-9056}"
DATA_DIR="${DATA_DIR:-./data_ci_preview}"
WEB_DIR="${WEB_DIR:-./web}"
LOG_FILE="${LOG_FILE:-./ci_preview_server.log}"

WORKDIR="${WORKDIR:-$(mktemp -d -t astra_preview_ci.XXXXXX)}"
PLAYLIST_FILE="$WORKDIR/index.m3u8"

SERVER_PID=""
SENDER_PID=""

cleanup() {
  set +e
  if [[ -n "${SENDER_PID:-}" ]]; then
    kill "$SENDER_PID" 2>/dev/null || true
    wait "$SENDER_PID" 2>/dev/null || true
  fi
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$LOG_FILE"
  rm -rf "$DATA_DIR"
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

pick_free_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()
PY
}

json_get() {
  python3 -c "import json,sys; data=json.load(sys.stdin); print(data.get('$1',''))"
}

echo "[preview-smoke] build" >&2
./configure.sh
make

echo "[preview-smoke] start server on :${PORT}" >&2
./astra scripts/server.lua -p "$PORT" --data-dir "$DATA_DIR" --web-dir "$WEB_DIR" >"$LOG_FILE" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 40); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/index.html" || true)"
  if [[ "$code" == "200" ]]; then
    break
  fi
  sleep 0.25
done

BASE="http://127.0.0.1:${PORT}"

echo "[preview-smoke] login" >&2
LOGIN_JSON="$(curl -s -X POST "${BASE}/api/v1/auth/login" -H 'Content-Type: application/json' --data-binary '{"username":"admin","password":"admin"}' || true)"
if [[ "${LOGIN_JSON:0:1}" != "{" ]]; then
  echo "login failed: ${LOGIN_JSON}" >&2
  tail -n 200 "$LOG_FILE" >&2 || true
  exit 1
fi
TOKEN="$(printf '%s' "$LOGIN_JSON" | json_get token)"
if [[ -z "$TOKEN" ]]; then
  echo "login failed (no token)" >&2
  tail -n 200 "$LOG_FILE" >&2 || true
  exit 1
fi

AUTH=(-H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json')

echo "[preview-smoke] set preview limits" >&2
curl -fsS -X PUT "${BASE}/api/v1/settings" "${AUTH[@]}" --data-binary '{"preview_max_sessions":2,"preview_idle_timeout_sec":3,"preview_token_ttl_sec":5}' >/dev/null

UDP1="$(pick_free_port)"
UDP2="$(pick_free_port)"
UDP3="$(pick_free_port)"

echo "[preview-smoke] create streams (udp ports: $UDP1 $UDP2 $UDP3)" >&2
curl -fsS -X POST "${BASE}/api/v1/streams" "${AUTH[@]}" --data-binary @- >/dev/null <<JSON
{"id":"s1","enabled":true,"config":{"id":"s1","name":"S1","input":["udp://127.0.0.1:${UDP1}"]}}
JSON
curl -fsS -X POST "${BASE}/api/v1/streams" "${AUTH[@]}" --data-binary @- >/dev/null <<JSON
{"id":"s2","enabled":true,"config":{"id":"s2","name":"S2","input":["udp://127.0.0.1:${UDP2}"]}}
JSON
curl -fsS -X POST "${BASE}/api/v1/streams" "${AUTH[@]}" --data-binary @- >/dev/null <<JSON
{"id":"s3","enabled":true,"config":{"id":"s3","name":"S3","input":["udp://127.0.0.1:${UDP3}"]}}
JSON

echo "[preview-smoke] start UDP TS generator" >&2
python3 - <<PY &
import socket,time
ports=[${UDP1},${UDP2},${UDP3}]
sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
pkt=bytes([0x47,0x1F,0xFF,0x10])+bytes(184)  # null TS packet (PID 0x1FFF)
while True:
  for p in ports:
    sock.sendto(pkt, ("127.0.0.1", p))
  time.sleep(0.02)
PY
SENDER_PID=$!

echo "[preview-smoke] start preview for s1" >&2
P1_JSON="$(curl -fsS -X POST "${BASE}/api/v1/streams/s1/preview/start" "${AUTH[@]}")"
P1_URL_PATH="$(printf '%s' "$P1_JSON" | json_get url)"
P1_TOKEN="$(printf '%s' "$P1_JSON" | json_get token)"
if [[ -z "$P1_URL_PATH" ]] || [[ -z "$P1_TOKEN" ]]; then
  echo "preview/start s1 failed: $P1_JSON" >&2
  exit 1
fi

P1_URL="${BASE}${P1_URL_PATH}"
echo "[preview-smoke] wait for playlist: $P1_URL" >&2
SEG=""
for _ in $(seq 1 80); do
  code="$(curl -s -o "$PLAYLIST_FILE" -w '%{http_code}' "$P1_URL" || true)"
  if [[ "$code" == "200" ]]; then
    SEG="$(grep -v '^#' "$PLAYLIST_FILE" | tr -d '\r' | awk 'NF{print $0}' | head -n 1 || true)"
    if [[ -n "$SEG" ]]; then
      break
    fi
  fi
  sleep 0.25
done
if [[ -z "$SEG" ]]; then
  echo "playlist not ready (see $LOG_FILE)" >&2
  tail -n 200 "$LOG_FILE" >&2 || true
  exit 1
fi

echo "[preview-smoke] fetch first segment: $SEG" >&2
curl -fsS "${BASE}/preview/${P1_TOKEN}/${SEG}" -o "$WORKDIR/$SEG" >/dev/null

echo "[preview-smoke] limit check: start s2 then s3 must fail" >&2
curl -fsS -X POST "${BASE}/api/v1/streams/s2/preview/start" "${AUTH[@]}" >/dev/null
code="$(curl -s -o "$WORKDIR/s3.json" -w '%{http_code}' -X POST "${BASE}/api/v1/streams/s3/preview/start" "${AUTH[@]}" || true)"
if [[ "$code" != "429" ]]; then
  echo "expected 429 for s3, got $code: $(cat "$WORKDIR/s3.json" 2>/dev/null || true)" >&2
  exit 1
fi

echo "[preview-smoke] idle cleanup check" >&2
sleep 8
code="$(curl -s -o /dev/null -w '%{http_code}' "$P1_URL" || true)"
if [[ "$code" != "404" ]]; then
  echo "expected 404 after idle cleanup, got $code" >&2
  exit 1
fi

echo "[preview-smoke] ok" >&2
