# Description

Astra (Advanced Streamer) is a professional software to organize Digital TV Service for
TV operators and broadcasters, internet service providers, hotels, etc.

* Learn more: https://cesbo.com/astra/
* Community: http://forum.cesbo.com/

## Quick start (local build)
- From `astra/`:
  - `./configure.sh` (see `./configure.sh --help` for all options)
  - `make`
  - Optional: `make install` (installs to `--bin`, default `/usr/bin/astra`)
- Binary: `./astra`
- NOTE: `configure.sh` regenerates `Makefile` and `config.h`.

## Docs
- `docs/ARCHITECTURE.md` - module map and data flow.
- `docs/PARITY.md` - feature parity matrix.
- `docs/ROADMAP.md` - staged improvement plan.
- `docs/TESTING.md` - local and server smoke tests.
- `docs/OPERATIONS.md` - systemd and ops basics.
- `docs/TRANSCODE_BUNDLE.md` - bundled ffmpeg/ffprobe packaging.
- `docs/API.md` - current HTTP API reference.
- `docs/CLI.md` - CLI modes and examples.
- `docs/ASTRAL_AI.md` - AstralAI overview and safety rules.

## UI brand assets
- Source icon: `web/assets/icons/stream-hub.svg`
- Render PNG/ICO set:
  - `python3 tools/branding/render_stream_hub_icons.py --svg web/assets/icons/stream-hub.svg --out web/assets/icons`
- Generated files include favicon and PWA sizes (16..512 + apple-touch icon).

## Run UI/API server
- `./astra scripts/server.lua [options]`
- `./astra <config.json|config.lua> [options]` (auto-runs `scripts/server.lua --config <path>`)
- Options (see `scripts/server.lua`):
  - `-a ADDR`, `-p PORT`
  - `--data-dir PATH`, `--db PATH`
  - `--web-dir PATH`
  - `--hls-dir PATH`, `--hls-route PATH`
  - `--config PATH`
  - `--import PATH`, `--import-mode merge|replace` (legacy alias)
- Defaults: addr `0.0.0.0`, port `8000`, data dir `./data`, web dir `./web`,
  HLS route `/hls`.
- First run creates SQLite `./data/astra.db` and default admin `admin`/`admin`.
- If `--config` points to a missing file, Astra creates it with default values.
- If `--data-dir` is not provided for a config run, Astra uses `<config>.data`
  next to the config file.
- The server persists `http_port`, `hls_dir`, and `hls_base_url` in SQLite; if set,
  they override defaults on next run.
  - NOTE: when `-p` is specified, the CLI port takes priority over stored `http_port`.

## UI preferences
- Use the top-bar "View" menu to switch between Table, Compact, and Cards layouts.
- Theme can be Light, Dark, or Auto (system); both view/theme are stored in
  localStorage keys `astra.viewMode` and `astra.theme`.

