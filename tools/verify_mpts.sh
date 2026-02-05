#!/usr/bin/env bash
set -euo pipefail

INPUT_URL="${1:-udp://127.0.0.1:12346}"
DURATION_SEC="${2:-5}"
EXPECT_PNRS="${EXPECT_PNRS:-}"
EXPECT_PMT_PNRS="${EXPECT_PMT_PNRS:-}"
EXPECT_SERVICE_COUNT="${EXPECT_SERVICE_COUNT:-}"
EXPECT_PMT_STREAMS="${EXPECT_PMT_STREAMS:-}"
EXPECT_PMT_VIDEO="${EXPECT_PMT_VIDEO:-}"
EXPECT_PMT_AUDIO="${EXPECT_PMT_AUDIO:-}"
EXPECT_PMT_DATA="${EXPECT_PMT_DATA:-}"
EXPECT_PMT_PCR="${EXPECT_PMT_PCR:-}"
EXPECT_NO_CC_ERRORS="${EXPECT_NO_CC_ERRORS:-0}"
EXPECT_NO_PES_ERRORS="${EXPECT_NO_PES_ERRORS:-0}"
EXPECT_NO_SCRAMBLED="${EXPECT_NO_SCRAMBLED:-0}"
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
EXPECT_NETWORK_NAME="${EXPECT_NETWORK_NAME:-}"
EXPECT_LCN="${EXPECT_LCN:-}"
EXPECT_FREE_CA="${EXPECT_FREE_CA:-}"
EXPECT_SERVICE_TYPE="${EXPECT_SERVICE_TYPE:-}"
EXPECT_BITRATE_KBIT="${EXPECT_BITRATE_KBIT:-}"
EXPECT_BITRATE_TOL_PCT="${EXPECT_BITRATE_TOL_PCT:-10}"

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

if [[ -n "$EXPECT_PMT_PNRS" ]]; then
  IFS=',' read -r -a PMT_PNR_LIST <<< "$EXPECT_PMT_PNRS"
  for pnr in "${PMT_PNR_LIST[@]}"; do
    pnr_trim="$(echo "$pnr" | xargs)"
    if [[ -z "$pnr_trim" ]]; then
      continue
    fi
    if ! grep -q "PMT: pnr: ${pnr_trim}" "$LOG_FILE"; then
      echo "PMT missing PNR ${pnr_trim}"
      exit 1
    fi
  done
fi

if [[ -n "$EXPECT_SERVICE_COUNT" ]]; then
  sdt_count=$(grep -c "^SDT: sid:" "$LOG_FILE" || true)
  if [[ "$sdt_count" != "$EXPECT_SERVICE_COUNT" ]]; then
    echo "SDT service count mismatch (expected ${EXPECT_SERVICE_COUNT}, got ${sdt_count})"
    exit 1
  fi
fi

if [[ -n "$EXPECT_PMT_STREAMS" ]]; then
  IFS=',' read -r -a PMT_STREAM_LIST <<< "$EXPECT_PMT_STREAMS"
  for entry in "${PMT_STREAM_LIST[@]}"; do
    entry_trim="$(echo "$entry" | xargs)"
    if [[ -z "$entry_trim" ]]; then
      continue
    fi
    sid="${entry_trim%%=*}"
    value="${entry_trim#*=}"
    if ! grep -q "PMT: summary: pnr=${sid} .* streams=${value}" "$LOG_FILE"; then
      echo "PMT streams mismatch for pnr ${sid} (expected ${value})"
      exit 1
    fi
  done
fi

if [[ -n "$EXPECT_PMT_VIDEO" ]]; then
  IFS=',' read -r -a PMT_VIDEO_LIST <<< "$EXPECT_PMT_VIDEO"
  for entry in "${PMT_VIDEO_LIST[@]}"; do
    entry_trim="$(echo "$entry" | xargs)"
    if [[ -z "$entry_trim" ]]; then
      continue
    fi
    sid="${entry_trim%%=*}"
    value="${entry_trim#*=}"
    if ! grep -q "PMT: summary: pnr=${sid} .* video=${value}" "$LOG_FILE"; then
      echo "PMT video mismatch for pnr ${sid} (expected ${value})"
      exit 1
    fi
  done
fi

if [[ -n "$EXPECT_PMT_AUDIO" ]]; then
  IFS=',' read -r -a PMT_AUDIO_LIST <<< "$EXPECT_PMT_AUDIO"
  for entry in "${PMT_AUDIO_LIST[@]}"; do
    entry_trim="$(echo "$entry" | xargs)"
    if [[ -z "$entry_trim" ]]; then
      continue
    fi
    sid="${entry_trim%%=*}"
    value="${entry_trim#*=}"
    if ! grep -q "PMT: summary: pnr=${sid} .* audio=${value}" "$LOG_FILE"; then
      echo "PMT audio mismatch for pnr ${sid} (expected ${value})"
      exit 1
    fi
  done
fi

