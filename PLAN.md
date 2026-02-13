# Stream Hub - Feature Map and Development Plan

## Goal
Build a Linux-first (Ubuntu) streaming platform based on this codebase, with HLS and web interface as the highest priority.

## Source of truth
- Parity matrix: `docs/PARITY.md`
- Roadmap: `docs/ROADMAP.md`
- If there is a mismatch, update `docs/PARITY.md` first, then sync this plan in the same change.

## Feature Map (reference; target parity)
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

## Out of Scope (for this plan)
- DVB virtual adapters (SAT>IP/CI/MPTS-scan), FE device, bbframe, modulators (RESI/TBS/HiDes).
- MPTS constructor features, EPG/NIT/SDT tooling, remux_eit, SCTE-35 for HLS.
- Grafana/Zabbix exports.

## Development Plan (roadmap-aligned)
### 0-2 Weeks (Stabilization)
- [DONE] Docs + CI baseline.
- [DONE] Settings UI parity audit (Softcam/CAS/License reflect real behavior).
- [DONE] Backup default deviation documented.
- [DONE] Smoke coverage refresh (`contrib/ci/smoke.sh` updated).
- [DONE] PLAN sync with `docs/PARITY.md`/`docs/ROADMAP.md`.

Definition of Done:
- `docs/PARITY.md` and `PLAN.md` are synced (same change set).
- CAS/License sections are functional, no placeholders.
- CI smoke covers the public endpoints impacted by these changes.

Gates/Tests:
- CI: `contrib/ci/smoke.sh`.
- CI: `./astra scripts/tests/telegram_unit.lua`.
- Server smoke checklist in `AGENT.md` for any runtime/C changes.

### 1-2 Months (Productization)
- [DONE] Sessions/Logs UX polish (filters, pause/refresh, perf optimizations).
- [DONE] HLS failover resilience (no broken segments during input switch).
- [DONE] Config history UX (revision list + meaningful error text).
- [DONE] Monitoring exports (Influx/Webhook documented and wired).
- [TODO] HTTP Play TLS support.
- [TODO] MPTS runtime apply (UI/API done, runtime pending).

Definition of Done:
- Sessions/logs filters are responsive with large datasets.
- HLS failover smoke shows continuous playback.
- Config history displays errors and supports restore.
- TLS works without breaking `http_play_no_tls` behavior.
- MPTS runtime apply is wired and covered by parity/tests.

Gates/Tests:
- CI smoke + telegram unit.
- Server HLS + HTTP Play smoke (`AGENT.md`).
- Failover smoke (`fixtures/failover.json`).

### 3-6 Months (Differentiators)
- [TODO] Advanced analytics (alert enrichment, rate-limited notifications).
- [TODO] Extended output types (SRT/RTSP I/O, validation + UI).
- [TODO] Ops automation (installer + systemd defaults + packaging).

Definition of Done:
- Analytics events are stable and documented.
- SRT/RTSP I/O works end-to-end with UI/API/runtime parity.
- Installer/systemd defaults are validated on Ubuntu.

Gates/Tests:
- CI smoke + bundle smoke (`contrib/ci/smoke_bundle_transcode.sh`) when packaging changes.
- Optional SRT/RTSP smoke (if ffmpeg supports protocols).
