# Astra-Compatible DVB EPG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore Astra-compatible `epg_export` behavior in Stream Lite so existing adapter JSON files continuously produce populated XMLTV schedules without changing their stream definitions.

**Architecture:** Add a read-only MPEG-TS tap module that subscribes only to PID `0x12`, reassembles and CRC-validates actual EIT sections, and sends complete sections to Lua. Lua owns legacy configuration normalization, EIT event state, DVB text parsing, safe retention, status, and atomic XMLTV export. The tap is a sibling consumer of the active input and never enters the media output path.

**Tech Stack:** C11, Astra module stream/PSI APIs, Lua 5.3, SQLite config store, XMLTV, shell build/tests, runit production services.

---

### Task 1: Make the disk I/O schema migration idempotent

**Files:**
- Modify: `scripts/config.lua`
- Create: `scripts/tests/config_disk_io_migration_unit.lua`

- [x] Add a regression test that starts schema version 16 both with and without `system_metrics_rollup.disk_io_json`.
- [x] Run `./stream scripts/tests/config_disk_io_migration_unit.lua` and confirm the existing-column case fails at migration 17.
- [x] Add a column-presence guard for migration 17 while preserving the add-column operation for older databases.
- [x] Run the new test plus `config_primary_fingerprint_unit.lua`, `config_export_reuse_unit.lua`, and `json_decode_unicode_unit.lua`.
- [x] Commit as `fix: make disk io schema migration idempotent`.

### Task 2: Define and test legacy EPG configuration compatibility

**Files:**
- Modify: `scripts/epg.lua`
- Modify: `web/app.js`
- Create: `scripts/tests/epg_legacy_config_unit.lua`

- [ ] Write tests for `file:///opt/epg/name.xml`, absolute paths, modern `config.epg` precedence, default XMLTV ID from stream ID, and disabled/invalid values.
- [ ] Run `./stream scripts/tests/epg_legacy_config_unit.lua` and confirm legacy resolution fails.
- [ ] Implement `epg.resolve_stream_config(row)` without mutating persisted stream configuration.
- [ ] Make the editor display resolved legacy values while still saving an explicit modern `epg` object only when the user edits the tab.
- [ ] Re-run the test and commit as `feat: recognize Astra epg_export configuration`.

### Task 3: Add a native, non-invasive EIT section tap

**Files:**
- Create: `modules/mpegts/eit_collect.c`
- Modify: `modules/mpegts/module.mk`
- Create: `scripts/tests/eit_collect_fixture.lua`

- [ ] Add a test fixture that packetizes one CRC-valid EIT actual section into PID `0x12` TS packets, including section repetition and a non-actual table.
- [ ] Add `eit_collect` with `upstream`, `service_id`, and `callback` options; join only PID `0x12` and never forward or modify packets.
- [ ] Reassemble with `mpegts_psi_mux`, accept table IDs `0x4E` and `0x50..0x5F`, validate CRC and optional service ID, and deduplicate by table/section CRC.
- [ ] Emit the complete section as a Lua binary string and safely disable a callback after a Lua error.
- [ ] Build with `make -j4`; run the fixture and confirm exactly one callback for a repeated section.
- [ ] Commit as `feat: add DVB EIT collection tap`.

### Task 4: Parse EIT and maintain a bounded event registry

**Files:**
- Modify: `modules/astra/iso8859.c`
- Modify: `scripts/epg.lua`
- Create: `scripts/tests/epg_eit_parser_unit.lua`

- [ ] Write a raw-section unit test covering MJD/BCD start time, duration, running status, short-event `0x4D`, ordered extended-event `0x4E`, content `0x54`, UTF-8 and ISO-8859 text.
- [ ] Expose the existing safe DVB decoder as `iso8859.decode(binary)`.
- [ ] Implement strict bounds-checked EIT parsing and reject malformed sections without modifying registry state.
- [ ] Store events under stream/service/event identity, deduplicate updates, purge events older than 24 hours and cap horizon/entry count.
- [ ] Re-run parser tests and commit as `feat: parse and retain DVB EIT events`.

