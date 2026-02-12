#!/usr/bin/env bash
set -euo pipefail

# Проверяет, что после безопасного PUT /api/v1/settings
# не падает uptime у активных stream-ов.
#
# Пример:
#   tools/perf/settings_no_restart_all_streams.sh \
#     --base http://127.0.0.1:9060

BASE_URL="http://127.0.0.1:9060"
USERNAME="${ASTRA_USER:-admin}"
PASSWORD="${ASTRA_PASS:-admin}"
TOKEN="${ASTRA_TOKEN:-}"
SETTING_KEY="ui_status_polling_interval_sec"
SETTING_VALUE="0.5"
WAIT_SEC=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      BASE_URL="$2"
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
    --setting-key)
      SETTING_KEY="$2"
      shift 2
      ;;
    --setting-value)
      SETTING_VALUE="$2"
      shift 2
      ;;
    --wait-sec)
      WAIT_SEC="$2"
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

get_status() {
  local token="$1"
  curl -fsS -H "Authorization: Bearer ${token}" "${BASE_URL}/api/v1/stream-status?lite=1"
}

apply_setting() {
  local token="$1"
  local key="$2"
  local val="$3"
  curl -fsS \
    -X PUT \
    -H "Authorization: Bearer ${token}" \
    -H "X-CSRF-Token: ${token}" \
    -H "Content-Type: application/json" \
    -d "{\"${key}\":${val}}" \
    "${BASE_URL}/api/v1/settings" >/dev/null
}

main() {
  local token
  token="$(auth_token)"
  if [[ -z "$token" ]]; then
    echo "failed to get auth token" >&2
    exit 1
  fi

  local before after
  before="$(get_status "$token")"
  apply_setting "$token" "$SETTING_KEY" "$SETTING_VALUE"
  sleep "$WAIT_SEC"
  after="$(get_status "$token")"

  python3 - "$before" "$after" <<'PY'
import json,sys

before=json.loads(sys.argv[1])
after=json.loads(sys.argv[2])

decreased=[]
checked=0

for sid,b in before.items():
    if not isinstance(b,dict):
        continue
    a=after.get(sid) or {}
    ub=b.get("uptime_sec")
    ua=a.get("uptime_sec")
    on_air = bool(b.get("on_air", False))
    # Сравниваем только те, что были активны и имели uptime.
    if not on_air:
        continue
    if isinstance(ub,(int,float)) and isinstance(ua,(int,float)):
        checked += 1
        if ua + 1 < ub:
            decreased.append((sid, ub, ua))

print(f"checked_active_streams={checked}")
if decreased:
    print("FAIL: uptime decreased for streams:")
    for sid,ub,ua in decreased:
        print(f"  {sid}: {ub} -> {ua}")
    sys.exit(2)
print("OK: no active stream uptime drops detected")
PY
}

main "$@"

