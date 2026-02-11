#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PID=""
BASE_URL="http://127.0.0.1:8000"
OUT_DIR=""
REQUESTS=1000
CONCURRENCY=20
TIMEOUT=3
ONLY_LITE=0
SKIP_LITE=0
BEARER=""
AUTH_USER=""
AUTH_PASS=""

usage() {
  cat <<EOF
Usage: $0 --pid <pid> [options]

Options:
  --pid <pid>                 PID процесса astral (обязательно)
  --base-url <url>            Базовый URL API (default: $BASE_URL)
  --out <dir>                 Папка для результатов (default: tools/perf/results/<ts>)
  --requests <n>              Кол-во запросов на кейс (default: $REQUESTS)
  --concurrency <n>           Параллелизм (default: $CONCURRENCY)
  --timeout <sec>             Таймаут запроса (default: $TIMEOUT)
  --only-lite                 Гонять только lite endpoint
  --skip-lite                 Гонять только full endpoint
  --bearer <token>            Bearer token для Authorization
  --auth-user <name>          Получить Bearer через /api/login (если --bearer не задан)
  --auth-pass <pass>          Пароль для --auth-user
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pid) PID="${2:-}"; shift 2 ;;
    --base-url) BASE_URL="${2:-}"; shift 2 ;;
    --out) OUT_DIR="${2:-}"; shift 2 ;;
    --requests) REQUESTS="${2:-}"; shift 2 ;;
    --concurrency) CONCURRENCY="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --only-lite) ONLY_LITE=1; shift ;;
    --skip-lite) SKIP_LITE=1; shift ;;
    --bearer) BEARER="${2:-}"; shift 2 ;;
    --auth-user) AUTH_USER="${2:-}"; shift 2 ;;
    --auth-pass) AUTH_PASS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$PID" ]]; then
  echo "error: --pid is required" >&2
  usage
  exit 1
fi
if ! kill -0 "$PID" 2>/dev/null; then
  echo "error: process $PID is not running" >&2
  exit 1
fi
if [[ "$ONLY_LITE" -eq 1 && "$SKIP_LITE" -eq 1 ]]; then
  echo "error: --only-lite and --skip-lite are mutually exclusive" >&2
  exit 1
fi
if [[ -n "$AUTH_USER" && -z "$AUTH_PASS" ]]; then
  echo "error: --auth-user requires --auth-pass" >&2
  exit 1
fi

if [[ -z "$OUT_DIR" ]]; then
  TS="$(date +%Y%m%d_%H%M%S)"
  OUT_DIR="$ROOT_DIR/tools/perf/results/$TS"
fi
mkdir -p "$OUT_DIR"

if [[ -z "$BEARER" && -n "$AUTH_USER" ]]; then
  LOGIN_URL="${BASE_URL%/}/api/login"
  LOGIN_JSON="$(python3 - "$LOGIN_URL" "$AUTH_USER" "$AUTH_PASS" <<'PY'
import json
import sys
import urllib.request
import urllib.error

url, user, password = sys.argv[1], sys.argv[2], sys.argv[3]
payload = json.dumps({"username": user, "password": password}).encode("utf-8")
req = urllib.request.Request(url, data=payload, method="POST")
req.add_header("Content-Type", "application/json")
try:
    with urllib.request.urlopen(req, timeout=5) as resp:
        body = resp.read().decode("utf-8", "replace")
except urllib.error.HTTPError as exc:
    body = exc.read().decode("utf-8", "replace")
    print(json.dumps({"ok": False, "status": exc.code, "body": body}))
    sys.exit(0)
except Exception as exc:
    print(json.dumps({"ok": False, "status": 0, "error": str(exc)}))
    sys.exit(0)

token = ""
status = int(getattr(resp, "status", 200))
try:
    parsed = json.loads(body)
    token = parsed.get("token", "") if isinstance(parsed, dict) else ""
except Exception:
    pass
print(json.dumps({"ok": bool(token), "status": status, "token": token, "body": body[:256]}))
PY
)"
  LOGIN_OK="$(python3 - "$LOGIN_JSON" <<'PY'
import json,sys
obj=json.loads(sys.argv[1])
print("1" if obj.get("ok") else "0")
PY
)"
  if [[ "$LOGIN_OK" != "1" ]]; then
    echo "error: auth login failed for polling suite: $LOGIN_JSON" >&2
    exit 1
  fi
  BEARER="$(python3 - "$LOGIN_JSON" <<'PY'
import json,sys
print(json.loads(sys.argv[1]).get("token",""))
PY
)"
fi

SNAPSHOT_SH="$ROOT_DIR/tools/perf/process_snapshot.sh"
POLL_PY="$ROOT_DIR/tools/perf/poll_status.py"

sample_process() {
  local pid="$1"
  local outfile="$2"
  local stopfile="$3"

  while [[ ! -f "$stopfile" ]]; do
    "$SNAPSHOT_SH" "$pid" >>"$outfile" 2>/dev/null || true
    sleep 1
  done
}

run_case() {
  local name="$1"
  local url="$2"
  local report_json="$OUT_DIR/${name}.json"
  local samples_log="$OUT_DIR/${name}_samples.log"
  local stopfile="$OUT_DIR/.${name}.stop"
  local -a auth_args=()
  if [[ -n "$BEARER" ]]; then
    auth_args=(--bearer "$BEARER")
  fi

  rm -f "$stopfile"
  : >"$samples_log"

  sample_process "$PID" "$samples_log" "$stopfile" &
  local sampler_pid=$!

  python3 "$POLL_PY" \
    --url "$url" \
    --requests "$REQUESTS" \
    --concurrency "$CONCURRENCY" \
    --timeout "$TIMEOUT" \
    "${auth_args[@]}" >"$report_json"

  touch "$stopfile"
  wait "$sampler_pid" || true
  rm -f "$stopfile"
}

META_FILE="$OUT_DIR/meta.txt"
{
  echo "pid=$PID"
  echo "base_url=$BASE_URL"
  echo "requests=$REQUESTS"
  echo "concurrency=$CONCURRENCY"
  echo "timeout=$TIMEOUT"
  echo "auth_user_set=$([[ -n \"$AUTH_USER\" ]] && echo 1 || echo 0)"
  echo "bearer_set=$([[ -n \"$BEARER\" ]] && echo 1 || echo 0)"
  echo "started_at=$(date -Iseconds)"
} >"$META_FILE"

"$SNAPSHOT_SH" "$PID" >"$OUT_DIR/snapshot_before.log"

if [[ "$ONLY_LITE" -eq 0 ]]; then
  run_case "status_full" "${BASE_URL%/}/api/v1/stream-status"
fi
if [[ "$SKIP_LITE" -eq 0 ]]; then
  run_case "status_lite" "${BASE_URL%/}/api/v1/stream-status?lite=1"
fi

"$SNAPSHOT_SH" "$PID" >"$OUT_DIR/snapshot_after.log"
echo "finished_at=$(date -Iseconds)" >>"$META_FILE"

echo "OK: results saved to $OUT_DIR"
