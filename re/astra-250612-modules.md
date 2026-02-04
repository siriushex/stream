# Astra 250612 Module Deep Dives (Static Analysis)

## Notes
- `http_server` details are based on repo sources (`modules/http/*`) and binary log strings.
- `srt_input` and `mux` details are derived from binary strings/xrefs only; sources are
  not present in this repo, so configuration and flow are inferred.

## http_server
### Summary
- TCP (or SCTP) HTTP server with route table. Each route entry is a callable Lua
  object or function. It dispatches requests to per-route module callbacks.

### Config Options (server)
- `addr` (string, default `0.0.0.0`)
- `port` (number, default `80`)
- `server_name` (string, default `Astra`)
- `http_version` (string, default `HTTP/1.1`)
- `sctp` (bool, default `false`)
- `route` (table, required):
  - Format: `{ { "/path", callback }, ... }`
  - Each `callback` must be a function or a table with `__call` metatable.

### Lua Methods (server instance)
- `send(client, response_table)`
  - `response_table`: `{ code, headers = {"Header: value", ...}, content }`.
- `close()` closes the server; `close(client)` closes a single client.
- `data(client)` returns/creates per-client table in registry.
- `redirect(client, location)` sends 302 with Location header.
- `abort(client, code, text?)` sends error response.

### Route Modules (common)
- `http_static`:
  - Options: `path` (required), `skip`, `block_size`, `default_mime`,
    `ts_extension`, `expires`, `headers`, `m3u_headers`, `ts_headers`.
  - Validates `path` exists and is a directory.
- `http_downstream`:
  - Options: `callback` (required).
  - Provides a TS stream handle to Lua via `request.stream`.
- `http_upstream`:
  - Options: `callback` (required).
  - `buffer_size`/`buffer_fill` accepted but deprecated.
- `http_websocket`:
  - Options: `callback` (required).
- `http_redirect`:
  - Options: `location` (required), `code` (default 302).

### Flow (inferred)
- Bind socket and listen (`addr`, `port`), accept clients.
- Parse HTTP request and dispatch to matching route.
- Route callback writes headers/body or streams TS data.
- Logs include bind/accept failures and client send/recv errors.

### Ghidra Function Anchors (binary)
- `FUN_00496e30`, `FUN_00496fc0`, `FUN_00497700`, `FUN_00497720`,
  `FUN_00497ba0`, `FUN_00498da0`, `FUN_00498860`.

## srt_input
### Summary
- SRT input module for ingesting transport stream data over SRT sockets.

### Required Options (from strings)
- `name` (required)

### Observed SRT Socket Options (from log strings)
- `SRTO_RCVSYN` (receive sync)
- `SRTO_TRANSTYPE` (transtype)
- `SRTO_TSBPDMODE` (TSBPD)
- `SRTO_PBKEYLEN` (PBK length)
- passphrase (`SRTO_PASSPHRASE`), length 10-79 chars
- `SRTO_LATENCY`
- `SRTO_PACKETFILTER`
- `SRTO_OHEADBW` (5-100)
- `SRTO_SNDBUF`, `SRTO_RCVBUF`
- `SRTO_STREAMID`
- `SRTO_LIVE` (live mode)
- stats output / stats timer

### Flow (inferred)
- Open SRT socket and apply options.
- Bind/listen in listener mode, or connect in caller mode.
- Use epoll for read readiness and a timer for stats.
- On receive timeout, logs and restarts input.
- Errors include connection closed, bind/connect failures, epoll init failure.

### Ghidra Function Anchors (binary)
- `FUN_004673e0`, `FUN_004673f0`, `FUN_004688a0`

## mux
### Summary
- Transport stream muxer that works with PID mappings and PSI remuxing.

### Required Options (from strings)
- `name` (required)
- `mux` / `pid` appear in error strings (likely required in some configs)
- `remux_eit` toggle (UI string present)
- `mux_pid` config hint in binary strings

### Flow (inferred)
- Attaches to stream demux (`module_stream_demux_set` required).
- Joins/leaves PIDs dynamically, with safeguards for double-leave.
- Remuxes PSI tables (PAT/PMT/SDT/EIT) and optionally EIT.

### Ghidra Function Anchors (binary)
- `FUN_00459760`, `FUN_00459e80`, `FUN_00460ae0`, `FUN_00463910`,
  `FUN_0046f2e0`, `FUN_00470f90`
