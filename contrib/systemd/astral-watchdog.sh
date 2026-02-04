#!/usr/bin/env bash
set -euo pipefail

ASTRA_DIR_DEFAULT="/opt/astra"
ASTRA_CONFIG_DEFAULT="/etc/astra/astra.json"
ASTRA_PORT_DEFAULT="8000"
ASTRA_LOG_DEFAULT="/var/log/astra/astra.log"

ASTRA_DIR="${ASTRA_DIR:-$ASTRA_DIR_DEFAULT}"
ASTRA_CONFIG="${ASTRA_CONFIG:-$ASTRA_CONFIG_DEFAULT}"
ASTRA_PORT="${ASTRA_PORT:-$ASTRA_PORT_DEFAULT}"
ASTRA_LOG="${ASTRA_LOG:-$ASTRA_LOG_DEFAULT}"
ASTRA_ARGS="${ASTRA_ARGS:-}"
ASTRA_CMD="${ASTRA_CMD:-}"
ASTRA_PGREP="${ASTRA_PGREP:-}"

STATE_FILE="${STATE_FILE:-/var/run/astral-watchdog.state}"
CPU_LIMIT="${CPU_LIMIT:-300}"
RSS_LIMIT_MB="${RSS_LIMIT_MB:-1500}"
HITS_THRESHOLD="${HITS_THRESHOLD:-2}"

if [ -f /etc/astral-watchdog.env ]; then
  # shellcheck disable=SC1091
  source /etc/astral-watchdog.env
fi

BIN="${ASTRA_DIR%/}/astra"
PGREP_PATTERN="${ASTRA_PGREP:-astra .* -p ${ASTRA_PORT}}"

log_warn() {
  local msg="$1"
  logger -t astral-watchdog "$msg"
  mkdir -p "$(dirname "$ASTRA_LOG")"
  echo "$(date "+%b %d %H:%M:%S"): WARN: [watchdog] $msg" >> "$ASTRA_LOG"
}

cpu_hits=0
mem_hits=0
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE" || true
fi

pid=$(pgrep -fo "$PGREP_PATTERN" || true)

start_astra() {
  if [ -n "$ASTRA_CMD" ]; then
    nohup bash -lc "$ASTRA_CMD" >> "$ASTRA_LOG" 2>&1 &
    return 0
  fi
  if [ ! -x "$BIN" ]; then
    log_warn "astra binary not found at $BIN"
    return 1
  fi
  nohup "$BIN" "$ASTRA_CONFIG" -p "$ASTRA_PORT" $ASTRA_ARGS >> "$ASTRA_LOG" 2>&1 &
}

if [ -z "$pid" ]; then
  if ss -lntp | grep -q ":${ASTRA_PORT} "; then
    exit 0
  fi
  start_astra
  log_warn "restarted astra on port ${ASTRA_PORT} (process not found)"
  echo "cpu_hits=0" > "$STATE_FILE"
  echo "mem_hits=0" >> "$STATE_FILE"
  exit 0
fi

cpu=$(ps -p "$pid" -o %cpu= | awk '{print $1}')
rss_kb=$(ps -p "$pid" -o rss= | awk '{print $1}')
rss_mb=$((rss_kb / 1024))

cpu_exceed=0
mem_exceed=0
awk -v c="$cpu" -v l="$CPU_LIMIT" 'BEGIN {exit !(c>l)}' && cpu_exceed=1 || true
[ "$rss_mb" -gt "$RSS_LIMIT_MB" ] && mem_exceed=1 || true

if [ "$cpu_exceed" -eq 1 ]; then
  cpu_hits=$((cpu_hits + 1))
else
  cpu_hits=0
fi

if [ "$mem_exceed" -eq 1 ]; then
  mem_hits=$((mem_hits + 1))
else
  mem_hits=0
fi

echo "cpu_hits=$cpu_hits" > "$STATE_FILE"
echo "mem_hits=$mem_hits" >> "$STATE_FILE"

if [ "$cpu_hits" -ge "$HITS_THRESHOLD" ] || [ "$mem_hits" -ge "$HITS_THRESHOLD" ]; then
  reason=""
  if [ "$cpu_hits" -ge "$HITS_THRESHOLD" ]; then
    reason="CPU ${cpu}% > ${CPU_LIMIT}%"
  fi
  if [ "$mem_hits" -ge "$HITS_THRESHOLD" ]; then
    if [ -n "$reason" ]; then
      reason+="; "
    fi
    reason+="RSS ${rss_mb}MB > ${RSS_LIMIT_MB}MB"
  fi
  log_warn "resource limit exceeded (${reason}); restarting"
  pkill -f "$PGREP_PATTERN" || true
  sleep 1
  start_astra
  echo "cpu_hits=0" > "$STATE_FILE"
  echo "mem_hits=0" >> "$STATE_FILE"
fi
