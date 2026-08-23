# Changelog

## 1.3.0 - 2026-08-23

- Isolate partial Newcamd CW state per service and connection generation.
- Detect Newcamd correctly when compiling against OpenSSL 3.
- Align guarded odd/even CW application with the shift-buffer packet boundary.
- Pace native HLS from PCR media time and make prebuffering stateful.
- Prevent active HLS segment duplication during playlist refresh.
- Add PAT/PMT/A/V-aware HTTP buffer failover and stable recovery probing.
- Preserve and fully drain MPEG-TS payloads coalesced with fast HTTP responses.
- Add optional ownership-safe publication of buffer outputs to the dashboard.
- Record release commit, build time, and binary SHA-256 in bundles.
- Refresh pinned FFmpeg release assets and checksums for reproducible bundles.
