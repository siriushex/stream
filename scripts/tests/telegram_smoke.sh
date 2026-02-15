#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
API="${STREAM_API:-${ASTRA_API:-http://127.0.0.1:8000}}"
USER="${STREAM_USER:-${ASTRA_USER:-admin}}"
PASS="${STREAM_PASS:-${ASTRA_PASS:-admin}}"
MOCK_HOST="${TELEGRAM_MOCK_HOST:-127.0.0.1}"
MOCK_PORT="${TELEGRAM_MOCK_PORT:-18080}"

python3 "$ROOT/fixtures/telegram_mock.py" "$MOCK_HOST" "$MOCK_PORT" >/tmp/telegram_mock.log 2>&1 &
MOCK_PID=$!
trap 'kill "$MOCK_PID" >/dev/null 2>&1 || true' EXIT

echo "Mock running on http://$MOCK_HOST:$MOCK_PORT"
echo "NOTE: Start Stream Hub with TELEGRAM_API_BASE_URL=http://$MOCK_HOST:$MOCK_PORT before running this test."

TOKEN=$(
  curl -i -s -X POST "$API/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    --data-binary "{\"username\":\"$USER\",\"password\":\"$PASS\"}" \
    | awk -F"stream_session=" "/Set-Cookie/ {print \$2}" | cut -d";" -f1 | head -n 1
)

if [[ -z "$TOKEN" ]]; then
  echo "Failed to obtain session token" >&2
  exit 1
fi

curl -s -X POST "$API/api/v1/notifications/telegram/test" \
  -H "Cookie: stream_session=$TOKEN" \
  -H "X-CSRF-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary "{}" >/dev/null

echo "telegram_smoke: request sent"
