#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HTTP_PORT=19000
HLS_PORT=19001
ASTRA_PORT=19010

ASTRA_BIN="${ROOT_DIR}/astral"
if [[ ! -x "${ASTRA_BIN}" ]]; then
  echo "WARN: ${ASTRA_BIN} not found/executable; mock servers only."
fi

python3 "$ROOT_DIR/tools/tests/mock_http_ts.py" --port "$HTTP_PORT" --drop-after 3 --quiet &
HTTP_PID=$!
python3 "$ROOT_DIR/tools/tests/mock_hls_server.py" --port "$HLS_PORT" --missing-seq 2 --quiet &
HLS_PID=$!
ASTRA_PID=""
TMP_DIR=""

cleanup() {
  if [[ -n "${ASTRA_PID}" ]]; then
    kill "${ASTRA_PID}" 2>/dev/null || true
  fi
  kill "$HTTP_PID" "$HLS_PID" 2>/dev/null || true
  if [[ -n "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

sleep 1
curl -I "http://127.0.0.1:${HTTP_PORT}/stream.ts" >/dev/null
curl -s "http://127.0.0.1:${HLS_PORT}/playlist.m3u8" | head -n 5

echo "Mock servers OK. Use these URLs in Astral inputs:"
echo "  http://127.0.0.1:${HTTP_PORT}/stream.ts"
echo "  hls://127.0.0.1:${HLS_PORT}/playlist.m3u8"

if [[ -x "${ASTRA_BIN}" ]]; then
  TMP_DIR="$(mktemp -d)"
  CFG="${TMP_DIR}/resilience.json"

  cat >"${CFG}" <<EOF
{
  "settings": {
    "input_resilience": {
      "enabled": false,
      "default_profile": "wan"
    }
  },
  "make_stream": [
    {
      "id": "res_http_default",
      "type": "udp",
      "enable": true,
      "input": ["http://127.0.0.1:${HTTP_PORT}/stream.ts"],
      "output": []
    },
    {
      "id": "res_http_bad",
      "type": "udp",
      "enable": true,
      "input": ["http://127.0.0.1:${HTTP_PORT}/stream.ts#net_profile=bad&jitter_buffer_ms=800"],
      "output": []
    },
    {
      "id": "res_hls_wan",
      "type": "udp",
      "enable": true,
      "input": ["hls://127.0.0.1:${HLS_PORT}/playlist.m3u8#net_profile=wan&hls_max_segments=10&hls_segment_retries=3"],
      "output": []
    }
  ]
}
EOF

  "${ASTRA_BIN}" scripts/server.lua -a 127.0.0.1 -p "${ASTRA_PORT}" \
    --config "${CFG}" \
    --data-dir "${TMP_DIR}/data" \
    --web-dir "${ROOT_DIR}/web" \
    --log "${TMP_DIR}/astra.log" \
    --no-stdout &
  ASTRA_PID=$!

  for _ in $(seq 1 50); do
    if curl -fsS "http://127.0.0.1:${ASTRA_PORT}/api/v1/stream-status/res_http_default" >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
  done

  echo "Checking stream-status fields..."
  curl -fsS "http://127.0.0.1:${ASTRA_PORT}/api/v1/stream-status/res_http_default" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); i=(d.get("inputs") or [{}])[0]; assert i.get("resilience_enabled") in (False,None); print("res_http_default: OK")'
  curl -fsS "http://127.0.0.1:${ASTRA_PORT}/api/v1/stream-status/res_http_bad" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); i=(d.get("inputs") or [{}])[0]; assert i.get("resilience_enabled") is True; assert i.get("net_profile_effective") == "bad"; print("res_http_bad: OK")'
  curl -fsS "http://127.0.0.1:${ASTRA_PORT}/api/v1/stream-status/res_hls_wan" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); i=(d.get("inputs") or [{}])[0]; assert i.get("resilience_enabled") is True; assert i.get("net_profile_effective") == "wan"; print("res_hls_wan: OK")'
fi
