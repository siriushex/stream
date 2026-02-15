#!/usr/bin/env bash
set -euo pipefail

STREAM_DIR_DEFAULT="/opt/stream"
STREAM_CONFIG_DEFAULT="/etc/stream/stream.json"
STREAM_PORT_DEFAULT="8816"
STREAM_LOG_DEFAULT="/var/log/stream/stream.log"

STREAM_DIR="${STREAM_DIR:-$STREAM_DIR_DEFAULT}"
STREAM_CONFIG="${STREAM_CONFIG:-$STREAM_CONFIG_DEFAULT}"
STREAM_PORT="${STREAM_PORT:-$STREAM_PORT_DEFAULT}"
STREAM_LOG="${STREAM_LOG:-$STREAM_LOG_DEFAULT}"
STREAM_ARGS="${STREAM_ARGS:-}"
STREAM_CMD="${STREAM_CMD:-}"
STREAM_PGREP="${STREAM_PGREP:-}"

STATE_FILE="${STATE_FILE:-/var/run/stream-watchdog.state}"
CPU_LIMIT="${CPU_LIMIT:-300}"
RSS_LIMIT_MB="${RSS_LIMIT_MB:-1500}"
HITS_THRESHOLD="${HITS_THRESHOLD:-2}"

if [ -f /etc/stream-watchdog.env ]; then
  # shellcheck disable=SC1091
  source /etc/stream-watchdog.env
fi

BIN="${STREAM_DIR%/}/stream"
PGREP_PATTERN="${STREAM_PGREP:-stream .* -p ${STREAM_PORT}}"

log_warn() {
  local msg="$1"
  logger -t stream-watchdog "$msg"
  mkdir -p "$(dirname "$STREAM_LOG")"
  echo "$(date "+%b %d %H:%M:%S"): WARN: [watchdog] $msg" >> "$STREAM_LOG"
}

cpu_hits=0
mem_hits=0
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE" || true
fi

pid=$(pgrep -fo "$PGREP_PATTERN" || true)

start_stream() {
  if [ -n "$STREAM_CMD" ]; then
    nohup bash -lc "$STREAM_CMD" >> "$STREAM_LOG" 2>&1 &
    return 0
  fi
  if [ ! -x "$BIN" ]; then
    log_warn "stream binary not found at $BIN"
    return 1
  fi
  nohup "$BIN" "$STREAM_CONFIG" -p "$STREAM_PORT" $STREAM_ARGS >> "$STREAM_LOG" 2>&1 &
}

if [ -z "$pid" ]; then
  if ss -lntp | grep -q ":${STREAM_PORT} "; then
    exit 0
  fi
  start_stream
  log_warn "restarted stream on port ${STREAM_PORT} (process not found)"
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
  start_stream
  echo "cpu_hits=0" > "$STATE_FILE"
  echo "mem_hits=0" >> "$STATE_FILE"
fi
