# Input Resilience (HTTP-TS / HLS)

This document describes network resilience for HTTP-TS and HLS inputs.

## Compatibility (important)
Nothing changes for existing configs unless you explicitly enable it:
- Global: `settings.input_resilience.enabled=true`
- Or per-input: add `#net_profile=dc|wan|bad|max|superbad` to the input URL

## What it does
- Reconnects on errors and stalls.
- Uses backoff + jitter to avoid request storms.
- Tracks input health (online/degraded/offline).
- Optional jitter buffer to smooth short gaps.

## Profiles (dc/wan/bad/max/superbad)
You can select a network profile per input:
- `dc`: stable datacenter networks
- `wan`: typical WAN between sites
- `bad`: unstable internet / poor connectivity
- `max`: aggressive profile for very unstable sources
- `superbad`: extreme profile for the worst sources (higher timeouts + larger jitter defaults)

When profiles are enabled (globally or per-input), Astral uses:
- `settings.input_resilience.profiles[profile]` as base net timeouts/backoff
- `settings.input_resilience.hls_defaults` for HLS ingest defaults (if set)
- `settings.input_resilience.jitter_defaults_ms[profile]` as default jitter (if input does not set `jitter_buffer_ms`)

Per-input URL options always override the profile defaults.

## Scheduled optimizer (optional)
If you have a stream that stays unstable even with `bad/max`, you can enable scheduled autotune per input:
- Add `#net_tune=1` to the input URL (per input).
- Schedule `tools/net_autotune.py` (cron/systemd timer) to periodically test and apply the best preset.

Example input:
```
http://host:port/stream.ts#net_tune=1&net_profile=bad
```

Example run (4 minutes per stream, sequential, minimal load):
```
python3 tools/net_autotune.py --api http://127.0.0.1:9060 --username admin --password admin --duration-sec 240
```

The script tries `bad,max,superbad` and chooses the lowest error score based on `/api/v1/stream-status`.
It only touches inputs explicitly marked with `#net_tune=1`.

## Adaptive auto-tune (optional)
For unstable sources you can enable adaptive tuning:
```
http://host:port/stream.ts#net_profile=bad&net_auto=1
```
This gradually increases timeouts and relaxes low-speed limits after repeated errors,
then slowly returns to normal when the input is stable again.

You can tune auto thresholds and relax timing:
```
http://host:port/stream.ts#net_profile=max&net_auto=1&net_auto_max_level=4&net_auto_burst=3&net_auto_relax_sec=180&net_auto_window_sec=25&net_auto_min_interval_sec=5
```

## Global defaults (Settings -> General -> Inputs)
There are two layers:
1) **Input Resilience (profiles)**: `settings.input_resilience.*` (new)
2) **Network resilience (advanced)**: legacy `settings.net_resilience` (still supported)

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

### Enable a profile per input
HTTP-TS (bad network):
```
http://host:port/stream.ts#net_profile=bad&jitter_buffer_ms=800
```

HLS (typical WAN) + HLS overrides:
```
hls://host:port/live/playlist.m3u8#net_profile=wan&hls_max_segments=10&hls_max_gap_segments=3&hls_segment_retries=3
```

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

Auto sizing (profiles enabled):
- If `jitter_buffer_ms` is set (explicitly or via profile defaults) and `jitter_max_buffer_mb` is not set,
  Astral computes a safe buffer size automatically based on an assumed bitrate for the active profile.
- Defaults are controlled by:
  - `settings.input_resilience.jitter_assumed_mbps.{dc,wan,bad,max}`
  - `settings.input_resilience.jitter_max_auto_mb`

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