if [[ -n "$EXPECT_PMT_DATA" ]]; then
  IFS=',' read -r -a PMT_DATA_LIST <<< "$EXPECT_PMT_DATA"
  for entry in "${PMT_DATA_LIST[@]}"; do
    entry_trim="$(echo "$entry" | xargs)"
    if [[ -z "$entry_trim" ]]; then
      continue
    fi
    sid="${entry_trim%%=*}"
    value="${entry_trim#*=}"
    if ! grep -q "PMT: summary: pnr=${sid} .* data=${value}" "$LOG_FILE"; then
      echo "PMT data mismatch for pnr ${sid} (expected ${value})"
      exit 1
    fi
  done
fi

if [[ -n "$EXPECT_PMT_PCR" ]]; then
  IFS=',' read -r -a PMT_PCR_LIST <<< "$EXPECT_PMT_PCR"
  for entry in "${PMT_PCR_LIST[@]}"; do
    entry_trim="$(echo "$entry" | xargs)"
    if [[ -z "$entry_trim" ]]; then
      continue
    fi
    sid="${entry_trim%%=*}"
    value="${entry_trim#*=}"
    if ! grep -q "PMT: summary: pnr=${sid} .* pcr=${value}" "$LOG_FILE"; then
      echo "PMT PCR mismatch for pnr ${sid} (expected ${value})"
      exit 1
    fi
  done
fi

if [[ "$EXPECT_NO_CC_ERRORS" == "1" ]]; then
  if grep -q "^CC: " "$LOG_FILE"; then
    echo "Continuity counter errors detected"
    exit 1
  fi
fi

if [[ "$EXPECT_NO_PES_ERRORS" == "1" ]]; then
  if grep -q "^PES: " "$LOG_FILE"; then
    echo "PES errors detected"
    exit 1
  fi
fi

if [[ "$EXPECT_NO_SCRAMBLED" == "1" ]]; then
  if grep -q "^Scrambled: " "$LOG_FILE"; then
    echo "Scrambled packets detected"
    exit 1
  fi
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

if [[ -n "$EXPECT_NETWORK_NAME" ]]; then
  if ! grep -q "NIT: network_name: ${EXPECT_NETWORK_NAME}" "$LOG_FILE"; then
    echo "NIT network_name mismatch (expected ${EXPECT_NETWORK_NAME})"
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

if [[ -n "$EXPECT_LCN" ]]; then
  if ! grep -q "NIT: lcn: ${EXPECT_LCN}" "$LOG_FILE"; then
    echo "NIT lcn mismatch (expected ${EXPECT_LCN})"
    exit 1
  fi
fi

if [[ -n "$EXPECT_FREE_CA" ]]; then
  IFS=',' read -r -a FREECA_LIST <<< "$EXPECT_FREE_CA"
  for entry in "${FREECA_LIST[@]}"; do
    entry_trim="$(echo "$entry" | xargs)"
    if [[ -z "$entry_trim" ]]; then
      continue
    fi
    sid="${entry_trim%%=*}"
    value="${entry_trim#*=}"
    if ! grep -q "SDT: sid: ${sid} free_ca: ${value}" "$LOG_FILE"; then
      echo "SDT free_ca mismatch for sid ${sid} (expected ${value})"
      exit 1
    fi
  done
fi

if [[ -n "$EXPECT_SERVICE_TYPE" ]]; then
  IFS=',' read -r -a STYPE_LIST <<< "$EXPECT_SERVICE_TYPE"
  for entry in "${STYPE_LIST[@]}"; do
    entry_trim="$(echo "$entry" | xargs)"
    if [[ -z "$entry_trim" ]]; then
      continue
    fi
    sid="${entry_trim%%=*}"
    value="${entry_trim#*=}"
    if ! grep -q "SDT: sid: ${sid} .* service_type: ${value}" "$LOG_FILE"; then
      echo "SDT service_type mismatch for sid ${sid} (expected ${value})"
      exit 1
    fi
  done
fi

if [[ -n "$EXPECT_BITRATE_KBIT" ]]; then
  bitrate_line="$(grep -E "^Bitrate: [0-9]+ Kbit/s" "$LOG_FILE" | tail -n 1 | awk '{print $2}')"
  if [[ -z "$bitrate_line" ]]; then
    echo "Bitrate not found"
    exit 1
  fi
  actual_bitrate=$bitrate_line
  expected_bitrate=$EXPECT_BITRATE_KBIT
  tol_pct=$EXPECT_BITRATE_TOL_PCT
  if ! awk -v actual="$actual_bitrate" -v expected="$expected_bitrate" -v tol="$tol_pct" 'BEGIN {
        diff = actual - expected; if (diff < 0) diff = -diff;
        allowed = expected * tol / 100.0;
        exit(diff <= allowed ? 0 : 1)
      }'; then
    echo "Bitrate mismatch (expected ${expected_bitrate} Kbit/s +/- ${tol_pct}%, got ${actual_bitrate})"
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
