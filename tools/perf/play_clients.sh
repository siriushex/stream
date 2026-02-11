#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <play_url> [clients=100] [hold_sec=30]"
  exit 1
fi

PLAY_URL="$1"
CLIENTS="${2:-100}"
HOLD_SEC="${3:-30}"

pids=()
cleanup() {
  for p in "${pids[@]:-}"; do
    kill "$p" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

for _ in $(seq 1 "$CLIENTS"); do
  (curl -fsS --max-time "$HOLD_SEC" "$PLAY_URL" >/dev/null 2>&1 || true) &
  pids+=("$!")
  sleep 0.01
done

wait
