#!/usr/bin/env bash
set -euo pipefail

INPUT_URL="${1:-udp://127.0.0.1:12346}"
DURATION_SEC="${2:-5}"

LOG_FILE="$(mktemp)"

./astra scripts/analyze.lua -n "$DURATION_SEC" "$INPUT_URL" > "$LOG_FILE" 2>&1 || true

if ! grep -q "PAT:" "$LOG_FILE"; then
  echo "PAT not found"
  exit 1
fi

if ! grep -q "PMT:" "$LOG_FILE"; then
  echo "PMT not found"
  exit 1
fi

if ! grep -q "SDT:" "$LOG_FILE"; then
  echo "SDT not found"
  exit 1
fi

if ! grep -q "NIT:" "$LOG_FILE"; then
  echo "NIT not found"
  exit 1
fi

if ! grep -q "TDT:" "$LOG_FILE"; then
  echo "TDT not found"
  exit 1
fi

if ! grep -q "TOT:" "$LOG_FILE"; then
  if [[ "${EXPECT_TOT:-0}" == "1" ]]; then
    echo "TOT not found"
    exit 1
  fi
  echo "TOT not found (optional)"
fi

echo "OK"
