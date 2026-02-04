# Astra Clone - Feature Map and Development Plan

## Goal
Build a Linux-first (Ubuntu) streaming platform based on this codebase that matches Cesbo Astra features and web UI behavior, with HLS and web interface as the highest priority.

## Feature Map (from Cesbo docs)
### Adapter Configuration
- Adapter id for dvb:// references, adapter index, FE device.
- DVB standards: S, S2, T, T2, C, C/AC, C/B, C/A, C/C, ATSC, ASI.
- Modulation: NONE, AUTO, QPSK, QAM16/32/64/128/256, VSB8/16, PSK8, APSK16/32, DQPSK.
- Budget mode, CA PMT delay, DVR buffer size, raw signal, log signal.
- DVB-S/S2: tp (freq:pol:symbolrate), lnb (lof1:lof2:slof), lnb_sharing, diseqc, tone, rolloff, uni_scr, uni_frequency, stream_id.
- DVB-T/T2: frequency, bandwidth, guardinterval, transmitmode, hierarchy, stream_id.
- DVB-C: frequency, symbolrate.
- ATSC: frequency.

### Web UI
- Dashboard: live cards for streams/adapters with bitrate, status, quick actions.
- Sessions: list active HTTP/HLS clients (server, stream, IP, login, uptime, user-agent).
- Settings: grouped system settings (General, Users, HLS, HTTP Play, HTTP Auth, Softcam, CAS, Servers, Groups, Import, Edit Config, License, Restart).
- Logs: real-time log viewer.
- Search: quick search via keyboard shortcut.
- New Adapter / New Stream flows.

### Streams and Inputs
- Streams are logical channels with multiple inputs and outputs.
- SPTS is the default stream type with automatic failover between inputs.
- Inputs supported by address format: DVB, UDP, RTP, HTTP (MPEG-TS/HLS), SRT, RTSP, FILE.
- Stream processing options (input URL options):
  - pnr, set_pnr, set_tsid, map, filter / filter~.
  - biss, cam (CI/softcam), ecm_pid, shift, cas.
  - pass_sdt, pass_eit, no_reload.
  - no_analyze, cc_limit, bitrate_limit.
- Stream-level options: timeout, http_keep_active, map, set_pnr, set_tsid, service_provider, service_name.

### Outputs and Delivery
- Output types per spec: UDP, RTP, HTTP MPEG-TS, HLS, SRT, NetworkPush (HTTP push), MPEG-TS Files.
- Modulator outputs: RESI (DVB-C), TBS (DVB-C), HiDes (DVB-T).
- UDP/RTP address format: udp://[iface@]addr[:port][#options]. Options include socket_size, sync, cbr, ttl.
- HTTP/HLS output: HLS playlist and segments, optional HTTP MPEG-TS.
- NetworkPush: HTTP push to remote host.
- File output: write MPEG-TS to file or directory, aio option.

### HLS Segmenter (System Settings)
- Duration, Quantity, naming method (PCR-hash / Sequence).
- Resource path mode: Absolute / Relative / Full.
- Round duration, Expires header, Pass all data PIDs.
- Default headers for .m3u8 and .ts, TS extension, TS MIME type.

### HTTP Play and Playlists
- Enable HTTP MPEG-TS and/or HLS access for all streams.
- Custom HTTP Play port, optional TLS disable.
- Playlist name, playlist grouping by category, logos path.
- M3U/XSPF playlist generation; M3U header for EPG URL.

### Auth and Access Control
- HTTP auth methods: user list, backend validation, securetoken, IP allow/deny.

### Sessions, Logs, Monitoring
- Sessions list for HTTP/HLS clients.
- Real-time logs and access logs.
- Monitoring export and integrations (InfluxDB, Grafana, Zabbix).

### Ops and Tools
- Systemd service management, license handling, backup/import/export.
- CLI tools (astra-cli, dvbls, mpeg-ts analyzer, etc.).

## Out of Scope for This Plan (per request)
- DVB virtual adapters (SAT>IP/CI/MPTS-scan), FE device, bbframe, modulators.
- MPTS constructor features, EPG/NIT/SDT tooling, remux_eit, SCTE-35 for HLS.

## Development Plan (detailed, HLS + UI first)
### Phase 0 - Parity audit + docs (in progress)
- Maintain `docs/astral-parity.md` (Docs → Astral matrix).
- Keep `SKILL.md`/`PLAN.md` in sync with implemented features.

### Phase 1 - Baseline Service + Config API (done)
- SQLite-backed config, users, sessions, settings.
- REST API for streams/adapters/settings/auth.
- Runtime apply/refresh of streams.

### Phase 2 - Web UI Skeleton (done)
- Astra-like layout (Dashboard, Sessions, Settings, Log, Help).
- Stream editor modal with tabs, inputs/outputs list.
- Output modal and UI styling to match Cesbo.
- Groups settings + stream group assignment: done.
- Servers settings + test endpoint: done.

### Phase 3 - Live Metrics + Analyze (done, pending server verification)
- Persist analyze stats per input (bitrate, CC/PES errors, on_air).
- API: stream-status list/single.
- UI: polling, tile updates, analyze modal with real stats.

### Phase 4 - Output Config Parity (in progress)
- Output modal advanced fields (HLS naming/round/ts, SCTP toggles, NP buffer fill, SRT bridge advanced, BISS key): done.
- Align output parameters with Cesbo spec for UDP/RTP (socket_size, sync, cbr, ttl, iface).
- HLS output options: base_url, playlist, prefix, window, cleanup, wall clock.
- HTTP MPEG-TS output options: host/port/path, buffer, keep_active.
- NetworkPush + File outputs parity.

### Phase 5 - HLS System Settings + HTTP Play (done)
- Settings pages wired to runtime config.
- HLS segmenter system settings: duration, quantity, naming, resource path, headers.
- HTTP Play: global HLS/HTTP enable, playlist settings, logos, M3U header.
- TODO: implement TLS support for HTTP Play; `http_play_no_tls` currently forces
  playlist/stream URLs to use `http://`.

### Phase 5.1 - General Settings Enhancements (done)
- Stream defaults in General (timeouts/backup/keep-active).

### Phase 6 - Sessions + Logs (next)
- Real HTTP/HLS session tracking and UI table.
- Live log stream + filters.

### Phase 7 - Auth + Users (next)
- User management UI.
- HTTP Auth methods and allow/deny lists.

### Phase 8 - Monitoring + Integrations (later)
- Metrics export endpoints and simple dashboards.
- InfluxDB/Grafana/Zabbix hooks.
- Telegram alerts (UI + notifier + test endpoint): done.

### Phase 9 - Packaging + Ops (later)
- Ubuntu systemd service, configs, install scripts.
- Backup/import/export.

### Phase 10 - Deferred Features (later)
- SRT/RTSP inputs + SRT output (new module required).
- RESI modulator output (hardware integration).

### Phase 11 - Buffer Mode (HTTP TS Buffer) (in progress)
- Settings + SQLite schema for buffer resources/inputs/allow rules.
- C http_buffer module (ring buffer, smart start, failover, HTTP output).
- Buffer API endpoints + status + reload/restart-reader.
- Buffer UI (resources, inputs, allow rules, diagnostics).
- Smoke tests + documentation updates.
