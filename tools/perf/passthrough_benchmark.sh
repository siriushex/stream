#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "SKIP: this benchmark is intended for Linux"
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

BIN="${ROOT_DIR}/stream"
if [[ ! -x "${BIN}" ]]; then
  BIN="${ROOT_DIR}/astra"
fi
if [[ ! -x "${BIN}" ]]; then
  echo "ERROR: stream/astra binary not found: ${ROOT_DIR}"
  exit 1
fi

COUNT="${COUNT:-200}"
HTTP_PORT="${HTTP_PORT:-19360}"
IN_BASE_PORT="${IN_BASE_PORT:-20000}"
OUT_BASE_PORT="${OUT_BASE_PORT:-30000}"
PPS="${PPS:-50}"
DURATION="${DURATION:-30}"

MODE="${MODE:-legacy}"
# MODE:
# - legacy: legacy pipeline, no batching
# - mmsg: legacy pipeline + recvmmsg/sendmmsg (global)
# - dp: dataplane force (Linux-only, UDP->UDP eligible only)

TMP_DIR="$(mktemp -d)"
CFG="${TMP_DIR}/passthrough.json"
LOG="${TMP_DIR}/stream.log"

cleanup() {
  if [[ -n "${STREAM_PID:-}" ]]; then
    kill "${STREAM_PID}" 2>/dev/null || true
  fi
  if [[ -n "${GEN_PID:-}" ]]; then
    kill "${GEN_PID}" 2>/dev/null || true
  fi
  rm -rf "${TMP_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

UDP_BATCHING="false"
DATAPLANE="off"
DP_WORKERS="0"
DP_AFFINITY="${DP_AFFINITY:-false}"
DP_WORKER_POLICY="${DP_WORKER_POLICY:-hash}"

case "${MODE}" in
  legacy)
    ;;
  mmsg)
    UDP_BATCHING="true"
    ;;
  dp)
    DATAPLANE="force"
    DP_WORKERS="${DP_WORKERS:-0}"
    ;;
  *)
    echo "ERROR: unknown MODE=${MODE} (expected legacy|mmsg|dp)"
    exit 1
    ;;
esac

python3 "${ROOT_DIR}/tools/perf/generate_passthrough_udp_config.py" \
  --count "${COUNT}" \
  --out "${CFG}" \
  --http-port "${HTTP_PORT}" \
  --in-addr 127.0.0.1 \
  --in-base-port "${IN_BASE_PORT}" \
  --out-addr 127.0.0.1 \
  --out-base-port "${OUT_BASE_PORT}" \
  $( [[ "${UDP_BATCHING}" == "true" ]] && echo "--udp-batching" ) \
  --dataplane "${DATAPLANE}" \
  --dp-workers "${DP_WORKERS}" \
  --dp-rx-batch 32 \
  $( [[ "${DP_AFFINITY}" == "true" || "${DP_AFFINITY}" == "1" ]] && echo "--dp-affinity" ) \
  --dp-worker-policy "${DP_WORKER_POLICY}" \
  >/dev/null

"${BIN}" scripts/server.lua -a 127.0.0.1 -p "${HTTP_PORT}" \
  --config "${CFG}" \
  --data-dir "${TMP_DIR}/data" \
  --log "${LOG}" \
  --no-web-auth \
  --no-stdout &
STREAM_PID=$!

# Wait server.
for _ in $(seq 1 100); do
  if curl -fsS "http://127.0.0.1:${HTTP_PORT}/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

echo "stream_pid=${STREAM_PID}"
echo "config=${CFG}"
echo "mode=${MODE} count=${COUNT} pps=${PPS} duration=${DURATION}s"

# Best-effort: capture metrics (prometheus format) for dataplane visibility.
METRICS_URL="http://127.0.0.1:${HTTP_PORT}/api/v1/metrics?format=prometheus"

# Start sender.
python3 "${ROOT_DIR}/tools/perf/udp_multi_sender.py" \
  --addr 127.0.0.1 \
  --base-port "${IN_BASE_PORT}" \
  --count "${COUNT}" \
  --pps "${PPS}" \
  --duration "${DURATION}" \
  >/dev/null &
GEN_PID=$!

# Snapshot + capture incident (best-effort).
OUT_DIR="${ROOT_DIR}/tools/perf/results/passthrough_$(date +%Y%m%d_%H%M%S)_${MODE}"
mkdir -p "${OUT_DIR}"
tools/perf/process_snapshot.sh "${STREAM_PID}" | tee "${OUT_DIR}/snapshot_before.txt"
curl -fsS "${METRICS_URL}" > "${OUT_DIR}/metrics_before.prom" 2>/dev/null || true

tools/perf/capture_incident.sh "${STREAM_PID}" 15 "${OUT_DIR}" || true

wait "${GEN_PID}" || true
tools/perf/process_snapshot.sh "${STREAM_PID}" | tee "${OUT_DIR}/snapshot_after.txt"
curl -fsS "${METRICS_URL}" > "${OUT_DIR}/metrics_after.prom" 2>/dev/null || true

echo "results=${OUT_DIR}"
echo "log=${LOG}"
