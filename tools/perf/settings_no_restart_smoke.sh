#!/usr/bin/env bash
set -euo pipefail

# Проверка, что изменение "безопасных" Settings -> General
# не вызывает forced reload stream/transcode пайплайна.
#
# Требования:
#   - curl
#   - python3
#   - доступ к API (admin/admin или через ASTRA_TOKEN)
#
# Пример:
#   tools/perf/settings_no_restart_smoke.sh \
#     --base http://127.0.0.1:9060 \
#     --stream a014

BASE_URL="http://127.0.0.1:9060"
STREAM_ID="a014"
USERNAME="${ASTRA_USER:-admin}"
PASSWORD="${ASTRA_PASS:-admin}"
TOKEN="${ASTRA_TOKEN:-}"
CHECK_LOCAL_PID=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      BASE_URL="$2"
      shift 2
      ;;
    --stream)
      STREAM_ID="$2"
      shift 2
      ;;
    --user)
      USERNAME="$2"
      shift 2
      ;;
    --pass)
      PASSWORD="$2"
      shift 2
      ;;
    --token)
      TOKEN="$2"
      shift 2
      ;;
    --check-local-pid)
      CHECK_LOCAL_PID=true
      shift
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

auth_token() {
  if [[ -n "$TOKEN" ]]; then
    echo "$TOKEN"
    return
  fi
  curl -fsS \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"${USERNAME}\",\"password\":\"${PASSWORD}\"}" \
    "${BASE_URL}/api/v1/auth/login" \
    | python3 -c 'import json,sys;print((json.load(sys.stdin) or {}).get("token",""))'
}

get_uptime() {
  local token="$1"
  local sid="$2"
  curl -fsS \
    -H "Authorization: Bearer ${token}" \
    "${BASE_URL}/api/v1/stream-status?lite=1" \
    | python3 -c "import json,sys;d=json.load(sys.stdin);print((d.get('${sid}') or {}).get('uptime_sec',-1))"
}

get_ffmpeg_pid() {
  local sid="$1"
  pgrep -f "ffmpeg.*input/${sid}" | head -n1 || true
}

set_setting() {
  local token="$1"
  local key="$2"
  local value_json="$3"
  curl -fsS \
    -X PUT \
    -H "Authorization: Bearer ${token}" \
    -H "X-CSRF-Token: ${token}" \
    -H "Content-Type: application/json" \
    -d "{\"${key}\":${value_json}}" \
    "${BASE_URL}/api/v1/settings" >/dev/null
}

main() {
  local token
  token="$(auth_token)"
  if [[ -z "$token" ]]; then
    echo "failed to get auth token" >&2
    exit 1
  fi

  local before_uptime before_pid
  before_uptime="$(get_uptime "$token" "$STREAM_ID")"
  before_pid=""
  if [[ "$CHECK_LOCAL_PID" == "true" ]]; then
    before_pid="$(get_ffmpeg_pid "$STREAM_ID")"
  fi

  echo "before: stream=${STREAM_ID} uptime=${before_uptime}s ffmpeg_pid=${before_pid:-none}"

  # Безопасный параметр из General: UI polling.
  set_setting "$token" "ui_status_polling_interval_sec" "0.5"
  sleep 2

  local after_uptime after_pid
  after_uptime="$(get_uptime "$token" "$STREAM_ID")"
  after_pid=""
  if [[ "$CHECK_LOCAL_PID" == "true" ]]; then
    after_pid="$(get_ffmpeg_pid "$STREAM_ID")"
  fi

  echo "after : stream=${STREAM_ID} uptime=${after_uptime}s ffmpeg_pid=${after_pid:-none}"

  if [[ "$CHECK_LOCAL_PID" == "true" && -n "${before_pid}" && -n "${after_pid}" && "${before_pid}" != "${after_pid}" ]]; then
    echo "FAIL: ffmpeg pid changed (${before_pid} -> ${after_pid})" >&2
    exit 2
  fi
  if [[ "${before_uptime}" -ge 0 && "${after_uptime}" -ge 0 && "${after_uptime}" -lt "${before_uptime}" ]]; then
    echo "FAIL: uptime dropped (${before_uptime} -> ${after_uptime})" >&2
    exit 3
  fi

  echo "OK: no forced stream restart on safe General setting change"
}

main "$@"
