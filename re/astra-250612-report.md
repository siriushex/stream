# Astra 250612 Reverse Engineering Report (Static Analysis)

## Scope and Inputs
- Binary: astra/astra-250612 (ELF64 x86-64, static, stripped)
- Tools: Ghidra headless maps (xref, func map, call graph), rizin/strings
- Notes: no debug symbols; function names are Ghidra auto-labels (FUN_*)

## Build and Library Fingerprint
- Version string: "Astra (commit:c8d87eba date:2025-06-12 lua:Lua 5.2)"
- Toolchain: GCC 11.4.0 (Ubuntu 22.04), glibc 2.35
- Embedded or linked libs (from strings and contrib paths):
  - Lua 5.2.3
  - libuv (contrib/libuv sources)
  - OpenSSL 1.1.1w
  - zlib 1.3 (inflate 1.3)
  - SRT core (contrib/srt/srtcore)
  - pthread/dl (static glibc)

## Runtime Architecture (Inferred)
- Main flow anchors:
  - `FUN_00418010` logs "[main] Starting/Reload/Exit"
  - `FUN_00436490` manages PID file creation
  - `FUN_00436670` initializes Lua (luaL_newstate, version string)
  - `FUN_004476e0` uses "luaopen_%s" to load modules
  - Event loop and sockets: `core/loop.c`, `core/socket.c` (libuv-backed)
- CLI/systemd commands:
  - `FUN_00438450` prints general usage (help, version, init/remove/reset-password)
  - `FUN_00438480` systemd init command
  - `FUN_00438800` systemd remove command
  - `FUN_00438a10` reset-password command

## Compiled Modules (Source Path Evidence)
- modules/asi/input.c
- modules/astra/exec.c
- modules/astra/timer.c
- modules/dvb/ci.c
- modules/dvb/input.c
- modules/dvb/it950x.c
- modules/epg/export.c
- modules/file/input.c
- modules/file/output.c
- modules/http/input.c
- modules/http/request.c
- modules/http/server.c
- modules/http/server/downstream.c
- modules/http/server/hls.c
- modules/http/server/playlist_icon.c
- modules/http/server/static.c
- modules/http/server/stream.c
- modules/http/server/websocket.c
- modules/media/aspect.c
- modules/mpegts/analyze.c
- modules/mpegts/channel.c
- modules/mpegts/gorynich.c
- modules/mpegts/transmit.c
- modules/mpts/mpts.c
- modules/mux/mux.c
- modules/resi/resi.c
- modules/rtsp/input.c
- modules/sessions/auth.c
- modules/softcam/cam/newcamd.c
- modules/softcam/decrypt.c
- modules/srt/input.c
- modules/srt/output.c
- modules/stream/stream.c
- modules/t2mi/t2mi.c
- modules/tbs/tbsmod.c
- modules/udp/input.c
- modules/udp/output.c

## Web UI and HTTP
- HTTP server module present: `modules/http/server.c` + downstream/hls/stream/static/websocket.
- Static asset server: strings "http_server/static", "http_server_static".
- UI assets embedded: Vue bundle and `app.js` strings in the binary.
- HTTP server function anchors (xref):
  - `FUN_00496e30`, `FUN_00496fc0`, `FUN_00497700`, `FUN_00497720`,
    `FUN_00497ba0`, `FUN_00498da0`, `FUN_00498c60`, `FUN_00498860`
  - Static server: `FUN_004a54c0`, `FUN_004a54d0`, `FUN_004a5530`

## Streaming Inputs and Outputs (Function Anchors)
- HLS/playlist:
  - Strings: "playlist", "%s/index.m3u8"
  - Functions: `FUN_00487af0`, `FUN_00487b70`, `FUN_00487be0`,
    `FUN_0049e2e0`, `FUN_004a1370`, `FUN_004a1480`
- RTSP input:
  - Functions: `FUN_0045a610`, `FUN_0045b310`, `FUN_0045b320`, `FUN_0045c0f0`
- SRT input/output:
  - Input: `FUN_004673e0`, `FUN_004673f0`, `FUN_004688a0`
  - Output: `FUN_0046aac0`
- UDP input/output:
  - Input: `FUN_00463bf0`, `FUN_00463e80`, `FUN_004645b0`
  - Output: `FUN_00464b90`, `FUN_00464ba0`
- File input/output:
  - Input: `FUN_00461df0`, `FUN_00461e00`
  - Output: `FUN_00462b10`, `FUN_00462b20`, `FUN_00462bf0`,
    `FUN_00462fd0`, `FUN_00462ff0`, `FUN_00463320`, `FUN_00463450`

## DVB/ASI and TS Processing (Function Anchors)
- DVB input:
  - `FUN_004887c0`, `FUN_00488830`, `FUN_00488920`, `FUN_00488980`,
    `FUN_004889e0`, `FUN_00488a40`, `FUN_00488b10`, `FUN_00488e60`,
    `FUN_004897a0`
- DVB CI/CA:
  - `FUN_00482ac0` (CI)
  - `FUN_0048a900`, `FUN_0048ab90`, `FUN_0048ac30`, `FUN_0048b4e0`,
    `FUN_0048bb10`, `FUN_0048bd20`, `FUN_0048bec0`, `FUN_0048c0c0`,
    `FUN_0048c690`, `FUN_0048d340`, `FUN_0048d690`
- ASI input:
  - `FUN_00474040`, `FUN_00474050`, `FUN_00474120`, `FUN_00474160`,
    `FUN_00474650`, `FUN_00474730`
- MPTS/MUX/T2MI:
  - MPTS: `FUN_0046f6c0`, `FUN_00470f90`
  - MUX: `FUN_00459760`, `FUN_00459e80`, `FUN_00460ae0`,
    `FUN_00463910`, `FUN_0046f2e0`, `FUN_00470f90`
  - T2MI: `FUN_004734f0`, `FUN_00473820`, `FUN_00473980`

## Softcam/Decrypt (Function Anchors)
- Modules: `modules/softcam/cam/newcamd.c`, `modules/softcam/decrypt.c`
- Functions: `FUN_00474a40`, `FUN_00474dd0`, `FUN_00474ea0`,
  `FUN_00475530`, `FUN_004757c0`, `FUN_00475bc0`, `FUN_00476270`,
  `FUN_004762c0`, `FUN_00478310`

## EPG and Analyze
- Modules: `modules/epg/export.c`, `modules/mpegts/analyze.c`
- Functions: `FUN_0045e690`, `FUN_0045e6a0`, `FUN_0045ec30`,
  `FUN_0045ffb0`, `FUN_0045ffc0`, `FUN_00460090`

## Call Graph Samples (Partial)
- `FUN_00498da0` (http_server receive):
  - Calls `FUN_004267d0` (x11), `FUN_00426320` (x10), `FUN_00425ff0` (x5)
- `FUN_004688a0` (srt_input):
  - Calls `FUN_004369e0` (x7), `FUN_00436af0` (x7),
    `thunk_FUN_0087ddc0` (x6), `FUN_00427fd0` (x5)
- `FUN_00487be0` (playlist):
  - Calls `FUN_0087dc90` (x5), `FUN_00439580` (x4), `FUN_0043b050` (x4)
- `FUN_0045a610` (rtsp_input):
  - Calls `thunk_FUN_0087ee90` (x12), `FUN_00428170` (x8)
  - Caller: `FUN_0045ca20` (x1)
- Missing direct callers on many functions suggests callback or Lua-driven dispatch.

## Limitations
- Static stripped binary; symbol names are not preserved.
- Call graph is incomplete for callback-based and Lua-driven control flow.
- Some modules may be compiled in but inactive depending on config.
