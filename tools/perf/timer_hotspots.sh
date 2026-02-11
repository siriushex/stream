#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <pid> [seconds=20] [out_file=tools/perf/timer_hotspots.txt]"
  exit 1
fi

PID="$1"
SECONDS_CAPTURE="${2:-20}"
OUT_FILE="${3:-tools/perf/timer_hotspots.txt}"

if ! kill -0 "$PID" 2>/dev/null; then
  echo "error: process $PID is not running" >&2
  exit 1
fi

if command -v perf >/dev/null 2>&1; then
  TMP_DATA="$(mktemp /tmp/astra-perf-XXXXXX.data)"
  trap 'rm -f "$TMP_DATA"' EXIT

  perf record -q -F 99 -g -p "$PID" -o "$TMP_DATA" -- sleep "$SECONDS_CAPTURE"

  FULL_REPORT="$(perf report --stdio --no-children -i "$TMP_DATA" | sed -n '1,120p')"
  FILTERED="$(perf report --stdio --no-children -i "$TMP_DATA" \
    | grep -E "asc_timer_|timer_|asc_main_loop|asc_utime|asc_list|heap" || true)"
  TIMER_ONLY="$(printf '%s\n' "$FILTERED" | grep -E "asc_timer_|timer_heap|asc_timer_core_loop" || true)"
  if [[ -z "$TIMER_ONLY" ]]; then
    TIMER_ONLY="(нет пользовательских символов timer; вероятно, бинарник собран со strip)"
  fi

  {
    echo "# Timer hotspots (perf)"
    echo "pid=$PID seconds=$SECONDS_CAPTURE captured_at=$(date -Iseconds)"
    echo
    echo "## Timer symbols"
    printf '%s\n' "$TIMER_ONLY"
    echo
    echo "## Filtered (timer-related stack lines)"
    if [[ -n "$FILTERED" ]]; then
      printf '%s\n' "$FILTERED"
    else
      echo "(пусто)"
    fi
    echo
    echo "## Top report (first 120 lines)"
    printf '%s\n' "$FULL_REPORT"
  } >"$OUT_FILE"

  echo "OK: $OUT_FILE"
  exit 0
fi

if command -v sample >/dev/null 2>&1; then
  TMP_OUT="$(mktemp /tmp/astra-sample-XXXXXX.txt)"
  trap 'rm -f "$TMP_OUT"' EXIT

  sample "$PID" "$SECONDS_CAPTURE" 1 -file "$TMP_OUT" >/dev/null 2>&1 || true

  MATCHED="$(grep -E "asc_timer_|timer_|asc_main_loop|asc_utime|heap" "$TMP_OUT" || true)"

  {
    echo "# Timer hotspots (macOS sample)"
    echo "pid=$PID seconds=$SECONDS_CAPTURE captured_at=$(date -Iseconds)"
    echo
    if [[ -n "$MATCHED" ]]; then
      printf '%s\n' "$MATCHED"
    else
      echo "No timer symbols matched. Top sample lines:"
      head -n 80 "$TMP_OUT"
    fi
  } >"$OUT_FILE"

  echo "OK: $OUT_FILE"
  exit 0
fi

echo "error: neither perf nor sample command found" >&2
exit 1