## PNG to Stream (reserve TS)
- UI: Edit stream → Transcode → PNG to Stream.
- Generate a short MPEG-TS from a PNG + audio (silence/beep/MP3).
- Use "Analyze main stream" to pull default codec/resolution/fps via ffprobe.
- After "Generate TS", add the file to INPUT LIST as a backup source (file://...).

## Create radio (audio + PNG → UDP TS)
- UI: Edit stream → Transcode → Create radio.
- Starts ffmpeg to mux audio stream with a static PNG into UDP MPEG-TS.
- Use Start/Stop/Restart to control the background process.
- Output URL can be added to INPUT LIST for backup/bridge workflows.

## CLI apps (public)
- Global options (from `scripts/base.lua`): `-h/--help`, `-v/--version`, `--pid`,
  `--syslog`, `--log`, `--no-stdout`, `--color`, `--debug`.
- Built-in apps (from `modules/inscript/inscript.c`):
  - `./astra --stream` (stream runtime; built-in stream app).
  - `./astra --relay` or `--xproxy` (HTTP relay).
  - `./astra --analyze` (MPEG-TS analyzer; see `-n` and URL formats).
  - `./astra --dvbls` (DVB adapter list).
  - `./astra --femon` (frontend monitor).
- Script entrypoints (same runtime, editable files):
  - `./astra scripts/server.lua`
  - `./astra scripts/relay.lua`
  - `./astra scripts/analyze.lua`
  - `./astra scripts/femon.lua`
  - `./astra scripts/export.lua`
  - `./astra scripts/lint.lua --config <path>` (config lint)
  - any custom script path

## HTTP API (public)
- Auth: `POST /api/v1/auth/login` (JSON `{username,password}`); response includes
  token and `astra_session` cookie. Auth header also accepts
  `Authorization: Bearer <token>`.
- Logout: `POST /api/v1/auth/logout`.
- Streams: `GET/POST /api/v1/streams`, `GET/PUT/DELETE /api/v1/streams/<id>`.
- Adapters: `GET/POST /api/v1/adapters`, `GET/PUT/DELETE /api/v1/adapters/<id>`.
- Status: `GET /api/v1/adapter-status`, `GET /api/v1/adapter-status/<id>`,
  `GET /api/v1/stream-status`, `GET /api/v1/stream-status/<id>`.
- Stream status payload adds `active_input_index` (0-based), `inputs[]` with
  URL/state/bitrate/last_ok, and `last_switch` (failover metadata).
- Sessions/logs/settings: `GET /api/v1/sessions?stream_id=&login=&ip=&text=&limit=&offset=`,
  `DELETE /api/v1/sessions/<id>`, `GET /api/v1/logs?since=&limit=&level=&text=&stream_id=`,
  `GET/PUT /api/v1/settings`.
- Access log: `GET /api/v1/access-log?since=&limit=&event=&stream_id=&ip=&login=&text=`.
- Health: `GET /api/v1/health/process`, `/api/v1/health/inputs`, `/api/v1/health/outputs`.
- Metrics: `GET /api/v1/metrics` (summary counters; requires auth; add
  `?format=prometheus` for text export).
  - Includes `lua_mem_kb` and `perf` timings (`refresh_ms`, `status_ms`,
    `status_one_ms`, `adapter_refresh_ms`) for basic profiling.
  - Prometheus adds `astra_lua_mem_kb` and `astra_perf_*_ms` gauges.
- Tools: `GET /api/v1/tools` (resolved ffmpeg/ffprobe paths and versions).
- Audit log: `GET /api/v1/audit?since=&limit=&action=&actor=&target=&ip=&ok=` (admin-only).
- Users: `GET /api/v1/users`, `POST /api/v1/users`, `PUT /api/v1/users/<username>`,
  `POST /api/v1/users/<username>/reset` (admin-only).
- Import/export/restart: `POST /api/v1/import`, `GET /api/v1/export`, `POST /api/v1/restart`.
- Transcode/alerts: `GET /api/v1/transcode-status`, `GET /api/v1/transcode-status/<id>`,
  `POST /api/v1/transcode/<id>/restart`, `GET /api/v1/alerts`.
- HLSSplitter: `GET/POST /api/v1/splitters`, `GET/PUT/DELETE /api/v1/splitters/<id>`,
  `GET/POST /api/v1/splitters/<id>/links`, `PUT/DELETE /api/v1/splitters/<id>/links/<link_id>`,
  `GET/POST /api/v1/splitters/<id>/allow`, `DELETE /api/v1/splitters/<id>/allow/<rule_id>`,
  `GET /api/v1/splitters/<id>/config`,
  `POST /api/v1/splitters/<id>/start|stop|restart|apply-config`,
  `GET /api/v1/splitter-status`, `GET /api/v1/splitter-status/<id>`.
- Buffer (HTTP TS): `GET/POST /api/v1/buffers/resources`,
  `GET/PUT/DELETE /api/v1/buffers/resources/<id>`,
  `GET/POST /api/v1/buffers/resources/<id>/inputs`,
  `PUT/DELETE /api/v1/buffers/resources/<id>/inputs/<input_id>`,
  `GET/POST /api/v1/buffers/allow`, `DELETE /api/v1/buffers/allow/<rule_id>`,
  `POST /api/v1/buffers/reload`, `POST /api/v1/buffers/<id>/restart-reader`,
  `GET /api/v1/buffer-status`, `GET /api/v1/buffer-status/<id>`.
- Token auth: `GET /api/v1/sessions?type=auth`, `GET /api/v1/auth-debug/session` (admin),
  `GET /api/v1/alerts?type=auth`.
- Servers: `POST /api/v1/servers/test` (test remote server health/login).
- NOTE: all endpoints except login/logout require a valid session; unauthorized
  returns 401.
- NOTE: if `http_csrf_enabled` is on, state-changing requests that rely on the
  `astra_session` cookie must send `X-CSRF-Token` equal to the session token.
  Bearer `Authorization` skips the CSRF check.

## Config and settings
- SQLite config store lives in `./data/astra.db` by default.
- Settings are stored via `/api/v1/settings` and used by `scripts/server.lua` and
  `scripts/stream.lua`.
- Watchdog alerts are stored in SQLite (`alerts` table) and exposed via `/api/v1/alerts`.
- Auth audit events are stored in SQLite (`audit_log` table) and exposed via
  `/api/v1/audit` (admin-only).
  - Keys used in the current code (see `scripts/server.lua` and `scripts/stream.lua`
  for defaults and exact behavior):
  - HLS: `hls_dir`, `hls_base_url`, `hls_duration`, `hls_quantity`, `hls_cleanup`,
    `hls_naming`, `hls_round_duration`, `hls_resource_path`, `hls_pass_data`,
    `hls_ts_extension`, `hls_ts_mime`, `hls_use_expires`, `hls_m3u_headers`,
    `hls_ts_headers`, `hls_session_timeout`, `hls_storage`, `hls_on_demand`,
    `hls_idle_timeout_sec`, `hls_max_bytes_per_stream`, `hls_max_segments`.
  - HTTP Play: `http_play_allow`, `http_play_hls`, `http_play_port`,
    `http_play_no_tls`, `http_play_playlist_name`, `http_play_arrange`,
    `http_play_buffer_kb`, `http_play_m3u_header`, `http_play_xspf_title`,
    `http_play_logos`, `http_play_screens`.
  - Buffer: `buffer_enabled`, `buffer_listen_host`, `buffer_listen_port`,
    `buffer_source_bind_interface`, `buffer_max_clients_total`,
    `buffer_client_read_timeout_sec`.
  - HTTP Auth: `http_auth_enabled`, `http_auth_users`, `http_auth_allow`,
    `http_auth_deny`, `http_auth_tokens`, `http_auth_realm`.
  - Auth/session: `auth_session_ttl_sec`, `http_csrf_enabled`,
    `rate_limit_login_per_min`, `rate_limit_login_window_sec`.
  - Password policy: `password_min_length`, `password_require_letter`,
    `password_require_number`, `password_require_symbol`, `password_require_mixed_case`,
    `password_disallow_username`.
  - Log retention (UI buffers): `log_max_entries`, `log_retention_sec`,
    `access_log_max_entries`, `access_log_retention_sec`.
  - InfluxDB export: `influx_enabled`, `influx_url`, `influx_org`, `influx_bucket`,
    `influx_token`, `influx_interval_sec`, `influx_instance`, `influx_measurement`.
  - Transcode tools: `ffmpeg_path`, `ffprobe_path` (optional overrides).
  - Stream defaults: `no_data_timeout_sec`, `probe_interval_sec`, `stable_ok_sec`,
    `backup_initial_delay_sec`, `backup_start_delay_sec`, `backup_return_delay_sec`,
    `backup_stop_if_all_inactive_sec`, `backup_active_warm_max`, `http_keep_active`.
  - Groups: `groups` (array of `{id,name}` used for playlist group-title).
  - Servers: `servers` (array of `{id,name,host,port,login,password,enabled}`).
  - Telegram alerts: `telegram_enabled`, `telegram_level`, `telegram_bot_token`, `telegram_chat_id`.
- NOTE: policy is enforced on user create/reset; defaults require min length 8,
  at least one letter + number, and no spaces. Default admin remains `admin`
  until changed.
- NOTE: log buffers are in-memory; defaults are 2000 entries and 86400 seconds
  for both logs. Set a limit to `0` to disable it (not recommended). File logs
  from `--log` are not rotated by Astra; use logrotate/systemd.

## HLSSplitter service (managed)
- Astra can manage an external `hlssplitter` process as a service (no code changes
  to hlssplitter itself).
- Binary discovery order:
  - `./hlssplitter/hlssplitter`
  - `./hlssplitter/source/hlssplitter/hlssplitter`
- Instances/links/allow rules are stored in SQLite:
  `splitter_instances`, `splitter_links`, `splitter_allow`.
- Config XML is generated automatically at `config_path` (default
  `./data/splitters/<id>.xml`); updates are pushed via file rewrite.
- Input URLs must be HTTP (`http://...`); HTTPS is rejected in the API/UI.
- Output URL pattern:
  `http://<server_ip>:<instance_port>/<resource_path>`, where `resource_path` is
  the input URL path.
- If no allow rules are present, Astra writes `allow 0.0.0.0` (allow all).
- Health checks probe local output URLs and mark each link `OK/DOWN` with
  `last_ok_ts` and `last_error`.
- UI presets fill common instance defaults (port/log/config). Note: `logtype` is
  numeric (0/1/2/4/3/5/6/7) per hlssplitter CLI.

## Buffer mode (HTTP TS buffer)
- Built-in HTTP server that buffers MPEG-TS per resource and serves raw TS.
- Input URLs must be HTTP; output URL pattern:
  `http://<server_ip>:<buffer_port>/<resource_path>`.
- Smart start uses PAT/PMT + keyframe checkpoints; per-resource failover supported.
- Global settings (Settings -> Buffer) configure the buffer server; resource settings
  are per channel (each resource keeps its own tuning).
- UI presets apply per resource and only fill tuning fields (backup/buffering/smart
  start/TS output). They do not change `id`, `name`, `path`, or `enable`.

### Buffer presets (examples)
Live + backup (passive failover):
```json
{
  "id": "buffer_live",
  "name": "Live + backup",
  "path": "/play/live",
  "enable": true,
  "backup_type": "passive",
  "no_data_timeout_sec": 3,
  "backup_start_delay_sec": 3,
  "backup_return_delay_sec": 10,
  "backup_probe_interval_sec": 30,
  "buffering_sec": 8,
  "bandwidth_kbps": 4000,
  "client_start_offset_sec": 1,
  "max_client_lag_ms": 3000,
  "smart_start_enabled": true,
  "smart_target_delay_ms": 1000,
  "smart_lookback_ms": 5000,
  "smart_wait_ready_ms": 1500,
  "smart_max_lead_ms": 2000,
  "smart_require_pat_pmt": true,
  "smart_require_keyframe": true,
  "smart_require_pcr": false,
  "keyframe_detect_mode": "auto",
  "av_pts_align_enabled": true,
  "av_pts_max_desync_ms": 500,
  "paramset_required": true,
  "start_debug_enabled": false,
  "ts_resync_enabled": true,
  "ts_drop_corrupt_enabled": true,
  "ts_rewrite_cc_enabled": false,
  "pacing_mode": "pcr"
}
```
Inputs:
```json
[
  { "id": "primary", "enable": true, "url": "http://source/primary.ts", "priority": 0 },
  { "id": "backup", "enable": true, "url": "http://source/backup.ts", "priority": 1 }
]
```

Multi-input (active warm inputs):
```json
{
  "id": "buffer_multi",
  "name": "Multi-input (active)",
  "path": "/play/multi",
  "enable": true,
  "backup_type": "active",
  "no_data_timeout_sec": 2,
  "backup_start_delay_sec": 0,
  "backup_return_delay_sec": 2,
  "backup_probe_interval_sec": 10,
  "buffering_sec": 6,
  "bandwidth_kbps": 4000,
  "client_start_offset_sec": 1,
  "max_client_lag_ms": 2000,
  "smart_start_enabled": true,
  "smart_target_delay_ms": 800,
  "smart_lookback_ms": 4000,
  "smart_wait_ready_ms": 1200,
  "smart_max_lead_ms": 1500,
  "smart_require_pat_pmt": true,
  "smart_require_keyframe": true,
  "smart_require_pcr": false,
  "keyframe_detect_mode": "auto",
  "av_pts_align_enabled": true,
  "av_pts_max_desync_ms": 400,
  "paramset_required": true,
  "start_debug_enabled": false,
  "ts_resync_enabled": true,
  "ts_drop_corrupt_enabled": true,
  "ts_rewrite_cc_enabled": false,
  "pacing_mode": "pcr"
}
```
Inputs:
```json
[
  { "id": "input0", "enable": true, "url": "http://source/input0.ts", "priority": 0 },
  { "id": "input1", "enable": true, "url": "http://source/input1.ts", "priority": 1 },
  { "id": "input2", "enable": true, "url": "http://source/input2.ts", "priority": 2 }
]
```

Low latency:
```json
{
  "id": "buffer_low",
  "name": "Low latency",
  "path": "/play/low",
  "enable": true,
  "backup_type": "passive",
  "no_data_timeout_sec": 2,
  "backup_start_delay_sec": 1,
  "backup_return_delay_sec": 3,
  "backup_probe_interval_sec": 10,
  "buffering_sec": 2,
  "bandwidth_kbps": 4000,
  "client_start_offset_sec": 0,
  "max_client_lag_ms": 800,
  "smart_start_enabled": true,
  "smart_target_delay_ms": 300,
  "smart_lookback_ms": 1500,
  "smart_wait_ready_ms": 500,
  "smart_max_lead_ms": 800,
  "smart_require_pat_pmt": true,
  "smart_require_keyframe": true,
  "smart_require_pcr": false,
  "keyframe_detect_mode": "idr_parse",
  "av_pts_align_enabled": true,
  "av_pts_max_desync_ms": 200,
  "paramset_required": true,
  "start_debug_enabled": false,
  "ts_resync_enabled": true,
  "ts_drop_corrupt_enabled": true,
  "ts_rewrite_cc_enabled": false,
  "pacing_mode": "none"
}
```

## UDP Output Audio Fix (AAC normalize)
- Per-UDP output toggle in the Output List: **Audio fix**.
- When enabled, Astra probes the UDP output with `scripts/analyze.lua` and checks
  the audio type in PMT.
- If audio type is not AAC (`0x0F`) for longer than the hold window, Astra starts
  a local ffmpeg pass: video copy, audio AAC, and publishes to the same UDP URL.
- Exclusive output: the normal UDP writer is disabled while the audio-fix ffmpeg
  is running (no double publish).
- Restarts on active input switches (failover/return/manual).
- Optional: set `force_on=true` (or `mode=auto`) to always run the ffmpeg pass and
  keep output audio parameters stable across primary/backup.
- Optional: `mode=auto` will copy audio (`-c:a copy`) only when the active input is
  already AAC and matches the target sample rate/channels; otherwise it transcodes
  to AAC.
- Optional: `silence_fallback=true` injects silence when input audio is missing.

Per-output config (UDP only):
```json
{
  "format": "udp",
  "addr": "239.0.0.10",
  "port": 1234,
  "audio_fix": {
    "enabled": true,
    "force_on": false,
    "mode": "aac",
    "probe_interval_sec": 30,
    "probe_duration_sec": 2,
    "mismatch_hold_sec": 10,
    "restart_cooldown_sec": 1200,
    "aac_bitrate_kbps": 128,
    "aac_sample_rate": 48000,
    "aac_channels": 2,
    "aac_profile": "",
    "aresample_async": 1,
    "silence_fallback": false
  }
}
```

## Backup/export
- API export (admin-only):
  - `GET /api/v1/export` (JSON payload matching import)
  - Optional query flags: `include_users=0`, `include_settings=0`,
    `include_streams=0`, `include_adapters=0`, `include_softcam=0`,
    `include_splitters=0`, `download=1`.
- NOTE: user exports include hashed passwords (or legacy cipher). Use
  `include_users=0` if you want to omit credentials.
- CLI export:
  - `./astra scripts/export.lua --data-dir ./data --output ./astra-export.json`
  - `./astra scripts/export.lua --data-dir ./data --no-users` (stdout)
  - `./astra scripts/export.lua --data-dir ./data --no-splitters` (stdout)
  - Other: `http_port`, `gid`, `softcam`, `backup_active_warm_max`, `event_request`.
- NOTE: `hls_base_url` is used as the URL prefix/route (default `/hls`); the CLI
  flag is `--hls-route`.
- NOTE: `hls_pass_data` defaults to true for compatibility; set it to false to
  drop MPEGTS_PACKET_DATA PIDs from HLS segments.
- NOTE: `http_play_no_tls` forces playlist/stream URLs to use `http://` even if
  a proxy sets `x-forwarded-proto=https`. The server itself does not implement TLS.
- NOTE: For HTTPS playlists behind a TLS-terminating proxy, pass
  `X-Forwarded-Proto: https` and (optionally) `X-Forwarded-Host` so generated
  URLs use the external scheme/host.
- NOTE: HTTP auth applies to HTTP Play playlists/streams, HLS routes, and HTTP
  output streams. Allow/deny lists match exact client IPs, tokens can be sent as
  `Authorization: Bearer <token>` or `?token=`, and Basic uses the users table.

## Config safety (LKG rollback)
- Config changes are validated and applied atomically. If reload fails, Astra
  restores the last known good (LKG) snapshot automatically.
- LKG snapshot path: `./data/backups/config/config_lkg.json`.
- Boot marker path: `./data/state/boot_state.json` (used to auto-rollback after a failed boot).
- Safe reload (UI uses this): `POST /api/v1/reload`.
- Validation: `POST /api/v1/config/validate` (returns `ok`, errors, warnings).
- Config history (admin):
  - `GET /api/v1/config/revisions`
  - `POST /api/v1/config/revisions/<id>/restore`

## Telegram alerts
- Settings (Settings → General → Telegram Alerts):
  - `telegram_enabled` (bool)
  - `telegram_level` (`OFF` | `CRITICAL` | `ERROR` | `WARNING` | `INFO` | `DEBUG`)
  - `telegram_bot_token` (secret)
  - `telegram_chat_id` (string, `-100…` or `@channel`)
- `GET /api/v1/settings` never returns the raw token. It exposes:
  - `telegram_bot_token_masked`
  - `telegram_bot_token_set`
- Test endpoint:
  - `POST /api/v1/notifications/telegram/test`
- Environment override (for testing):
  - `TELEGRAM_API_BASE_URL` (default `https://api.telegram.org`)

## Token authorization (Flussonic-like)
### Settings (global)
- `auth_on_play_url`, `auth_on_publish_url` (enable by setting on_play URL).
- `auth_timeout_ms` (default 3000), `auth_default_duration_sec` (default 180),
  `auth_deny_cache_sec` (default 180).
- `auth_hash_algo` (`sha1` or `md5`).
- `auth_hls_rewrite_token` (default true): append token to m3u8 URIs; playlist
  responses set cookies when a token is present.
- `auth_admin_bypass_enabled` (default true).
- `auth_allow_no_token` (default false).
- `auth_overlimit_policy`: `deny_new` (default) or `kick_oldest`.

### Per-stream overrides
- `on_play`, `on_publish` (override backend URLs).
- `session_keys` (comma-separated, order matters; required keys: `ip,name,proto`).
- `auth_enabled` (true/false to override global; omit to inherit).

### Backend protocol
- on_play: GET `<on_play_url>?name=&ip=&proto=&token=&session_id=&uri=&user_agent=&referer=`.
- on_publish: POST JSON `{name,ip,proto,token,session_id,uri,user_agent}`.
- Response headers: `X-AuthDuration`, `X-UserId`, `X-Max-Sessions`, `X-Unique`.

### Notes
- Token source: query `?token=`, fallback to `astra_token` cookie.
- Session id uses the ordered session_keys values; missing values become `undefined`.
- Backend errors: cached ALLOW gets short grace; new sessions fail closed.
- on_publish is best-effort for pull inputs: denial stops input after backend response.

## Project structure
- `main.c` + `modules/inscript/inscript.c`: entry and built-in apps.
- `scripts/`: Lua runtime (base/config/runtime/stream/api/server) and CLI apps.
- `modules/`: C modules (HTTP, HLS, DVB, UDP/RTP, file, SQLite, softcam, etc.).
- `web/`: UI assets (`index.html`, `app.js`, `styles.css`).
- `lua/`: vendored Lua 5.2.3.
- `contrib/`: helper build scripts.

## Examples
- `scripts/examples/http/` includes request, file server, and websocket examples.
- `fixtures/` provides sample JSON/Lua configs for inputs, outputs, failover,
  and transcode (most streams are disabled by default).

## Systemd (template)
- Templates live in `contrib/systemd/`:
  - `astra.service` (unit)
  - `astra.env` (environment file)
- Copy to:
  - `/etc/systemd/system/astra.service`
  - `/etc/default/astra`
- Update `WorkingDirectory`, `ExecStart`, and paths in `astra.env` for your install.
- Create the config at `ASTRA_CONFIG` (JSON or Lua). The unit uses
  `--config` to import before startup.
- Enable/start:
  - `systemctl daemon-reload`
  - `systemctl enable --now astra`

## Stream backup/failover
- Inputs are ordered; `input[0]` is primary, `input[1..]` are backups.
- `backup_type`: `active` | `active_stop_if_all_inactive` | `passive` | `disabled`.
  - Default: `active` when `input.length > 1`, otherwise `disabled`.
  - `active_stop_if_all_inactive`: stop stream if all inputs are down for
    `stop_if_all_inactive_sec`, then auto-resume when any input recovers.
- Delays (seconds):
  - `backup_initial_delay`/`backup_initial_delay_sec`: delay before switching away from primary on startup.
    Defaults: UDP/SRT=5, HTTP/HLS/RTSP=10, DVB=120, other=10.
  - `backup_start_delay`/`backup_start_delay_sec`: time primary must be down before switching (default `5`).
  - `backup_return_delay`/`backup_return_delay_sec`: wait before returning to primary after it stabilizes
    (active modes only, default `10`).
  - `stop_if_all_inactive_sec`: stop window for `active_stop_if_all_inactive` (default `20`, min `5`).
- Health/probing:
  - `no_data_timeout_sec` (default `3`),
  - `probe_interval_sec` (default `3`),
  - `stable_ok_sec` (default `5`).
- Active mode keeps warm standbys up to `backup_active_warm_max`
  (or global setting `backup_active_warm_max`, default `2`).
- Passive mode switches inputs without keeping warm probes; when the last input fails,
  it cycles back to the first.
- `GET /api/v1/stream-status` reports `active_input_index` and per-input state
  (`ACTIVE|STANDBY|DOWN|PROBING`), `backup_type`, `global_state`, bitrate, last_ok timestamp,
  last error, and fail count.
- If `settings.event_request` is set (HTTP URL), failover switches are POSTed as
  JSON events (`event=failover_switch`, stream id, from/to, reason, timestamp).
- Transcode streams use the same backup settings; when the active input changes,
  ffmpeg is restarted with the new input (monitoring uses the same analyzer-based checks).

## SRT/RTSP bridge (ffmpeg)
- SRT/RTSP inputs and SRT outputs are bridged via a local ffmpeg subprocess.
- Requires `ffmpeg` in `PATH` with `srt`/`rtsp` protocol support.
- Inputs: use `srt://` or `rtsp://` URLs with `bridge_port` (via `#bridge_port=...`
  or an object field).
- Outputs: use `format: "srt"` with `url` and `bridge_port`.
- Optional keys:
  - `bridge_bin` (default `ffmpeg`), `bridge_log_level` (default `warning`),
  - `bridge_input_args`, `bridge_output_args` (arrays of args),
  - `bridge_addr` (default `127.0.0.1`), `bridge_pkt_size` (default `1316`),
  - `bridge_socket_size`, `bridge_localaddr`,
  - `rtsp_transport` (for RTSP input, e.g. `tcp`).
- Example:
```json
{
  "make_stream": [
    {
      "id": "srt_in",
      "name": "SRT In",
      "enable": true,
      "input": [
        "srt://example.com:9000?mode=caller#bridge_port=14000"
      ],
      "output": [
        {
          "format": "srt",
          "url": "srt://127.0.0.1:15000?mode=caller",
          "bridge_port": 14010
        }
      ]
    }
  ]
}
```

## Transcode streams (FFmpeg)
- New stream type: `type="transcode"` (alias: `type="ffmpeg"`).
- Astra launches `ffmpeg` as a managed subprocess (no shell) with
  `-hide_banner -progress pipe:1 -nostats -loglevel warning`.
- Status/alerts:
  - `GET /api/v1/transcode-status` and `/api/v1/transcode-status/<id>`.
  - `GET /api/v1/alerts` (filters: `since`, `limit`, `stream_id`, `code`).
  - Alerts are also logged (`ERROR`) and sent via `settings.event_request`
    (`event=transcode_alert`) when configured.
  - Status includes `active_input_url` (selected by backup) and `ffmpeg_input_url`
    (actual ffmpeg `-i`).
  - ffmpeg is always started with a single input (the active one); backup switches
    restart ffmpeg with the new input.
- Config keys (per stream):
  - `transcode.engine`: `cpu` | `nvidia` | `vaapi` | `qsv` (defaults output codecs).
  - `transcode.process_per_output`: when `true`, run one ffmpeg process per output
    (fault isolation, independent restarts; status includes `workers[]`).
  - `transcode.seamless_udp_proxy`: when `true` and the output URL is UDP/RTP,
    route the worker output through a local UDP switch proxy so failover can do
    a warm cutover (old+new encoders in parallel; proxy flips sender when ready).
  - `transcode.seamless_cutover_timeout_sec`: cutover timeout (default 10).
  - `transcode.seamless_cutover_min_stable_sec`: extra stable window requirement
    for cutover readiness (defaults to the existing warmup stable window).
  - `transcode.ffmpeg_global_args`, `transcode.decoder_args`,
    `transcode.common_output_args` (alias: `common_input_args`).
  - `transcode.outputs[]`: `vf`, `vcodec`, `v_args`, `acodec`, `a_args`,
    `metadata`, `format_args`, `url`.
  - `transcode.log_file`: append ffmpeg stderr lines to a file.
  - `transcode.log_to_main`: `true` to mirror ffmpeg stderr to Astra log
    (use `"errors"` to log only matched error lines).
  - `transcode.input_probe_udp`: `true` to run a short UDP input probe before
    start (longer analyze window; requires `probe_interval_sec` > 0). UDP
    sockets cannot be shared with the ffmpeg receiver, so the input bitrate
    will not refresh while the transcode is running.
  - `transcode.input_probe_restart`: `true` to restart at each probe interval
    and refresh UDP input bitrate (disruptive; requires `input_probe_udp`).
  - `transcode.outputs[].watchdog` (per-output):
    `restart_delay_sec`, `no_progress_timeout_sec`, `max_error_lines_per_min`,
    `desync_threshold_ms`, `desync_fail_count`, `probe_interval_sec`,
    `probe_duration_sec`, `probe_timeout_sec`, `max_restarts_per_10min`,
    `probe_fail_count`, `monitor_engine` (`auto|ffprobe|astra_analyze`),
    `low_bitrate_enabled`, `low_bitrate_min_kbps`, `low_bitrate_hold_sec`,
    `restart_cooldown_sec`.
    Probe target is always the output `url` (user-provided `probe_url` is ignored).
  - Legacy: `transcode.watchdog` is still accepted as defaults for outputs when
    an output does not define its own watchdog.
  - Global: `monitor_analyze_max_concurrency` limits parallel Astra Analyze probes
    (default 4).
- UI tip: transcode output presets are available for common CPU/NVIDIA/Intel QSV 1080p/720p/540p
  profiles; transcode presets can also set engine/decoder/watchdog defaults and
  add a preset output if none exist. The output modal includes presets for
  HTTP/HLS/UDP/RTP/SRT/NetworkPush/file outputs.
- UI tip: input modal presets cover UDP/RTP/HTTP/HLS/SRT/RTSP/File templates and
  apply the corresponding URL/option defaults.
- UI tip: transcode output modal includes a repeat-headers toggle for libx264.
- NVIDIA engine validation checks for `/dev/nvidia0`, `/dev/nvidiactl`, or
  `/proc/driver/nvidia/version`; if none are found the job moves to `ERROR`
  and emits `TRANSCODE_GPU_UNAVAILABLE`.
- Intel QSV engine validation checks for `/dev/dri/renderD*` and FFmpeg encoder
  support (`ffmpeg -encoders | grep -E 'h264_qsv|hevc_qsv'`). If missing, the job
  moves to `ERROR` and emits `TRANSCODE_QSV_UNAVAILABLE`.
- Intel QSV typically requires the Intel iHD VAAPI driver (often packaged as
  `intel-media-va-driver`) and permissions to access `/dev/dri/renderD*`.
- Intel QSV settings (global, can be overridden per-stream via `transcode.qsv_*`):
  - `qsv_libva_driver_name` (default `iHD`)
  - `qsv_libva_drivers_path` (default `/opt/intel/mediasdk/lib64`)
  - `qsv_preset` (default `fast`)
  - `qsv_look_ahead_depth` (default `50`; set `0` to disable)
  - `qsv_h264_profile` (default `high`)
  - `qsv_hevc_profile` (default `main`)
- CPU example (minimum):
```json
{
  "make_stream": [
    {
      "id": "tc_cpu",
      "type": "transcode",
      "name": "CPU transcode",
      "enable": true,
      "input": ["udp://127.0.0.1:12100"],
      "transcode": {
        "engine": "cpu",
        "outputs": [
          {
            "name": "out",
            "vcodec": "libx264",
            "acodec": "aac",
            "format_args": ["-f", "mpegts"],
            "url": "udp://127.0.0.1:12110?pkt_size=1316"
          }
        ]
      }
    }
  ]
}
```
- NVIDIA example (excerpt):
```json
{
  "transcode": {
    "engine": "nvidia",
    "decoder_args": ["-hwaccel", "nvdec", "-c:v", "h264_cuvid"],
    "outputs": [
      {
        "vcodec": "h264_nvenc",
        "v_args": ["-preset", "slow", "-b:v", "2500k"],
        "acodec": "aac",
        "a_args": ["-ab", "128k", "-ac", "2", "-strict", "-2"],
        "format_args": ["-f", "mpegts"],
        "url": "udp://234.1.2.3:1234?pkt_size=1316"
      }
    ]
  }
}
```

- Intel QSV example (excerpt):
```json
{
  "transcode": {
    "engine": "qsv",
    "profiles": [
      {"id":"HD","width":1280,"height":720,"fps":25,"bitrate_kbps":2500,"maxrate_kbps":3200,"bufsize_kbps":5000}
    ]
  }
}
```

## Dev, test, lint, format
- Tests: only smoke tests in `AGENT.md` (required for changes).
- CI smoke runner: `contrib/ci/smoke.sh` (uses local build + minimal API checks).
- Lint/format: no configured tooling; keep edits scoped to touched lines.
- NOTE: performance-sensitive changes should be tested with real streams.

## Development rules
- Compatibility: keep API/CLI/config backward compatible by default.
- Versioning (SemVer): `version.h` is the source of truth. Use MAJOR for breaking
  changes, MINOR for new features, PATCH for fixes/internal updates.
- Deprecation: document + warn, keep deprecated paths for at least one MINOR release
  (or two PATCH releases if no MINOR is planned), include migration steps, remove
  only on a MAJOR bump.
- Migrations: update SQLite schema via `scripts/config.lua` migrations; avoid
  destructive changes unless `--import-mode replace` is used. Migrations run in
  transactions and create `astra.db.bak.<timestamp>` before applying new steps.
- Acceptance criteria: define expected behavior for each feature and extend smoke
  tests to cover new public endpoints/flows (see `AGENT.md`).

## Changes and TODOs
- Changelog: `CHANGELOG.md`.
- Roadmap: `PLAN.md`.
- TODOs: search via `rg "TODO"` (notable ones in HTTP/websocket, restart, stream
  module init/kill).
