#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <pid>"
  exit 1
fi

PID="$1"
if ! kill -0 "$PID" 2>/dev/null; then
  echo "process $PID is not running"
  exit 1
fi

TS="$(date +%s)"

CPU="$(ps -p "$PID" -o %cpu= | tr -d ' ' || echo 0)"
RSS_KB="$(ps -p "$PID" -o rss= | tr -d ' ' || echo 0)"

if [[ "$(uname -s)" == "Darwin" ]]; then
  THREADS="$(ps -M -p "$PID" 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
  FD_COUNT="$(lsof -p "$PID" 2>/dev/null | wc -l | tr -d ' ')"
else
  THREADS="$(ps -p "$PID" -o nlwp= | tr -d ' ' || echo 0)"
  FD_COUNT="$(ls "/proc/$PID/fd" 2>/dev/null | wc -l | tr -d ' ')"
fi

printf "ts=%s pid=%s cpu_pct=%s rss_kb=%s threads=%s fds=%s\n" \
  "$TS" "$PID" "${CPU:-0}" "${RSS_KB:-0}" "${THREADS:-0}" "${FD_COUNT:-0}"
