# Astra 250612 Clean-Room Compatibility Spec (Static Analysis)

## Purpose
This document is a clean-room compatibility guide based on static analysis of
`astra/astra-250612`. It cannot recreate the original source code, but it
captures enough structure to build a compatible implementation.

## Constraints and Gaps
- Stripped static binary: no symbols, types, or original file layout.
- Call graph is incomplete for callbacks and Lua-driven dispatch.
- Config schema and HTTP API are only partially visible from strings.
- Dynamic behavior (runtime options, defaults) requires live observation.

## Build and Library Fingerprint
- Version string: "Astra (commit:c8d87eba date:2025-06-12 lua:Lua 5.2)"
- Toolchain: GCC 11.4.0 (Ubuntu 22.04), glibc 2.35
- Embedded or linked libs:
  - Lua 5.2.3
  - libuv (contrib/libuv)
  - OpenSSL 1.1.1w
  - zlib 1.3 (inflate 1.3)
  - SRT core (contrib/srt/srtcore)

## Runtime Architecture (Inferred)
- Startup flow:
  - Main entry logs "[main] Starting/Reload/Exit".
  - Lua VM is initialized and modules are registered via "luaopen_%s".
  - Event loop and sockets are libuv-backed (`core/loop.c`, `core/socket.c`).
- Modules are Lua-callable and appear to provide inputs, outputs, and services.
- Many functions are invoked via callbacks or Lua dispatch (no direct callers).

## CLI Commands (Observed)
- `help` / `-h`: print usage.
- `version` / `-v`: print version.
- `init [PORT [NAME]]`: register systemd service.
- `remove [NAME]`: remove systemd service.
- `reset-password`: request reset from running instance.

## Module Inventory (Source Path Evidence)
See `astra/re/astra-250612-report.md` for the full module list; key families:
- HTTP server (static, HLS, downstream, websocket, stream)
- UDP, SRT, RTSP, file inputs/outputs
- DVB/ASI, MPTS, MUX, T2MI
- Softcam/newcamd + decrypt
- EPG export, MPEG-TS analyze

## Required Options by Module (from error strings)
These are the minimum fields that trigger "option required" errors.
- analyze: `name`
- asi_input: `adapter`
- channel: `name`
- channel %s: `custom_pmt`, `define_pid`, `lang`, `map`, `order`
- ci %d:%d: `adapter`
- decrypt: `name`
- dvb_input %d:%d: `diseqc`
- epg_export: `name`
- epg_export %s: `callback`
- exec: `cmd`
- file_input: `name`
- file_output: `filename`
- http_downstream: `callback`
- http_input: `name`
- http_request %s:%d%s: `callback`, `host`
- http_static: `path`
- http_websocket: `callback`
- mpts: `name`
- mpts %s: `country`, `pat_interval`, `upstream`
- mux: `name`
- mux %s: `mux`, `pid`
- newcamd: `name`
- newcamd %s: `host`, `pass`, `port`, `user`
- rtsp_input: `name`
- session_auth_backend: `callback`, `url`
- srt_input: `name`
- srt_output: `name`
- timer: `callback`, `interval`
- udp_input: `name`
- udp_output: `name`

## Behavioral Hints by Area
- HTTP server: log prefix `[http_server %s:%d]` with client lifecycle, send/recv,
  bind errors, TLS/SSL allocation failure.
- Static web: log prefix `[http_static]`, requires `path`.
- HLS/playlist: strings include `playlist`, `playlist_name`, `%s/index.m3u8`.
- SRT: extensive error messages for socket setup, password length, latency,
  stats timers, receive timeouts.
- RTSP: SDP parsing errors (`parse_m`, `parse_rtpmap`, `parse_fmtp`).
- DVB/ASI: frontend lock and CA/CI errors with detailed status logging.

## Minimal Compatibility Roadmap
1. Recreate CLI commands (help/version/init/remove/reset-password).
2. Build a Lua host runtime and module registration system (luaopen_%s).
3. Implement HTTP server with static + HLS/playlist + websocket endpoints.
4. Implement core inputs/outputs (UDP, SRT, RTSP, file).
5. Add DVB/ASI stack and TS processing (MUX/MPTS/T2MI) if needed.
6. Add optional softcam/newcamd and EPG export.

## What Is Still Needed (Dynamic Verification)
- Full HTTP API route list and payload schemas.
- Default config values and runtime behavior for options.
- Lua module interface signatures (function names, arguments, return values).
