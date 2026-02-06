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
curl -s "http://127.0.0.1:${PORT}/api/v1/license" -b "$COOKIE_JAR" | head -n 1
curl -s "http://127.0.0.1:${PORT}/api/v1/metrics" -b "$COOKIE_JAR"
curl -s "http://127.0.0.1:${PORT}/api/v1/metrics?format=prometheus" -b "$COOKIE_JAR"
curl -s "http://127.0.0.1:${PORT}/api/v1/health/process" -b "$COOKIE_JAR"
curl -s "http://127.0.0.1:${PORT}/api/v1/health/inputs" -b "$COOKIE_JAR"
curl -s "http://127.0.0.1:${PORT}/api/v1/health/outputs" -b "$COOKIE_JAR"
curl -s "http://127.0.0.1:${PORT}/api/v1/export?include_users=0" -b "$COOKIE_JAR" | head -n 1

./astra scripts/export.lua --data-dir "$DATA_DIR" --output "${DATA_DIR}/astra-export.json"

if [[ "${MPTS_STRICT_PNR_SMOKE:-0}" == "1" ]]; then
  STRICT_PNR_PORT="${MPTS_STRICT_PNR_PORT:-9057}"
  PORT="$STRICT_PNR_PORT" contrib/ci/smoke_mpts_strict_pnr.sh
fi

if [[ "${MPTS_PID_COLLISION_SMOKE:-0}" == "1" ]]; then
  PORT="${MPTS_PID_COLLISION_PORT:-9059}" contrib/ci/smoke_mpts_pid_collision.sh
fi
if [[ "${MPTS_PASS_TABLES_SMOKE:-0}" == "1" ]]; then
  PORT="${MPTS_PASS_TABLES_PORT:-9058}" contrib/ci/smoke_mpts_pass_tables.sh
fi
if [[ "${MPTS_SPTS_ONLY_SMOKE:-0}" == "1" ]]; then
  PORT="${MPTS_SPTS_ONLY_PORT:-9062}" contrib/ci/smoke_mpts_spts_only.sh
fi
if [[ "${MPTS_AUTO_PROBE_SMOKE:-0}" == "1" ]]; then
  PORT="${MPTS_AUTO_PROBE_PORT:-9063}" contrib/ci/smoke_mpts_auto_probe.sh
fi

if [[ "${AUDIO_FIX_SMOKE:-0}" == "1" ]]; then
  PORT="${AUDIO_FIX_PORT:-9077}" contrib/ci/smoke_audio_fix_failover.sh
fi

if [[ "${TRANSCODE_WORKERS_SMOKE:-0}" == "1" ]]; then
  PORT="${TRANSCODE_WORKERS_PORT:-9083}" contrib/ci/smoke_transcode_per_output_isolation.sh
fi

if [[ "${TRANSCODE_SEAMLESS_SMOKE:-0}" == "1" ]]; then
  PORT="${TRANSCODE_SEAMLESS_PORT:-9084}" contrib/ci/smoke_transcode_seamless_failover.sh
fi

if [[ "${TRANSCODE_LADDER_HLS_SMOKE:-0}" == "1" ]]; then
  PORT="${TRANSCODE_LADDER_HLS_PORT:-9085}" contrib/ci/smoke_transcode_ladder_hls_publish.sh
fi
