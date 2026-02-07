#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HTTP_PORT=19000
HLS_PORT=19001

python3 "$ROOT_DIR/tools/tests/mock_http_ts.py" --port "$HTTP_PORT" --drop-after 3 --quiet &
HTTP_PID=$!
python3 "$ROOT_DIR/tools/tests/mock_hls_server.py" --port "$HLS_PORT" --missing-seq 2 --quiet &
HLS_PID=$!

cleanup() {
  kill "$HTTP_PID" "$HLS_PID" 2>/dev/null || true
}
trap cleanup EXIT

sleep 1
curl -I "http://127.0.0.1:${HTTP_PORT}/stream.ts" >/dev/null
curl -s "http://127.0.0.1:${HLS_PORT}/playlist.m3u8" | head -n 5

echo "Mock servers OK. Use these URLs in Astral inputs:"
echo "  http://127.0.0.1:${HTTP_PORT}/stream.ts"
echo "  hls://127.0.0.1:${HLS_PORT}/playlist.m3u8"
