# HLS memfd (in-memory) storage

## What it does
- Keeps HLS segments and playlists in memory (no disk I/O).
- Uses Linux `memfd` + `sendfile()` for low-CPU segment delivery when available.
- Generates HLS only when clients request `/hls/<id>/...` (on-demand), then idles and frees memory after a timeout.
- Preserves existing URL shape: `/hls/<stream_id>/index.m3u8` and segment filenames.

## Settings
- `hls_storage`: `"disk"` | `"memfd"` (default `"disk"`).
- `hls_on_demand`: boolean (default `true` when `hls_storage=memfd`).
- `hls_idle_timeout_sec`: seconds before deactivating on-demand HLS (default `30`).
- `hls_max_bytes_per_stream`: memory cap for segments (default `67108864` / 64MB).
- `hls_max_segments`: max segments to keep (default `hls_cleanup` / `window*2`).

Per-stream override is supported via the HLS output config (`storage`, `on_demand`, `idle_timeout_sec`, `max_bytes`, `max_segments`).

## Example config (memfd + on-demand)
```json
{
  "settings": {
    "http_play_hls": true,
    "hls_storage": "memfd",
    "hls_on_demand": true,
    "hls_idle_timeout_sec": 30,
    "hls_max_bytes_per_stream": 67108864,
    "hls_max_segments": 12,
    "hls_duration": 2,
    "hls_quantity": 5
  },
  "make_stream": [
    {
      "id": "hls_demo",
      "name": "HLS Demo",
      "type": "udp",
      "enable": true,
      "input": ["udp://127.0.0.1:13000"],
      "output": []
    }
  ]
}
```

## Verification (minimal)
1. Start a test input and Stream Hub:
   - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
       -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts \
       "udp://127.0.0.1:13000?pkt_size=1316" &`
   - `./astra ./tmp_hls_memfd.json -p 9027 --data-dir ./data_hls_memfd --web-dir ./web &`
2. Request HLS:
   - `curl -s http://127.0.0.1:9027/hls/hls_demo/index.m3u8 | head -n 5`
   - `segment=$(curl -s http://127.0.0.1:9027/hls/hls_demo/index.m3u8 | grep -v '^#' | head -n 1)`
   - `curl -I "http://127.0.0.1:9027/hls/hls_demo/${segment}" | head -n 1`
3. Confirm **no files** created in `hls_dir`:
   - `ls -la ./data_hls_memfd/hls/hls_demo` (should be empty or missing)
4. Wait for idle timeout and confirm deactivation (logs):
   - Expect `[hls_output] HLS deactivate stream=hls_demo reason=idle`.

## Load sanity
- 10 clients reading the same playlist/segment:
  - `for i in $(seq 1 10); do curl -s http://127.0.0.1:9027/hls/hls_demo/index.m3u8 >/dev/null & done`
  - `segment=$(curl -s http://127.0.0.1:9027/hls/hls_demo/index.m3u8 | grep -v '^#' | head -n 1)`
  - `for i in $(seq 1 10); do curl -s "http://127.0.0.1:9027/hls/hls_demo/${segment}" >/dev/null & done`

## Notes / limitations
- `memfd` is Linux-only; when unavailable, Stream Hub falls back to in-memory buffers with a warning.
- Disk HLS (`hls_storage="disk"`) is unchanged and still served by `http_static`.
- On-demand mode suppresses HLS generation until a `/hls/<id>/...` request is seen.
- `debug_hold_sec` is a test-only option and is available only when compiled with `-DHLS_MEMFD_DEBUG`.

## Smoke script
- Run from repo root (Linux recommended):
  - `tools/hls_memfd_smoke.sh`

## Status counters
- `GET /api/v1/stream-status/<id>` now includes:
  - `current_segments`: number of in-memory HLS segments for the stream.
  - `current_bytes`: total bytes of in-memory HLS segments for the stream.
