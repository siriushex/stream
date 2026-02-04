#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PORT="${PORT:-9065}"
BUNDLE_TAR="${BUNDLE_TAR:-}"
LOG_FILE="${LOG_FILE:-}"

if [[ -z "$BUNDLE_TAR" ]]; then
  latest="$(ls -t "$ROOT_DIR"/dist/astral-transcode-*.tar.gz 2>/dev/null | head -n 1 || true)"
  if [[ -z "$latest" ]]; then
    echo "BUNDLE_TAR not set and no bundle found in dist/" >&2
    exit 1
  fi
  BUNDLE_TAR="$latest"
fi

WORK_DIR="$(mktemp -d)"
DATA_DIR="$WORK_DIR/data"
LOG_FILE="${LOG_FILE:-$WORK_DIR/server.log}"
COOKIE_JAR="$WORK_DIR/cookies.txt"

cleanup() {
  if [[ -n "${FEED_PID:-}" ]]; then
    kill "$FEED_PID" 2>/dev/null || true
  fi
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$WORK_DIR"
tar -xzf "$BUNDLE_TAR" -C "$WORK_DIR"
BUNDLE_DIR="$(find "$WORK_DIR" -maxdepth 1 -type d -name 'astral-transcode-*' | head -n 1)"
if [[ -z "$BUNDLE_DIR" ]]; then
  echo "Bundle root not found after extract" >&2
  exit 1
fi

CONFIG_FILE="$ROOT_DIR/fixtures/transcode_bundle.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing fixture: $CONFIG_FILE" >&2
  exit 1
fi

pushd "$BUNDLE_DIR" >/dev/null

./run.sh scripts/server.lua -p "$PORT" --data-dir "$DATA_DIR" --config "$CONFIG_FILE" > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

sleep 2

"$BUNDLE_DIR/bin/ffmpeg" -hide_banner -loglevel error -re \
  -f lavfi -i testsrc=size=160x90:rate=25 \
  -f lavfi -i sine=frequency=1000 \
  -shortest -c:v mpeg2video -c:a mp2 \
  -f mpegts "udp://127.0.0.1:12100?pkt_size=1316" >/dev/null 2>&1 &
FEED_PID=$!

# Try login (ok even if auth disabled)
if curl -fsS -c "$COOKIE_JAR" -X POST "http://127.0.0.1:${PORT}/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"admin","password":"admin"}' >/dev/null 2>&1; then
  AUTH_ARGS=( -b "$COOKIE_JAR" )
else
  AUTH_ARGS=()
fi

TOOLS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/api/v1/tools" "${AUTH_ARGS[@]}")"
TOOLS_JSON="$TOOLS_JSON" python3 - <<'PY'
import json, os, sys
raw = os.environ.get('TOOLS_JSON')
if not raw:
    sys.exit('Missing tools json')
info = json.loads(raw)
path = info.get('ffmpeg_path_resolved', '')
if '/bin/ffmpeg' not in path:
    sys.exit('ffmpeg_path_resolved does not point to bundled bin')
if not info.get('ffmpeg_bundled'):
    sys.exit('ffmpeg_bundled is false')
print('tools ok')
PY

STATE_OK=0
for _ in $(seq 1 10); do
  STATUS_JSON="$(curl -fsS "http://127.0.0.1:${PORT}/api/v1/transcode-status/transcode_bundle_test" "${AUTH_ARGS[@]}")"
  STATE="$(STATUS_JSON="$STATUS_JSON" python3 - <<'PY'
import json, os
raw = os.environ.get('STATUS_JSON')
info = json.loads(raw) if raw else {}
print(info.get('state', ''))
PY
)"
  if [[ "$STATE" == "RUNNING" ]]; then
    STATE_OK=1
    break
  fi
  sleep 1
done

if [[ "$STATE_OK" -ne 1 ]]; then
  echo "Transcode state not RUNNING" >&2
  exit 1
fi

popd >/dev/null
