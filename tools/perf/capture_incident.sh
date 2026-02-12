#!/usr/bin/env bash
set -euo pipefail

PID="${1:-}"
SECONDS="${2:-15}"
OUT_DIR="${3:-}"

if [[ -z "$PID" || -z "$OUT_DIR" ]]; then
  echo "Usage: $0 <pid> <seconds> <out_dir>"
  exit 2
fi

mkdir -p "$OUT_DIR"

run() {
  local name="$1"
  shift
  {
    echo "### $(date -Is) :: $name"
    "$@"
  } >"$OUT_DIR/$name.txt" 2>&1 || true
}

run "env" bash -lc 'uname -a; echo; command -v lscpu >/dev/null && lscpu | egrep "^(CPU\\(s\\):|Thread\\(s\\) per core:|Core\\(s\\) per socket:|Socket\\(s\\):)" || true; echo; echo "pid=$PID"; cat /proc/'"$PID"'/status 2>/dev/null | egrep "^(Name:|State:|Threads:|VmRSS:|voluntary_ctxt_switches:|nonvoluntary_ctxt_switches:|Cpus_allowed_list:)" || true'

run "threads_top" bash -lc 'ps -L -p '"$PID"' -o pid,tid,psr,pcpu,comm --sort=-pcpu | head -n 50'

if command -v mpstat >/dev/null 2>&1; then
  run "mpstat_all" bash -lc "mpstat -P ALL 1 $SECONDS"
fi

if command -v pidstat >/dev/null 2>&1; then
  run "pidstat_threads" bash -lc "pidstat -t -p $PID 1 $SECONDS"
fi

if [[ -r /proc/net/softnet_stat ]]; then
  run "softnet_before" bash -lc "cat /proc/net/softnet_stat"
  sleep "$SECONDS" || true
  run "softnet_after" bash -lc "cat /proc/net/softnet_stat"
fi

if command -v perf >/dev/null 2>&1; then
  # Best-effort: perf может быть ограничен perf_event_paranoid или отсутствием symbols.
  run "perf_record" bash -lc "perf record -q -F 99 -p $PID -g -o '$OUT_DIR/perf.data' -- sleep $SECONDS"
  run "perf_report" bash -lc "perf report -i '$OUT_DIR/perf.data' --stdio --percent-limit 1 --sort comm,dso,symbol | head -n 200"
fi

echo "Saved to: $OUT_DIR"

