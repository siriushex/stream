#!/usr/bin/env bash
set -euo pipefail

# E2E smoke: Stream /play -> auth backend (named auth_backend) -> allow/deny/redirect + cache.
#
# Требования:
# - bash
# - python3
# - curl
#
# Пример запуска:
#   STREAM_BIN=./stream ./tools/tests/auth_backend_e2e.sh

script_path="${BASH_SOURCE[0]:-$0}"
ROOT="$(cd "$(dirname "$script_path")/../.." && pwd)"

STREAM_BIN="${STREAM_BIN:-$ROOT/stream}"
PYTHON="${PYTHON:-python3}"
CURL_MAX_TIME="${CURL_MAX_TIME:-0.6}"

if [[ ! -x "$STREAM_BIN" ]]; then
  echo "ERROR: STREAM_BIN not executable: $STREAM_BIN" >&2
  exit 1
fi

if ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "ERROR: python3 not found" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl not found" >&2
  exit 1
fi

pick_port() {
  "$PYTHON" - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

STREAM_PORT="${STREAM_PORT:-$(pick_port)}"
BACKEND_PORT="${BACKEND_PORT:-$(pick_port)}"
MOCK_TS_PORT="${MOCK_TS_PORT:-$(pick_port)}"

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/stream-auth-e2e.XXXXXX")"
cfg="$tmpdir/test.json"
data_dir="$tmpdir/data"
backend_log="$tmpdir/backend.log"
mock_ts_log="$tmpdir/mock_ts.log"
stream_log="$tmpdir/stream.log"

cleanup() {
  set +e
  if [[ -n "${STREAM_PID:-}" ]]; then
    kill "$STREAM_PID" >/dev/null 2>&1 || true
    wait "$STREAM_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${BACKEND_PID:-}" ]]; then
    kill "$BACKEND_PID" >/dev/null 2>&1 || true
    wait "$BACKEND_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${MOCK_TS_PID:-}" ]]; then
    kill "$MOCK_TS_PID" >/dev/null 2>&1 || true
    wait "$MOCK_TS_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmpdir" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Starting mock HTTP-TS on :$MOCK_TS_PORT"
"$PYTHON" "$ROOT/tools/tests/mock_http_ts.py" --port "$MOCK_TS_PORT" --quiet >"$mock_ts_log" 2>&1 &
MOCK_TS_PID="$!"

cat >"$cfg" <<JSON
{
  "settings": {
    "http_play_allow": true,
    "auth_backends": {
      "demo": {
        "enabled": true,
        "mode": "sequential",
        "timeout_ms": 500,
        "total_timeout_ms": 1200,
        "fail_policy": "closed",
        "allow_default": false,
        "session_keys_default": ["ip","proto","name","token"],
        "cache": { "default_allow_sec": 2, "default_deny_sec": 2 },
        "backends": [
          { "url": "http://127.0.0.1:${BACKEND_PORT}/on_play", "timeout_ms": 500 }
        ]
      }
    }
  },
  "make_stream": [
    {
      "id": "auth_test",
      "name": "Auth Test",
      "enable": true,
      "input": ["http://127.0.0.1:${MOCK_TS_PORT}/stream.ts#sync"],
      "output": [],
      "on_play": "auth://demo",
      "session_keys": "ip,proto,name,token"
    }
  ]
}
JSON

echo "Starting auth backend mock on :$BACKEND_PORT"
AUTH_BACKEND_PORT="$BACKEND_PORT" "$PYTHON" "$ROOT/fixtures/auth_backend.py" >"$backend_log" 2>&1 &
BACKEND_PID="$!"

echo "Starting stream instance on :$STREAM_PORT (tmp: $tmpdir)"
"$STREAM_BIN" -c "$cfg" -p "$STREAM_PORT" --data-dir "$data_dir" >"$stream_log" 2>&1 &
STREAM_PID="$!"

echo "Waiting for /api/v1/health..."
for _ in $(seq 1 50); do
  if curl -fsS "http://127.0.0.1:${STREAM_PORT}/api/v1/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if ! curl -fsS "http://127.0.0.1:${STREAM_PORT}/api/v1/health" >/dev/null 2>&1; then
  echo "ERROR: stream instance did not start. Logs:" >&2
  tail -n 200 "$stream_log" >&2 || true
  exit 1
fi

expect_code() {
  local want="$1"
  local url="$2"
  local code
  code="$(curl -sS -o /dev/null -m "$CURL_MAX_TIME" -w '%{http_code}' "$url" || true)"
  if [[ "$code" != "$want" ]]; then
    echo "ERROR: expected HTTP $want, got $code for $url" >&2
    echo "--- stream log (tail)" >&2
    tail -n 80 "$stream_log" >&2 || true
    echo "--- backend log (tail)" >&2
    tail -n 80 "$backend_log" >&2 || true
    exit 1
  fi
}

echo "Deny: missing token"
expect_code 403 "http://127.0.0.1:${STREAM_PORT}/play/auth_test.ts?buf_fill_kb=1"

echo "Deny: bad token"
expect_code 403 "http://127.0.0.1:${STREAM_PORT}/play/auth_test.ts?token=bad&buf_fill_kb=1"

echo "Redirect: token=redirect"
expect_code 302 "http://127.0.0.1:${STREAM_PORT}/play/auth_test.ts?token=redirect&buf_fill_kb=1"

echo "Allow: token=token123"
expect_code 200 "http://127.0.0.1:${STREAM_PORT}/play/auth_test.ts?token=token123&buf_fill_kb=1"

echo "Cache: backend should be called once for repeated allow within TTL"
before="$("$PYTHON" -c "import json,urllib.request; print(json.load(urllib.request.urlopen('http://127.0.0.1:${BACKEND_PORT}/stats'))['on_play'])")"
expect_code 200 "http://127.0.0.1:${STREAM_PORT}/play/auth_test.ts?token=token123&buf_fill_kb=1"
after="$("$PYTHON" -c "import json,urllib.request; print(json.load(urllib.request.urlopen('http://127.0.0.1:${BACKEND_PORT}/stats'))['on_play'])")"
if [[ "$before" != "$after" ]]; then
  echo "ERROR: expected cache hit (on_play stays $before), got $after" >&2
  exit 1
fi

echo "TTL expiry: after 2.1s backend should be queried again"
sleep 2.1
expect_code 200 "http://127.0.0.1:${STREAM_PORT}/play/auth_test.ts?token=token123&buf_fill_kb=1"
after2="$("$PYTHON" -c "import json,urllib.request; print(json.load(urllib.request.urlopen('http://127.0.0.1:${BACKEND_PORT}/stats'))['on_play'])")"
if [[ "$after2" -le "$after" ]]; then
  echo "ERROR: expected backend recheck after TTL ($after -> >$after), got $after2" >&2
  exit 1
fi

echo "OK"
