#!/usr/bin/env bash
set -euo pipefail

INPUT_URL="${1:-udp://127.0.0.1:12346}"
DURATION_SEC="${2:-5}"
EXPECT_PNRS="${EXPECT_PNRS:-}"
EXPECT_SERVICES="${EXPECT_SERVICES:-}"
EXPECT_PROVIDERS="${EXPECT_PROVIDERS:-}"
EXPECT_NETWORK_ID="${EXPECT_NETWORK_ID:-}"
EXPECT_TSID="${EXPECT_TSID:-}"
EXPECT_CAT="${EXPECT_CAT:-0}"
EXPECT_DELIVERY="${EXPECT_DELIVERY:-}"
EXPECT_FREQUENCY_KHZ="${EXPECT_FREQUENCY_KHZ:-}"
EXPECT_SYMBOLRATE_KSPS="${EXPECT_SYMBOLRATE_KSPS:-}"
EXPECT_MODULATION="${EXPECT_MODULATION:-}"
EXPECT_FEC="${EXPECT_FEC:-}"

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

if [[ "${EXPECT_CAT}" == "1" ]]; then
  if ! grep -q "CAT: present" "$LOG_FILE"; then
    echo "CAT not found"
    exit 1
  fi
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

if [[ -n "$EXPECT_NETWORK_ID" ]]; then
  if ! grep -q "NIT: network_id: ${EXPECT_NETWORK_ID}" "$LOG_FILE"; then
    echo "NIT network_id mismatch (expected ${EXPECT_NETWORK_ID})"
    exit 1
  fi
fi

if [[ -n "$EXPECT_DELIVERY" ]]; then
  if ! grep -q "NIT: delivery: ${EXPECT_DELIVERY}" "$LOG_FILE"; then
    echo "NIT delivery mismatch (expected ${EXPECT_DELIVERY})"
    exit 1
  fi
fi

if [[ -n "$EXPECT_FREQUENCY_KHZ" ]]; then
  if ! grep -q "freq_khz: ${EXPECT_FREQUENCY_KHZ}" "$LOG_FILE"; then
    echo "NIT frequency mismatch (expected ${EXPECT_FREQUENCY_KHZ})"
    exit 1
  fi
fi

if [[ -n "$EXPECT_SYMBOLRATE_KSPS" ]]; then
  if ! grep -q "symbolrate_ksps: ${EXPECT_SYMBOLRATE_KSPS}" "$LOG_FILE"; then
    echo "NIT symbolrate mismatch (expected ${EXPECT_SYMBOLRATE_KSPS})"
    exit 1
  fi
fi

if [[ -n "$EXPECT_MODULATION" ]]; then
  if ! grep -q "modulation: ${EXPECT_MODULATION}" "$LOG_FILE"; then
    echo "NIT modulation mismatch (expected ${EXPECT_MODULATION})"
    exit 1
  fi
fi

if [[ -n "$EXPECT_FEC" ]]; then
  if ! grep -q "fec: ${EXPECT_FEC}" "$LOG_FILE"; then
    echo "NIT fec mismatch (expected ${EXPECT_FEC})"
    exit 1
  fi
fi

if [[ -n "$EXPECT_TSID" ]]; then
  if ! grep -q "PAT: tsid: ${EXPECT_TSID}" "$LOG_FILE"; then
    echo "PAT tsid mismatch (expected ${EXPECT_TSID})"
    exit 1
  fi
  if ! grep -q "SDT: tsid: ${EXPECT_TSID}" "$LOG_FILE"; then
    echo "SDT tsid mismatch (expected ${EXPECT_TSID})"
    exit 1
  fi
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
