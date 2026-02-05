#!/usr/bin/env bash
set -euo pipefail

INPUT_URL="${1:-udp://127.0.0.1:12346}"
DURATION_SEC="${2:-5}"
EXPECT_PNRS="${EXPECT_PNRS:-}"
EXPECT_SERVICES="${EXPECT_SERVICES:-}"
EXPECT_PROVIDERS="${EXPECT_PROVIDERS:-}"

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

if [[ -n "$EXPECT_PNRS" ]]; then
  IFS=',' read -r -a PNR_LIST <<< "$EXPECT_PNRS"
  for pnr in "${PNR_LIST[@]}"; do
    pnr_trim="$(echo "$pnr" | xargs)"
    if [[ -z "$pnr_trim" ]]; then
      continue
    fi
    if ! grep -q "PAT: pid: .* pnr: ${pnr_trim}" "$LOG_FILE"; then
      echo "PAT missing PNR ${pnr_trim}"
      exit 1
    fi
  done
fi

if [[ -n "$EXPECT_SERVICES" ]]; then
  IFS=',' read -r -a SERVICE_LIST <<< "$EXPECT_SERVICES"
  for svc in "${SERVICE_LIST[@]}"; do
    svc_trim="$(echo "$svc" | xargs)"
    if [[ -z "$svc_trim" ]]; then
      continue
    fi
    if ! grep -Fq "SDT:     Service: ${svc_trim}" "$LOG_FILE"; then
      echo "SDT missing Service ${svc_trim}"
      exit 1
    fi
  done
fi

if [[ -n "$EXPECT_PROVIDERS" ]]; then
  IFS=',' read -r -a PROVIDER_LIST <<< "$EXPECT_PROVIDERS"
  for provider in "${PROVIDER_LIST[@]}"; do
    provider_trim="$(echo "$provider" | xargs)"
    if [[ -z "$provider_trim" ]]; then
      continue
    fi
    if ! grep -Fq "SDT:     Provider: ${provider_trim}" "$LOG_FILE"; then
      echo "SDT missing Provider ${provider_trim}"
      exit 1
    fi
  done
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
