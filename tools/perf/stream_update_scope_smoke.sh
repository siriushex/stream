#!/usr/bin/env bash
set -euo pipefail

# Проверка scope-обновления стрима:
# - меняем только target stream (description),
# - убеждаемся, что control stream не перезапущен.
#
# Пример:
#   tools/perf/stream_update_scope_smoke.sh \
#     --base http://127.0.0.1:9060 \
#     --target a014 \
#     --control a019

BASE_URL="http://127.0.0.1:9060"
TARGET_STREAM="a014"
CONTROL_STREAM="a019"
USERNAME="${ASTRA_USER:-admin}"
PASSWORD="${ASTRA_PASS:-admin}"
TOKEN="${ASTRA_TOKEN:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      BASE_URL="$2"
      shift 2
      ;;
    --target)
      TARGET_STREAM="$2"
      shift 2
      ;;
    --control)
      CONTROL_STREAM="$2"
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

update_target_description() {
  local token="$1"
  local sid="$2"

  local current payload
  current="$(curl -fsS -H "Authorization: Bearer ${token}" "${BASE_URL}/api/v1/streams/${sid}")"
  payload="$(python3 - "$current" <<'PY'
import json,sys,time
obj=json.loads(sys.argv[1])
cfg=obj.get("config") or {}
cfg["description"]="scope-check-"+str(int(time.time()))
obj["config"]=cfg
print(json.dumps(obj,separators=(",",":")))
PY
)"

  curl -fsS \
    -X PUT \
    -H "Authorization: Bearer ${token}" \
    -H "X-CSRF-Token: ${token}" \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${BASE_URL}/api/v1/streams/${sid}" >/dev/null
}

main() {
  local token
  token="$(auth_token)"
  if [[ -z "$token" ]]; then
    echo "failed to get auth token" >&2
    exit 1
  fi

  local t1 c1
  t1="$(get_uptime "$token" "$TARGET_STREAM")"
  c1="$(get_uptime "$token" "$CONTROL_STREAM")"
  echo "before: target=${TARGET_STREAM}:${t1}s control=${CONTROL_STREAM}:${c1}s"

  update_target_description "$token" "$TARGET_STREAM"
  sleep 2

  local t2 c2
  t2="$(get_uptime "$token" "$TARGET_STREAM")"
  c2="$(get_uptime "$token" "$CONTROL_STREAM")"
  echo "after : target=${TARGET_STREAM}:${t2}s control=${CONTROL_STREAM}:${c2}s"

  if [[ "$c1" -ge 0 && "$c2" -ge 0 && "$c2" -lt "$c1" ]]; then
    echo "FAIL: control stream uptime dropped (${c1} -> ${c2})" >&2
    exit 2
  fi
  echo "OK: update scope is isolated (control stream unchanged)"
}

main "$@"

