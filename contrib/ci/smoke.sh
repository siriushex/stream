#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-9050}"
DATA_DIR="${DATA_DIR:-./data_ci}"
WEB_DIR="${WEB_DIR:-./web}"
LOG_FILE="${LOG_FILE:-./ci_server.log}"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  if [[ -n "${COOKIE_JAR:-}" ]] && [[ -f "$COOKIE_JAR" ]]; then
    rm -f "$COOKIE_JAR"
  fi
  if [[ -n "${APP_JS_FILE:-}" ]] && [[ -f "$APP_JS_FILE" ]]; then
    rm -f "$APP_JS_FILE"
  fi
  rm -f "$LOG_FILE"
  rm -rf "$DATA_DIR"
}
trap cleanup EXIT

./configure.sh
make

./astra scripts/server.lua -p "$PORT" --data-dir "$DATA_DIR" --web-dir "$WEB_DIR" > "$LOG_FILE" 2>&1 &
SERVER_PID=$!
sleep 2

curl -I "http://127.0.0.1:${PORT}/index.html"
INDEX_HTML="$(curl -fsS "http://127.0.0.1:${PORT}/index.html")"
if ! grep -q 'app.js' <<<"$INDEX_HTML"; then
  echo "index.html missing app.js reference" >&2
  exit 1
fi

APP_JS_FILE="$(mktemp)"
curl -fsS "http://127.0.0.1:${PORT}/app.js" -o "$APP_JS_FILE"
head -n 1 "$APP_JS_FILE"

COOKIE_JAR="$(mktemp)"
curl -s -c "$COOKIE_JAR" -X POST "http://127.0.0.1:${PORT}/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"admin","password":"admin"}'

curl -s "http://127.0.0.1:${PORT}/api/v1/streams" -b "$COOKIE_JAR"
curl -s "http://127.0.0.1:${PORT}/api/v1/settings" -b "$COOKIE_JAR"
curl -s "http://127.0.0.1:${PORT}/api/v1/metrics" -b "$COOKIE_JAR"
curl -s "http://127.0.0.1:${PORT}/api/v1/metrics?format=prometheus" -b "$COOKIE_JAR"
curl -s "http://127.0.0.1:${PORT}/api/v1/health/process" -b "$COOKIE_JAR"
curl -s "http://127.0.0.1:${PORT}/api/v1/health/inputs" -b "$COOKIE_JAR"
curl -s "http://127.0.0.1:${PORT}/api/v1/health/outputs" -b "$COOKIE_JAR"
curl -s "http://127.0.0.1:${PORT}/api/v1/export?include_users=0" -b "$COOKIE_JAR" | head -n 1

./astra scripts/export.lua --data-dir "$DATA_DIR" --output "${DATA_DIR}/astra-export.json"
