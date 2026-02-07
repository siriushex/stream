# Input Resilience (HTTP-TS / HLS)

This document describes network resilience for HTTP-TS and HLS inputs.

## What it does
- Reconnects on errors and stalls.
- Uses backoff + jitter to avoid request storms.
- Tracks input health (online/degraded/offline).
- Optional jitter buffer to smooth short gaps.

## Global defaults (Settings -> General -> Inputs)
These defaults apply to all HTTP/HLS inputs unless overridden in the input URL.

Recommended safe defaults (already set):
- connect_timeout_ms: 3000
- read_timeout_ms: 8000
- stall_timeout_ms: 5000
- max_retries: 10 (0 = infinite with backoff)
- backoff_min_ms: 500
- backoff_max_ms: 10000
- backoff_jitter_pct: 20
- low_speed_limit_bytes_sec: 1024
- low_speed_time_sec: 5
- keepalive: false
- dns_cache_ttl_sec: 0

## Per-input overrides (URL options)
Add options to the input URL with `#key=value`.

HTTP-TS example:
```
http://user:pass@host:port/stream.ts#connect_timeout_ms=3000&read_timeout_ms=8000&stall_timeout_ms=5000&max_retries=0&backoff_min_ms=500&backoff_max_ms=10000&backoff_jitter_pct=20&low_speed_limit_bytes_sec=1024&low_speed_time_sec=5&keepalive=1
```

HLS example:
```
hls://user:pass@host:port/live/playlist.m3u8#read_timeout_ms=8000&stall_timeout_ms=5000&max_retries=0&backoff_min_ms=500&backoff_max_ms=10000&backoff_jitter_pct=20
```

Jitter buffer (optional):
```
http://host:port/stream.ts#jitter_buffer_ms=500&jitter_max_buffer_mb=4
```

## Health and metrics
Each input reports:
- `health_state`: online / degraded / offline
- `health_reason`: last error or degrade reason
- `net.*`: state, backoff, reconnects, last_error, last_recv_ts
- `hls.*`: state, last_seq, segment_errors_total, gap_count
- `jitter.*`: buffer_fill_ms, buffer_target_ms, buffer_underruns_total

These are visible in the Analyze modal input rows and in the API stream status.

## Suggested profiles
- Home / unstable ISP: increase `stall_timeout_ms` to 8000-12000, keep `backoff_max_ms` at 10000.
- Datacenter / clean WAN: keep defaults; consider `keepalive=1`.
- Satellite -> IP: enable jitter buffer 500-1200 ms and `max_retries=0`.

## Notes
- Backoff with jitter prevents request storms.
- If `max_retries=0`, reconnects continue with backoff indefinitely.
- Jitter buffer trades latency for stability; keep it off unless needed.