### Task 5: Attach collectors and export populated XMLTV atomically

**Files:**
- Modify: `scripts/stream.lua`
- Modify: `scripts/epg.lua`
- Create: `scripts/tests/epg_xmltv_export_unit.lua`
- Create: `scripts/tests/epg_runtime_attach_unit.lua`

- [ ] Test that an enabled legacy stream creates a collector on the active-input analyze tail, collectors survive HTTP idle state, and teardown releases the tap.
- [ ] Test XMLTV channel/programme output, XML escaping, chronological ordering, multiple destinations, and preservation of the last valid file when there are zero current events.
- [ ] Attach `eit_collect` as a sibling tap in `channel_prepare_input`; point it at the currently active stream input and register sections through `epg.ingest_section`.
- [ ] Keep EPG-enabled streams active even without HTTP viewers and release collectors during input/channel teardown.
- [ ] Replace direct writes with same-directory temporary file plus rename; write only when at least one valid programme exists.
- [ ] Trigger a debounced export after new/changed EIT and use a safe default interval when legacy exports exist but the global setting is absent.
- [ ] Re-run tests and commit as `feat: export live DVB schedules as XMLTV`.

### Task 6: Add status and UI visibility

**Files:**
- Modify: `scripts/epg.lua`
- Modify: `scripts/api.lua`
- Modify: `web/app.js`
- Create: `scripts/tests/epg_status_api_unit.lua`

- [ ] Test status fields: configured destination, collector state, last EIT timestamp, event count, last successful write, and last error.
- [ ] Add an authenticated `/api/epg/status` response and render legacy-resolved configuration/status in the EPG tab.
- [ ] Re-run API/UI static tests and commit as `feat: expose DVB EPG collection status`.

### Task 7: Build and verify Stream Lite locally

**Files:**
- Verify only.

- [ ] Run `./configure.sh --without-transcode --bin=./stream && make -j4`.
- [ ] Run all new EPG tests, migration tests, config tests, and existing stream/runtime API tests affected by lifecycle changes.
- [ ] Run `bash scripts/ci/check_sensitive_data.sh` and inspect `git diff --check` and `git status --short`.
- [ ] Produce the Linux amd64 Lite binary using the repository-supported build path and record its SHA-256.

### Task 8: Back up and canary on adapter5

**Remote targets:**
- Backup: `/root/back/stream-epg-astra-compat-20260823/`
- Canary binary: `/usr/local/bin/stream-epg-canary`
- Canary service: `/etc/sv/adapter5/run`

- [ ] Record current binary hash, service commands, config hashes, process list, port listeners, EPG file counts/horizons, and representative playback probes.
- [ ] Copy the binary, all adapter JSON files, and run scripts into the exact backup directory.
- [ ] Install the verified candidate as `/usr/local/bin/stream-epg-canary` and change only adapter5's run script.
- [ ] Restart only adapter5 and verify port `8805`, admin/API health, continuous stream bitrate, no new CC/PES errors, and fresh populated `/opt/epg/*.xml` for adapter5.
- [ ] Observe at least two EIT refresh/export cycles and compare programme counts/horizons with the pre-migration Astra files.
- [ ] On failure, restore adapter5's run script and restart it before further work.

### Task 9: Controlled production rollout

**Remote targets:**
- Binary: `/usr/local/bin/stream`
- Services: `adapter0,1,2,3,4,5,6,8,9,10,11,13,14,15,17`
- Excluded: `aggregation`

- [ ] Promote the canary binary only after adapter5 passes.
- [ ] Rolling-restart one adapter at a time with a five-second service timeout and verify listener/API/playback after each restart.
- [ ] Verify all 54 configured EPG destinations are being refreshed and contain programmes, with no truncation to channel-only XML.
- [ ] Run external `ffprobe` samples for representative channels and compare process stability, bitrate, CC/PES counters, EPG freshness, and logs.
- [ ] Leave `aggregation` unchanged and report exact hashes, service states, programme counts, remaining exceptions, and rollback path.
