# Changelog

## Policy
- Every change must add an entry here.
- Format:
  - YYYY-MM-DD - Short summary
  - Changes:
    - Itemized list of changes
  - Tests:
    - Itemized list of tests (or "Not run")

## Entries
### 2026-02-07
- Changes:
  - Install: extend install.sh to support CentOS/RHEL family (dnf/yum), source/binary download from a.centv.ru, and systemd template install.
  - Softcam: add dual-CAM hedge delay (backup ECM after threshold), input-level cam_backup selection, and richer CAM stats (backup usage + RTT histogram).
  - Softcam: fix hedged dual-CAM stats fields and implement backup send timer to match UI stats (build/runtime).
  - HTTP input: apply /play-style sync/timeout defaults for /stream URLs (burst delivery).
  - Softcam: drop duplicate module_data_t typedef in decrypt.c (silence -Wpedantic warning).
  - Analyze: show dual-CAM hedge, backup activity share, and ECM RTT distribution with primary/backup counts.
  - AI Chat: add chip/command `update channel names` (no OpenAI call) with CLI instructions to refresh stream names from SDT via `astral --analyze`.
  - Tools: add `tools/update_stream_names_from_sdt.py` (dry-run by default, low parallelism + rate limiting) to update `stream.name` from SDT service name through API.
  - UI: fix AI chat Diff/Apply preview gating: when diff sections are empty, do not show Diff preview or Apply plan (prevents confusing `+0 ~0 -0` blocks).
  - Softcam: add `POST /api/v1/softcam/test` and a Softcam modal "Test" button (separate from Save; saving does not depend on reachability).
  - API: remove a duplicate `/api/v1/softcam/test` route block (no behavior change).
  - UI: show a clearer allowlist/origin hint for Softcam save/test network errors.
  - UI: bump asset version stamp to `20260207a` to ensure browsers pick up the latest Softcam UI updates.
  - Runtime: skip invalid Softcam entries during apply to avoid aborting the server on incomplete configs.
- Tests:
  - `python3 -m py_compile tools/update_stream_names_from_sdt.py`
  - `python3 tools/update_stream_names_from_sdt.py --help`
  - Not run (softcam changes).
### 2026-02-06
- Changes:
  - AI Chat: make prompt chips clickable (ChatGPT-style) and hide Diff/Apply when the plan has no config changes.
  - AI Chat: add local commands `error ch` (list problematic channels) and `transcode all stream` (create disabled transcode ladder streams without calling OpenAI).
  - API: add admin endpoint `POST /api/v1/streams/transcode-all` to generate default transcode ladder (HLS publish) streams for all enabled non-transcode channels (disabled by default for safety).
  - Stream validation: allow `stream://<id>` inputs for transcode streams and accept ladder configs (profiles+publish) without requiring `transcode.outputs`.
  - Transcode: defer starting ffmpeg jobs until the HTTP server is listening (prevents early /play connect failures during boot).
  - CI: add ladder smoke fixtures/scripts for failover HLS publish and HTTP TS pull.
- Tests:
  - Local smoke: start server, login, import one stream, run `POST /api/v1/streams/transcode-all`.
  - `bash -n contrib/ci/smoke_transcode_ladder_failover_hls_publish.sh`
  - `bash -n contrib/ci/smoke_transcode_ladder_http_ts_pull.sh`
  - `python3 -m json.tool fixtures/transcode_ladder_failover_hls_publish.json`
  - `python3 -m json.tool fixtures/transcode_ladder_http_ts_pull.json`
### 2026-02-06
- Changes:
  - Auth: cache `auth_session_ttl_sec` lookup to avoid extra settings DB query on each authenticated request.
- Tests:
  - Not run locally.
### 2026-02-06
- Changes:
  - Auth: keep web sessions alive for active users (sliding TTL) and set persistent session cookie (`Max-Age`, `SameSite=Lax`) on login.
- Tests:
  - Not run locally.
### 2026-02-06
- Changes:
  - Settings/Logs: add runtime logging controls (stdout/file/syslog, log level, file rotation) and apply them live via `PUT /api/v1/settings`.
- Tests:
  - `./configure.sh && make`
### 2026-02-06
- Changes:
  - UI: speed up initial load and dashboard updates for large configs (refresh only the active view first, background-load the rest; reduce per-poll DOM work by caching tile refs and updating details only when expanded).
- Tests:
  - Not run locally.
### 2026-02-06
- Changes:
  - Transcode API: expose `publish_hls_variants` in transcode status (list of published HLS variant PIDs, if present).
- Tests:
  - Not run locally (covered by CI).
### 2026-02-06
- Changes:
  - UI: add `ui_polling_interval_sec` (Settings -> General: "Polling") to control Dashboard status/bitrate refresh; on page load it polls every ~2s for ~30s then ramps to the selected interval.
  - UI: fix view naming defaults so polling follows the active tabs (`dashboard`, `logs`) without requiring a manual re-open.
  - Transcode: improve late-joiner compatibility (repeat SPS/PPS on keyframes, resend TS headers, and set MP4 codec tags for DASH stream-copy).
  - CI: add DASH ladder publish smoke (`contrib/ci/smoke_transcode_ladder_dash_publish.sh`).
- Tests:
  - Not run locally (covered by CI).
### 2026-02-06
- Changes:
  - AI Chat: add `delete all disable channel` command chip to purge all disabled streams (no OpenAI call).
  - AI Chat: command runs via API (no plan/apply) and refreshes the streams list after completion.
  - API: add admin endpoint `POST /api/v1/streams/purge-disabled` (snapshot-safe config change).
- Tests:
  - `./configure.sh && make`
### 2026-02-06
- Changes:
  - UI Player: "Open in new tab" now opens a self-contained UI URL (`/index.html#player=<id>&kind=...`) so playback works in a new tab (instead of opening raw `/play`/`/hls`).
  - Preview: return `409 stream offline` when the input is already running and has failures, to avoid infinite buffering in the player.
  - CI: add `preview_offline_unit` and run it in `contrib/ci/smoke_preview.sh`.
- Tests:
  - `contrib/ci/smoke_preview.sh`
### 2026-02-06
- Changes:
  - UI Player: always show both links `Play` (`/play/<id>`) and `HLS` (`/hls/<id>/index.m3u8`), and display the selected URL in the header (instead of the UDP active input).
  - UI Player: improve HLS robustness (retries for on-demand 503, better error messages, and fallbacks: `audio_aac` then video-only on decode/not-supported errors).
  - Preview: when `http_play_hls=true`, `preview/start` returns direct `/hls/<id>/index.m3u8` without starting a preview session.
  - Preview: add `audio_aac` preview profile (ffmpeg: `-c:v copy`, `-c:a aac`) and use `/play/<id>?internal=1` for localhost ffmpeg to bypass `http_auth`.
  - API: support `audio_aac=1` for `POST /api/v1/streams/:id/preview/start`.
- Tests:
  - `contrib/ci/smoke_preview.sh`
  - `./astral scripts/tests/preview_audio_aac_unit.lua`
### 2026-02-06
- Changes:
  - JSON: support `\\uXXXX` (incl. surrogate pairs) and `\\b`/`\\f` escapes, plus exponent numbers (improves OpenAI Responses parsing reliability).
- Tests:
  - `./astral scripts/tests/json_decode_unicode_unit.lua`
### 2026-02-06
- Changes:
  - AI: when the outer OpenAI Responses JSON is invalid, extract `output_text` directly from the raw body to keep chat working behind flaky proxies.
- Tests:
  - `./astral scripts/tests/ai_openai_raw_output_extract_unit.lua`
### 2026-02-06
- Changes:
  - AI: harden OpenAI proxy response decoding (scrub/salvage JSON) and fall back to the next model when a proxy returns invalid JSON.
- Tests:
  - `./astral scripts/tests/ai_openai_invalid_json_fallback_unit.lua`
### 2026-02-06
- Changes:
  - AI: when using proxy (curl), read OpenAI Responses body from a temp file (`curl -o`) to avoid stdout truncation causing "invalid json" in chat.
- Tests:
  - `./astral scripts/tests/ai_openai_proxy_bodyfile_unit.lua`
### 2026-02-06
- Changes:
  - AI: make OpenAI response parsing more tolerant (accept text chunk variants and fall back to the next model when 200 OK has no output_text).
- Tests:
  - `./astral scripts/tests/ai_openai_output_missing_fallback_unit.lua`
### 2026-02-06
- Changes:
  - AI: switch default OpenAI model to `gpt-5-nano` (lower cost) with auto fallback to `gpt-5-mini`, `gpt-4.1` when unavailable/unsupported.
  - AI: normalize common versioned aliases (`gpt-5.2-mini`, `gpt-5.2-nano`, etc) to family names to avoid 400 `model_not_found`.
  - UI/Docs: update AstralAI model hints to reflect the new default.
- Tests:
  - `./astral scripts/tests/ai_openai_model_alias_unit.lua`
### 2026-02-06
- Changes:
  - AI: switch default OpenAI model to `gpt-5-mini` (lower cost) and keep auto fallback to `gpt-5.2`, `gpt-4.1` when a model is unavailable/unsupported.
  - AI: omit `temperature` for older GPT-5 models (`gpt-5`, `gpt-5-mini`, `gpt-5-nano`) to avoid OpenAI parameter-compatibility 400s.
  - UI/Docs: update AstralAI model hints to reflect the new default.
- Tests:
  - `./astral scripts/tests/ai_openai_fallback_unit.lua`
  - `./astral scripts/tests/ai_openai_strict_schema_unit.lua`
### 2026-02-06
- Changes:
  - AI: harden OpenAI 429 handling (use retry hints in error messages, safer backoff when headers are stripped, and avoid retry loops on quota errors).
  - AI: add `ai_max_attempts` (default 6) so chat jobs can survive transient rate limits without user re-submits.
  - UI: extend AstralAI chat polling timeout to 10 minutes to allow longer backoffs.
- Tests:
  - `./astral scripts/tests/ai_openai_retry_delay_unit.lua`
### 2026-02-06
- Changes:
  - HLS memfd: fix invalid `#EXTINF` duration formatting in playlists (was emitting `.3f` due to limited formatter).
  - Tools: HLS memfd smoke now validates EXTINF duration format (regression guard).
- Tests:
  - Not run locally (covered in CI: `tools/hls_memfd_smoke.sh`).
### 2026-02-06
- Changes:
  - MPTS: UI: make MPTS tab actionable when disabled (callout + click-to-manual) and add tools to build service list faster (Convert inputs / Add from streams).
  - MPTS: DVB hardening: CAT multi-section (large CA lists no longer truncate).
  - MPTS: TOT: add `advanced.disable_tot` (TDT only), `general.dst.*` (time_of_change/next_offset) and treat `general.utc_offset` as minutes with hours compatibility.
  - MPTS: EIT pass-through: add `advanced.eit_table_ids` filter (table_id allowlist/ranges).
  - MPTS: SDT/NIT: add DVB charset marker prefixes for `general.codepage` (limited ISO-8859 set + UTF-8).
  - Tools/CI: extend `tools/gen_spts.py` to emit multiple EIT table_ids; add `EXPECT_NO_TOT` to verifier; add new MPTS smokes.
- Tests:
  - `./configure.sh && make`
  - `contrib/ci/smoke_mpts_tot_disable.sh`
  - `contrib/ci/smoke_mpts_eit_mask.sh`
  - `contrib/ci/smoke_mpts_cat_multisection.sh`
### 2026-02-06
- Changes:
  - UI: warn when HTTP Play HLS is enabled but HLS storage is set to disk (common source of high disk I/O); add one-click preset to switch to memfd + on-demand defaults.
  - Streams: log a one-time warning when `http_play_hls=true` uses disk storage (suggest `hls_storage=memfd`) to reduce disk I/O surprises.
- Tests:
  - Not run (UI/Lua change only).
### 2026-02-06
- Changes:
  - Transcode: seamless UDP proxy cutover can complete even when only standby sender exists (prevents cutover timeouts when primary dies early).
- Tests:
  - `contrib/ci/smoke_transcode_seamless_failover.sh` (Ubuntu servers).
### 2026-02-06
- Changes:
  - Repo: ignore macOS `.DS_Store` and remove accidentally tracked file.
- Tests:
  - Not run.
### 2026-02-06
- Changes:
  - MPTS: add optional CAT generation with CA_descriptors from `mpts_config.ca` (CA system id, CA PID, private data).
  - MPTS: include CA_PID from PMT CA_descriptor in auto-remap and rewrite CA_PID inside output PMT (keeps ECM PID consistent after remap).
  - UI: add MPTS CAT/CA section to edit `mpts_config.ca` and clarify pass-through behavior in the manual.
  - CI: add `contrib/ci/smoke_mpts_cat.sh` coverage and extend verifier to assert CAT/PMT CAS lines.
  - Tools: `tools/gen_spts.py` can emit PMT CA_descriptor for CI fixtures.
- Tests:
  - `./configure.sh && make`
  - `contrib/ci/smoke_mpts.sh`
  - `contrib/ci/smoke_mpts_cat.sh`
### 2026-02-06
- Changes:
  - API: allow enabled-only adapter updates (avoid wiping adapter config when toggling enabled).
  - API: adapters: treat missing `enabled` on updates as "keep current" (prevents accidental re-enable on partial updates).
  - UI: rename Stream/Adapter "Apply" buttons to "Save" to clarify persistence.
- Tests:
  - Local integration: enabled-only adapter PUT preserves adapter config fields (export unchanged).
### 2026-02-06
- Changes:
  - Docs: update `docs/API.md` with health auth rules, `POST /mpts/scan`, and enabled-only patch notes for streams/adapters.
- Tests:
  - Not run (docs change only).
### 2026-02-06
- Changes:
  - UI: add Save buttons for HLS/HTTP Play/HTTP Auth settings (persist without restart) and autosave HTTP Play access toggles.
- Tests:
  - Not run (UI change only).
### 2026-02-06
- Changes:
  - API/UI: allow enabled-only stream updates (avoid wiping stream config when toggling Disable/Enable).
- Tests:
  - Not run.
### 2026-02-06
- Changes:
  - UI: add compact mode toggle for Settings -> General cards.
- Tests:
  - Not run (UI change only).
### 2026-02-06
- Changes:
  - AI: honor `retry-after` / `x-ratelimit-reset-*` headers when scheduling retries (reduces retry load on 429).
- Tests:
  - `./astra scripts/tests/ai_openai_retry_delay_unit.lua`
### 2026-02-06
- Changes:
  - CI: run HLS memfd smoke (`tools/hls_memfd_smoke.sh`) to guard zero-disk/on-demand behavior.
- Tests:
  - Not run (CI change only).
### 2026-02-06
- Changes:
  - UI: expose HLS memfd storage/on-demand limits in Settings -> HLS.
  - HLS: run memfd idle sweep timer whenever memfd handler is enabled (supports per-stream memfd overrides).
- Tests:
  - `tools/hls_memfd_smoke.sh`
### 2026-02-06
- Changes:
  - MixAudio: modernize FFmpeg API usage to compile against current libavcodec/libavutil.
  - MixAudio: fix module detection to always add system FFmpeg link flags (pkg-config libs).
  - CI: install libavcodec-dev/libavutil-dev/libpq-dev so optional modules (mixaudio/postgres) build in CI.
- Tests:
  - `docker run --platform linux/arm64 ubuntu:24.04 ./configure.sh && make`
### 2026-02-06
- Changes:
  - Tools: HLS memfd smoke now validates playlist no-cache/no-store headers (regression guard).
  - HLS: use strict no-cache/no-store headers for playlists (m3u8), including memfd 503 responses.
  - UI: reduce AstralAI chat polling load and show clearer retry/error status details.
- Tests:
  - `tools/hls_memfd_smoke.sh`
  - Not run (UI change only).
### 2026-02-06
- Changes:
  - AI: fix OpenAI retry backoff timer scoping (prevents panic on retries).
- Tests:
  - `./astra scripts/tests/ai_openai_retry_scope_unit.lua`
### 2026-02-06
- Changes:
  - MPTS: NIT delivery descriptor support for DVB-T (0x5A) and DVB-S/S2 (0x43).
  - Analyzer: decode DVB-T/S delivery descriptors in NIT (for logs/CI checks).
  - CI: add smoke coverage for DVB-T and DVB-S NIT delivery.
  - Docs: update MPTS design/summary for delivery support.
- Tests:
  - `contrib/ci/smoke_mpts_dvbt.sh`
  - `contrib/ci/smoke_mpts_dvbs.sh`
### 2026-02-06
- Changes:
  - AI: add `Content-Length` header for OpenAI requests (fixes OpenAI 400 "Missing required parameter: model" when body is ignored).
- Tests:
  - `./astra scripts/tests/ai_openai_host_header_unit.lua`
### 2026-02-06
- Changes:
  - AI: add `Host` and `User-Agent` headers for OpenAI requests (fixes Cloudflare 400 when Host is missing).
- Tests:
  - `./astra scripts/tests/ai_openai_host_header_unit.lua`
### 2026-02-06
- Changes:
  - Transcode: add per-output workers (one ffmpeg per output) for fault isolation.
  - Transcode: add seamless UDP/RTP cutover via local UDP proxy (`udp_switch`) to allow warm-switch without full output downtime.
  - UI: add per-output + seamless proxy toggles and surface worker/proxy state in Editor and Analyze.
  - CI: add seamless failover fixture + smoke script.
- Tests:
  - `./configure.sh && make`
  - `contrib/ci/smoke.sh`
  - `contrib/ci/smoke_transcode_seamless_failover.sh` (intended for Ubuntu/Debian; multicast input)
### 2026-02-06
- Changes:
  - AI/Observability: fix sqlite abort by storing md5 fingerprint as hex (no NUL bytes) and making AI log/metric inserts non-fatal.
- Tests:
  - Not run (covered by CI).
### 2026-02-05
- Changes:
  - AI: scrub ASCII control bytes and sanitize UTF-8 in OpenAI request bodies (prevents OpenAI "Invalid body: failed to parse JSON value" 400s).
- Tests:
  - `./astra scripts/tests/ai_openai_body_scrub_unit.lua`
### 2026-02-05
- Changes:
  - HLS: memfd mode avoids touching disk HLS dir unless disk HLS is explicitly used; playlist rewrite path avoids disk fallback when memfd playlist isn't ready.
  - HLS: gate `debug_hold_sec` behind `-DHLS_MEMFD_DEBUG`.
  - Tools: add/update `tools/hls_memfd_smoke.sh` for repeatable HLS memfd on-demand/no-disk sanity.
  - Preview: add on-demand HLS preview manager (memfd) + smoke coverage.
  - HTTP: fix `/play` streaming via `http_upstream` send/auth path.
  - AI: sanitize NaN/Inf in context/payload JSON to avoid OpenAI "Invalid body: failed to parse JSON" errors.
- Tests:
  - `tools/hls_memfd_smoke.sh`
  - `./configure.sh && make`
  - `./astra scripts/tests/ai_prompt_sanitize_nan_unit.lua`
### 2026-02-05
- Changes:
  - AI: fix strict JSON schema (Structured Outputs) by requiring all object keys (prevents OpenAI schema validation errors).
- Tests:
  - `./astra scripts/tests/ai_openai_strict_schema_unit.lua`
### 2026-02-05
- Changes:
  - AI: fix OpenAI Responses json_schema request format (text.format.name/schema/strict) to avoid 400 errors.
- Tests:
  - `./astra scripts/tests/ai_openai_fallback_unit.lua`
### 2026-02-05
- Changes:
  - AI: add fallback for unsupported response_format/json_schema and expose error detail + model metadata.
  - UI: show AI error details in chat.
  - Release: pin bundled FFmpeg source to a specific autobuild tag (stable SHA256).
- Tests:
  - `./astra scripts/tests/ai_openai_fallback_unit.lua`
  - `./astra scripts/tests/ai_telegram_commands_unit.lua`
  - `./astra scripts/tests/ai_logs_autoselect_unit.lua`
### 2026-02-05
- Changes:
  - UI: warmup alerts now show actionable hints.
- Tests:
  - Not run (UI change only).
### 2026-02-05
- Changes:
  - AI: force on-demand metrics (no rollup), hide UI AI summary and compute observability summary from metrics.
  - AI: Telegram command parsing now supports keys with `_` / `-` (e.g. plan_id).
  - Docs: clarify minimal-load AI defaults and auto context selection.
- Tests:
  - `./astra scripts/tests/ai_telegram_commands_unit.lua`
### 2026-02-05
- Changes:
  - Transcode: add warmup failure/timeout/stop alerts for failover diagnostics.
- Tests:
  - Not run (logic change only).
### 2026-02-05
- Changes:
  - UI: editor warmup badge now includes timeline (start/ready/last/deadline).
- Tests:
  - Not run (UI change only).
### 2026-02-05
- Changes:
  - UI: analyze shows warmup timeline (start/ready/last progress/deadline).
- Tests:
  - Not run (UI change only).
### 2026-02-05
- Changes:
  - UI: warmup badge now includes stable/IDR hints on transcode tiles.
- Tests:
  - Not run (UI change only).
### 2026-02-05
- Changes:
  - UI: analyze now shows detailed warmup diagnostics (ready/stable/IDR/timestamps).
- Tests:
  - Not run (UI change only).
### 2026-02-05
- Changes:
  - UI: compact view shows warmup status on transcode tiles.
- Tests:
  - Not run (UI change only).
### 2026-02-05
- Changes:
  - UI: analyze shows GPU overload reason and GPU metrics error.
- Tests:
  - Not run (UI change only).
### 2026-02-05
- Changes:
  - Transcode: publish selected GPU stats/limits/overload in status for UI.
  - UI: GPU info now reflects actual metrics and overload state.
  - AI: proxy requests write JSON body to temp file for curl payload.
- Tests:
  - Not run (UI/status changes).
### 2026-02-05
- Changes:
  - MPTS/CI: обновлён verify_mpts (UTF-8 marker, Bitrate parsing, устойчивость к префиксам логов).
  - MPTS: анализатор NIT декодирует network_name с учётом кодировки.
  - CI: check_changelog учитывает shallow clone; check_branch_name допускает codex/<topic>.
  - CI: smoke_mpts ослаблены проверки PID/PAT NIT для недетерминированного ремапа.
- Tests:
  - Not run (CI/doc updates; covered by CI).
### 2026-02-05
- Changes:
  - MPTS: не отправляет пустые PSI (PAT/SDT/NIT), если все сервисы отклонены (spts_only/strict_pnr).
  - Runtime: validate_stream_config больше не падает, когда MPTS stream не имеет поля input.
  - Fixtures: mpts_spts_only output URL исправлен (Astral URL options не парсятся через `?`).
- Tests:
  - `contrib/ci/smoke_mpts.sh`
  - `contrib/ci/smoke_mpts_pid_collision.sh`
  - `contrib/ci/smoke_mpts_pass_tables.sh`
  - `contrib/ci/smoke_mpts_strict_pnr.sh`
  - `contrib/ci/smoke_mpts_spts_only.sh`
  - `contrib/ci/smoke_mpts_auto_probe.sh`
### 2026-02-05
- Changes:
  - Release: исправлены кавычки в сборке bundle; обновлены SHA256 для ffmpeg sources.
  - Release: корректное определение версии из version.h для имени bundle (без падения при отсутствии ASTRA_VERSION).
  - CI: check_changelog учитывает shallow clone и подтягивает merge-base.
- Tests:
  - Not run (CI fix).
### 2026-02-05
- Changes:
  - Export: принудительно синхронизирует `enable` для streams/adapters с текущим состоянием БД.
- Tests:
  - Server: `./configure.sh && make` (root@178.212.236.2:/home/hex/astra).
  - UI (port 9060): `curl -I http://127.0.0.1:9060/index.html`
  - UI asset (port 9060): `curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - Auth (port 9060): `POST /api/v1/auth/login`
  - API (port 9060, cookie auth): `GET /api/v1/streams`, `GET /api/v1/settings`
  - Metrics/health (port 9060): `GET /api/v1/metrics`, `GET /api/v1/metrics?format=prometheus`, `GET /api/v1/health/*`
  - Config (port 9060, CSRF header): `POST /api/v1/config/validate`, `GET /api/v1/config/revisions`, `POST /api/v1/reload`
  - Export (port 9060): `GET /api/v1/export?include_users=0`
  - Export CLI: `./astra scripts/export.lua --data-dir ./data --output ./astra-export.json`
### 2026-02-05
- Changes:
  - UI: hide/remove Observability AI summary block from the page (AI uses it internally).
  - UI: AstralAI chat now shows attachment previews (image thumbnails + filenames).
  - UI: AstralAI chat shows inline image thumbnails and enhanced waiting animation.
  - UI: AstralAI chat `/help` returns local hints without calling AI.
  - AstralAI: normalize ai_api_base so trailing `/v1` is handled correctly.
- Tests:
  - `./astra scripts/tests/ai_openai_url_unit.lua`
### 2026-02-05
- Changes:
  - AstralAI: auto-include on-demand metrics in AI context when prompt asks for charts/metrics.
  - AstralAI: clamp and downsample metrics in context to reduce load.
- Tests:
  - `scripts/tests/ai_metrics_autoselect_unit.lua`
### 2026-02-05
- Changes:
  - UI: Observability/Help/Access отображаются только при включении соответствующих опций в Settings → General.
- Tests:
  - Not run (UI change only).
### 2026-02-05
- Changes:
  - AstralAI: default model `gpt-5.2` with fallback to `gpt-5-mini` and `gpt-4.1` on `model_not_found`.
  - AstralAI: auto-select logs/CLI context by prompt to reduce load.
  - AstralAI: allow optional `charts` field in AI responses (line/bar series).
  - AstralAI: AI summary no longer includes logs unless `include_logs=1` is set (lower load).
  - Observability: when `ai_metrics_on_demand=true`, metrics retention forced to `0` (no background rollups).
  - UI: AI chat no longer forces log inclusion; status shows effective model.
- Tests:
  - `./astra scripts/tests/ai_openai_model_fallback_unit.lua`
  - `./astra scripts/tests/ai_observability_on_demand_config_unit.lua`
  - `./astra scripts/tests/ai_logs_autoselect_unit.lua`
  - `./astra scripts/tests/ai_cli_autoselect_unit.lua`
### 2026-02-05
- Changes:
  - Analyze: модалка показывает подробные PSI/PMT/PID/codec данные через on-demand analyze API.
- Tests:
  - Not run (UI/API change only).
### 2026-02-05
- Changes:
  - AstralAI: default model set to `gpt-5.2` with automatic fallback to `gpt-5-mini` and `gpt-4.1` on `model_not_found`.
  - AstralAI: auto-select logs/CLI context by prompt to reduce load (logs/CLI only when needed).
  - Observability: when `ai_metrics_on_demand=true`, metrics retention is forced to `0` (no background rollups).
  - UI: AI chat no longer forces log inclusion; status uses default model when field is empty.
- Tests:
  - `./astra scripts/tests/ai_openai_model_fallback_unit.lua`
  - `./astra scripts/tests/ai_observability_on_demand_config_unit.lua`
### 2026-02-05
- Changes:
  - Streams/Adapters: при сохранении синхронизируется `enable` в config_json, чтобы disable не терялся в JSON и после рестарта.
- Tests:
  - Server: `./configure.sh && make` (root@178.212.236.2:/home/hex/astra).
  - UI (port 9060): `curl -I http://127.0.0.1:9060/index.html`
  - UI asset (port 9060): `curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - Auth (port 9060): `POST /api/v1/auth/login`
  - API (port 9060, cookie auth): `GET /api/v1/streams`, `GET /api/v1/settings`
  - Metrics/health (port 9060): `GET /api/v1/metrics`, `GET /api/v1/metrics?format=prometheus`, `GET /api/v1/health/*`
  - Config (port 9060, CSRF header): `POST /api/v1/config/validate`, `GET /api/v1/config/revisions`, `POST /api/v1/reload`
  - Export (port 9060): `GET /api/v1/export?include_users=0`
  - Export CLI: `./astra scripts/export.lua --data-dir ./data --output ./astra-export.json`
### 2026-02-05
- Changes:
  - UI Player: ссылка и кнопки Open/Copy используют `/play/<stream_id>`; для `<video>` выбирается прямой HTTP Play при поддержке MPEG-TS.
- Tests:
  - Not run (UI change only).
### 2026-02-05
- Changes:
  - Config: экспортирует основной JSON-конфиг при изменениях (streams/adapters/settings) при запуске с `--config *.json`.
  - Config: при ошибке apply откатывает основной JSON-конфиг к LKG-снимку.
- Tests:
  - Server: `./configure.sh && make` (root@178.212.236.2:/home/hex/astra).
  - UI (port 9060): `curl -I http://127.0.0.1:9060/index.html`
  - UI asset (port 9060): `curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - Auth (port 9060): `POST /api/v1/auth/login`
  - API (port 9060, cookie auth): `GET /api/v1/streams`, `GET /api/v1/settings`
  - Metrics/health (port 9060): `GET /api/v1/metrics`, `GET /api/v1/metrics?format=prometheus`, `GET /api/v1/health/*`
  - Config (port 9060, CSRF header): `POST /api/v1/config/validate`, `GET /api/v1/config/revisions`, `POST /api/v1/reload`
  - Export (port 9060): `GET /api/v1/export?include_users=0`
  - Export CLI: `./astra scripts/export.lua --data-dir ./data --output ./astra-export.json`
### 2026-02-05
- Changes:
  - Transcode failover: improved warmup/pending switch handling and return-to-primary logic.
- Tests:
  - Not run (transcode logic changes).
### 2026-02-05
- Changes:
  - Added ffmpeg warmup before failover switches (configurable via `backup_switch_warmup_sec`/`switch_warmup_sec`).
  - Exposed warmup status in transcode state and Analyze UI.
- Tests:
  - Not run (transcode logic/UI changes).
### 2026-02-05
- Changes:
  - UI: добавлена автоподсветка активного раздела Settings → General при прокрутке.
  - UI: убран блок Observability AI Summary, чтобы AI‑сводка запускалась только по запросу (API/Telegram).
- Tests:
  - Server: `./configure.sh && make` (root@178.212.236.2:/home/hex/astra).
  - UI (port 9060): `curl -I http://127.0.0.1:9060/index.html`
  - UI asset (port 9060): `curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - Auth (port 9060): `POST /api/v1/auth/login`
  - API (port 9060, cookie auth): `GET /api/v1/streams`, `GET /api/v1/settings`
  - Metrics/health (port 9060): `GET /api/v1/metrics`, `GET /api/v1/metrics?format=prometheus`, `GET /api/v1/health/*`
  - Config (port 9060, CSRF header): `POST /api/v1/config/validate`, `GET /api/v1/config/revisions`, `POST /api/v1/reload`
  - Export (port 9060): `GET /api/v1/export?include_users=0`
  - Export CLI: `./astra scripts/export.lua --data-dir ./data --output ./astra-export.json`
### 2026-02-05
- Changes:
  - UI: перестроена вкладка Settings → General на разделы и карточки с поиском, переключателем базовых/расширенных, sticky-панелью действий и едиными switch-контролами.
  - UI: добавлено подтверждение для Allow apply в AstraAI и переключатель отображения лимитов в разделе безопасности.
- Tests:
  - Server: `./configure.sh && make` (root@178.212.236.2:/home/hex/astra).
  - UI (port 9060): `curl -I http://127.0.0.1:9060/index.html`
  - UI asset (port 9060): `curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - Auth (port 9060): `POST /api/v1/auth/login`
  - API (port 9060, cookie auth): `GET /api/v1/streams`, `GET /api/v1/settings`
  - Metrics/health (port 9060): `GET /api/v1/metrics`, `GET /api/v1/metrics?format=prometheus`, `GET /api/v1/health/*`
  - Config (port 9060, CSRF header): `POST /api/v1/config/validate`, `GET /api/v1/config/revisions`, `POST /api/v1/reload`
  - Export (port 9060): `GET /api/v1/export?include_users=0`
  - Export CLI: `./astra scripts/export.lua --data-dir ./data --output ./astra-export.json`
### 2026-02-05
- Changes:
  - Added automatic contrib ffmpeg build fallback for mixaudio module when system libs are missing.
  - Enabled mixaudio and postgres module builds when dependencies are available (pkg-config/pg_config support).
- Tests:
  - Not run (build config change).
### 2026-02-05
- Changes:
  - Added memfd-backed HLS storage with on-demand activation and idle deactivation.
  - Served HLS from memory via new `hls_memfd` handler (sendfile when available).
  - Fixed memfd sendfile to use per-request offsets (safe concurrent segment fetch).
  - Skipped expired memfd segments for new requests after idle deactivation.
  - Enforced memfd memory limits by dropping the oldest non-busy segment (not just the head).
  - Marked HLS discontinuity when memfd drops a non-head segment under memory pressure.
  - Added per-stream segment lookup hash to avoid linear scans on memfd reads.
  - Added stream lookup hash for memfd streams to speed up hls_memfd touch/lookup.
  - Added stream-hash rehashing when memfd stream count grows.
  - Added stream-hash shrink/rehash on memfd stream removal.
  - Logged discontinuity when memfd drops a non-head segment under memory pressure.
  - Added `debug_hold_sec` for HLS memfd tests to pin the first segment.
  - Added HLS in-memory counters (`current_segments`, `current_bytes`) to stream status.
  - Added HLS memfd settings wiring + documentation and example config.
- Tests:
  - Server: `./configure.sh && make` (root@178.212.236.2:/home/hex/astra).
  - UI (port 9060): `curl -I http://127.0.0.1:9060/index.html`
  - UI asset (port 9060): `curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - API (port 9060, cookie auth): `GET /api/v1/streams`, `GET /api/v1/settings`
  - Metrics/health (port 9060): `GET /api/v1/metrics`, `GET /api/v1/metrics?format=prometheus`, `GET /api/v1/health/*`
  - Config (port 9060, CSRF): `POST /api/v1/config/validate`, `POST /api/v1/reload`
  - Export (port 9060): `GET /api/v1/export?include_users=0`
  - Export CLI: `./astra scripts/export.lua --data-dir ./data --output ./astra-export.json`
  - HLS memfd on-demand (port 9027): playlist/segment fetch + idle deactivate log + no files in hls_dir.
  - HLS HTTP Play (port 9026): `fixtures`-style smoke for cache headers + playlist/segment.
  - HLS memfd load sanity (dynamic port): 10 clients playlist/segment + stream-status counters.
  - HLS memfd idle (port 9030): old segment returns 404 after idle deactivation.
  - HLS memfd mem-limit drop (port 9031): drop log appears while a segment is busy.
  - HLS memfd hash lookup (port 9032): playlist/segment fetch returns 200.
  - HLS memfd stream hash (port 9037): playlist/segment fetch returns 200.
### 2026-02-05
- Changes:
  - Added `docs/API.md` with current API reference.
  - Added `ai_context` unit test.
  - Added AI context UI options for include logs/CLI.
  - Persisted AI Summary context options in UI.
  - Skipped AI log reads when retention is disabled (low‑load).
  - Added `docs/CLI.md` with CLI modes and examples.
  - Added curl examples for AI context parameters.
  - Expanded AI context API test to include analyze/femon inputs.
  - Fixed AI plan audit logging scope (log_audit now local in runtime).
  - Linked API/CLI/AstralAI docs in README.
  - Added AI context curl examples to AstralAI doc; noted CLI timeout requirement.
  - Added AstralAI test list to docs/TESTING.md.
  - Clarified stream/dvbls context sources (runtime/module for low‑load).
- Tests:
  - `./astra scripts/tests/ai_context_unit.lua`
  - `./astra scripts/tests/ai_context_cli_unit.lua`
  - `./astra scripts/tests/ai_runtime_context_unit.lua`
  - `./astra scripts/tests/ai_context_api_unit.lua`
  - `./astra scripts/tests/ai_plan_context_unit.lua`
### 2026-02-05
- Changes:
  - Added `ai_context.lua` to collect AI context from logs and CLI snapshots on demand.
  - Wired `/api/v1/ai/summary` to accept `include_logs` and `include_cli` params (stream/analyze/dvbls/femon).
  - Extended AI summary prompt with optional context payload (logs + CLI).
  - Added Observability UI controls for AI context (logs + CLI inputs).
  - Documented AI CLI context settings in `docs/ASTRAL_AI.md`.
- Tests:
  - Not run (UI + API wiring only).
### 2026-02-05
- Changes:
  - Added `ai_openai_client.lua` with centralized retries/backoff and rate-limit parsing.
  - Added `ai_charts.lua` and wired Telegram charts through it.
  - Added Observability “AI Summary” block (UI + `/api/v1/ai/summary?ai=1`).
  - Implemented Telegram `/ai` commands (summary/report/suggest/apply).
  - Added AI guardrails for destructive apply and `ai_change` audit event.
  - Added AI summary + charts unit tests.
  - Documented performance-first rule (min CPU/RAM/IO) in development guidelines.
  - Added on-demand AI metrics (logs + runtime snapshot) to avoid background rollup load.
  - Added on-demand metrics caching (TTL) to reduce repeated runtime scans.
- Tests:
  - Not run (unit files added only).
### 2026-02-05
- Changes:
  - Added observability data tables and rollup timers for AI logs/metrics.
  - Added AI observability API endpoints: `/api/v1/ai/logs`, `/api/v1/ai/metrics`, `/api/v1/ai/summary`.
  - Added Settings → General controls for observability retention + rollup interval.
  - Added Observability view with summary cards and charts.
  - Added Observability error log list (last 20 errors).
  - Added Telegram summary scheduler with optional charts and manual send.
  - Added optional AI summary (OpenAI) for Telegram reports when AI is enabled.
  - Extended Telegram summary charts (bitrate + streams down).
  - Reconfigured observability on settings updates.
- Tests:
  - Not run (UI + API wiring only).
### 2026-02-05
- Changes:
  - Added AstralAI scaffolding (AI runtime/tools stubs + API endpoints).
  - Implemented local AI plan diff (validate + snapshot + diff summary).
  - Added AI plan prompt mode (Responses API structured outputs).
  - Added safe AI context summary builder (streams/adapters).
  - Added AI audit log entries and retry/backoff with rate-limit header capture.
  - Added strict input validation for /api/v1/ai/plan.
  - Added AI plan smoke test fixture.
  - Added server-side validation for AI plan output schema.
  - Added AI apply: backup/validate/diff/apply with runtime reload + rollback.
  - Added AstralAI settings block in General UI (enable/model/apply toggles).
  - Bumped UI build stamp to 20260205q.
- Tests:
  - ./astra scripts/tests/ai_plan_smoke.lua
  - ./astra scripts/tests/ai_apply_smoke.lua
### 2026-02-05
- Changes:
  - Added View menu toggle to show/hide disabled streams.
  - Updated UI build stamp and asset version to 20260205p.
- Tests:
  - Not run (UI-only).
### 2026-02-05
- Changes:
  - Bumped UI asset version query to match build stamp (cache bust for app/styles).
- Tests:
  - Not run (UI-only).
### 2026-02-05
- Changes:
  - Startup log now includes SSL capability (helps diagnose HTTPS inputs).
- Tests:
  - Not run (log-only).
### 2026-02-05
- Changes:
  - Serve favicon via web static handler when available (avoid 204 placeholder).
- Tests:
  - Not run (server change).
### 2026-02-05
- Changes:
  - Added default favicon to stop /favicon.ico warnings in http_server logs.
- Tests:
  - Not run (static asset).
### 2026-02-05
- Changes:
  - Improved scan feedback by keeping dashboard notices stable (no premature clear).
  - Extended scan success notice duration; updated UI build stamp to 20260205o.
- Tests:
  - Not run (UI-only).
### 2026-02-05
- Changes:
  - Allow adapter scan even when lock/status is missing (with warning message).
- Tests:
  - Not run (UI-only).
### 2026-02-05
- Changes:
  - Documented DVB adapter UX polish in ROADMAP and PARITY.
- Tests:
  - Not run (docs-only).
### 2026-02-05
- Changes:
  - Expanded Help tab with failover and DVB scan instructions.
  - Updated UI build stamp to 20260205n.
- Tests:
  - Not run (UI-only).
### 2026-02-05
- Changes:
  - Ensured DVB list polling only starts when Adapters view is active.
  - Added status prefix in Detected DVB options for clearer BUSY/FREE visibility.
  - Updated UI build stamp to 20260205m.
- Tests:
  - Not run (UI-only).
### 2026-02-05
- Changes:
  - Clarified HTTP auth allow/deny placeholders with CIDR examples.
  - Updated UI build stamp to 20260205l.
- Tests:
  - Not run (UI-only).
### 2026-02-05
- Changes:
  - Scan button is now enabled even without status; shows a warning instead of blocking.
  - Updated UI build stamp to 20260205k.
- Tests:
  - Not run (UI-only).
### 2026-02-05
- Changes:
  - Stream status polling now runs only when Dashboard is open.
  - Updated UI build stamp to 20260205j.
- Tests:
  - Not run (UI-only).
### 2026-02-05
- Changes:
  - Adapter scan button now enables when signal is present (warns if no lock).
  - Updated UI build stamp to 20260205i.
- Tests:
  - Not run (UI-only).
### 2026-02-05
- Changes:
  - Reduced polling load: sessions/logs/access/adapters/buffers/splitters now poll only when their view is open.
  - Updated UI build stamp to 20260205h.
- Tests:
  - Not run (UI-only).
### 2026-02-05
- Changes:
  - Added LNB format validation in adapter editor.
  - Updated UI build stamp to 20260205g.
- Tests:
  - Not run (UI-only).
### 2026-02-05
- Changes:
  - HTTP auth allow/deny lists now support CIDR ranges.
  - Updated Help text for CIDR support and bumped UI build to 20260205f.
- Tests:
  - Not run (docs/runtime).
### 2026-02-05
- Changes:
  - Collapsed General settings with an “Show advanced settings” toggle.
  - Sessions list now filters inactive/ended entries in the UI.
  - Updated UI build stamp to 20260205e.
- Tests:
  - Not run (UI-only).
### 2026-02-05
- Changes:
  - Added `-pass` option to reset admin password to default (admin/admin).
  - Reset now bypasses password policy via a force-set path.
  - Added dashboard notice for scan add feedback.
  - Defaulted view mode to Cards with Compact tiles on first load.
  - Updated Help page and UI build stamp to 20260205d.
- Tests:
  - Not run (deploy-only).
### 2026-02-04
- Changes:
  - Fixed embedded launcher to treat JSON configs as server configs and skip the script arg in option parsing.
  - Bumped UI build stamp to 20260204m.
- Tests:
  - Not run (deploy-only).
### 2026-02-04
- Changes:
  - Refreshed `SKILL.md` and `AGENT.md` to reflect current UX updates, single-owner governance, and CI guardrails.
- Tests:
  - Not run (docs only).
### 2026-02-04
- Changes:
  - Default data directory now uses /etc/astral/<config>.data unless overridden by ASTRA_DATA_ROOT.
  - Added astral symlink alongside astra binary for simplified запуск.
  - Added ASTRA_WEB_DIR/ASTRAL_WEB_DIR override for UI path.
- Tests:
  - Not run (startup defaults).
### 2026-02-04
- Changes:
  - Stream editor General tab layout compacted (Name/ID/Type inline, smaller Description).
- Tests:
  - Not run (UI change).
### 2026-02-04
- Changes:
  - Reduced UI polling frequency and pause polling when tab is hidden.
  - Added 1s cache for /api/v1/stream-status to reduce load.
- Tests:
  - Not run (UI/API changes).
### 2026-02-04
- Changes:
  - Sessions list now drops stale HTTP clients to keep only active sessions.
- Tests:
  - Not run (runtime change).
### 2026-02-04
- Changes:
  - Stream apply now uses targeted runtime update instead of full reload.
- Tests:
  - Not run (runtime change).
### 2026-02-04
- Changes:
  - Added Sessions table actions to add client IPs to whitelist/block list.
- Tests:
  - Not run (UI change).
### 2026-02-04
- Changes:
  - Enforced HTTP auth allow/deny IP lists for stream access even when auth is disabled.
- Tests:
  - Not run (auth change).
### 2026-02-04
- Changes:
  - Guarded HTTP play client cleanup to avoid nil index crash on disconnect.
- Tests:
  - Not run (server change).
### 2026-02-04
- Changes:
  - Fixed HTTP play streaming response to return valid HTTP 200 status headers.
- Tests:
  - Not run (server change).
### 2026-02-04
- Changes:
  - Added config history deletion controls (per revision + delete all).
- Tests:
  - Not run (UI + API change).
### 2026-02-04
- Changes:
  - Added LNB sanitization for adapters to prevent startup aborts on invalid format.
  - DVB adapter UI now refreshes on view with busy badge + refresh button.
- Tests:
  - Not run (Lua + UI changes).
### 2026-02-04
- Changes:
  - Updated `AGENT.md` and `SKILL.md` for multi-agent coordination and ownership rules.
- Tests:
  - Not run (docs only).
### 2026-02-04
- Changes:
  - Added Codex multi-agent environment setup guide.
- Tests:
  - Not run (docs only).
### 2026-02-04
- Changes:
  - Added CI checks for branch naming and CHANGELOG updates.
  - Updated workflow docs and agent instructions for PR-first flow.
- Tests:
  - Not run (CI/docs only).
### 2026-02-04
- Changes:
  - Set CODEOWNERS to a single owner (`@siriushex`) and simplified CODEOWNERS check.
  - Updated workflow doc to reflect single-owner approval policy.
- Tests:
  - Not run (docs/CI only).
### 2026-02-04
- Changes:
  - Added CODEOWNERS ownership map and CI guard for required ownership entries.
  - Added strict team workflow documentation and PR template.
- Tests:
  - Not run (docs/CI only).
### 2026-02-04
- Changes:
  - Made General settings more compact with show/hide toggles for optional sections.
- Tests:
  - Not run (UI change).
### 2026-02-04
- Changes:
  - Added SoftCAM id dropdown in Input settings populated from configured SoftCAMs.
- Tests:
  - Not run (UI change).
### 2026-02-04
- Changes:
  - Added `/api/v1/dvb-adapters` and UI selection of detected DVB devices with busy/free status.
  - Adapter cards show hardware availability badges when dvbls is available.
- Tests:
  - Not run (API + UI changes).
### 2026-02-04
- Changes:
  - Added Astral watchdog templates + installer for CPU/RAM monitoring.
  - Documented watchdog installation and configuration in `docs/OPERATIONS.md`.
- Tests:
  - Not run (ops scripts + docs).
### 2026-02-04
- Changes:
  - Synced `PLAN.md` with `docs/PARITY.md`/`docs/ROADMAP.md` and added phase DoD/gates.
  - Implemented CAS defaults in settings + stream runtime; added License view with `/api/v1/license`.
  - Extended CI smoke to hit the license endpoint.
- Tests:
  - Not run (docs + UI + API/runtime change).
### 2026-02-04
- Changes:
  - Added pause/refresh controls for Sessions and pause/clear for Access logs.
  - Debounced filters and reduced DOM churn for sessions/logs rendering.
  - Marked Sessions/Logs UX polish as done in `PLAN.md`.
- Tests:
  - Not run (UI change).
### 2026-02-04
- Changes:
  - Marked Config history UX as done in `PLAN.md`.
- Tests:
  - Not run (docs change).
### 2026-02-04
- Changes:
  - Added HLS discontinuity handling on input switch.
  - Added HLS failover smoke fixture and AGENT steps.
  - Marked HLS failover resilience as done in `PLAN.md`.
- Tests:
  - Not run (C/runtime + docs change).
### 2026-02-04
- Changes:
  - Added access log visible count and limit clamp.
- Tests:
  - Not run (UI change).
### 2026-02-04
- Changes:
  - Added log limit selector and visible count in Logs view.
- Tests:
  - Not run (UI change).
### 2026-02-04
- Changes:
  - Added config history error details modal and copy action.
- Tests:
  - Not run (UI change).
### 2026-02-04
- Changes:
  - Added log pause/resume control in UI.
- Tests:
  - Not run (UI change).
### 2026-02-04
- Changes:
  - Added CI job for MPTS smoke coverage.
- Tests:
  - Not run (CI change).
### 2026-02-04
- Changes:
  - Hid CAS/License placeholder sections in UI.
  - Added best-effort runtime mapping for MPTS config fields.
  - Added MPTS smoke fixture/script and testing doc note.
- Tests:
  - Not run (UI + runtime change).
### 2026-02-04
- Changes:
  - Added CI job to build ASTRAL bundle and run bundle smoke.
  - Consolidated startup log to include edition + ffmpeg/ffprobe versions.
- Tests:
  - Not run (CI change).
### 2026-02-04
- Changes:
  - Adjusted bundle build script to avoid bash readarray dependency.
- Tests:
  - Not run (script change).
### 2026-02-04
- Changes:
  - Added ASTRAL bundle build script and ffmpeg source manifest (SHA256 enforced).
  - Added bundle smoke test and transcode fixture for bundled ffmpeg.
  - Added transcode bundle documentation and README link.
- Tests:
  - Not run (bundle packaging).
### 2026-02-04
- Changes:
  - Added General settings fields for ffmpeg/ffprobe path overrides.
- Tests:
  - Not run (UI change).
### 2026-02-04
- Changes:
  - Added ffmpeg/ffprobe path resolver with settings/env/bundle defaults.
  - Added `/api/v1/tools` and startup log for resolved tools/edition.
- Tests:
  - Not run (core change).
### 2026-02-04
- Changes:
  - Added Softcam settings UI (list + modal) backed by settings.
  - Added CAS/License section notes that they are not wired yet.
  - Updated `SKILL.md` to reflect the new UI state.
- Tests:
  - Not run (UI change).
### 2026-02-04
- Changes:
  - Added `.github/workflows/ci.yml` for build + smoke + telegram unit.
- Tests:
  - Not run (CI only).
### 2026-02-04
- Changes:
  - Added core docs: ARCHITECTURE, TESTING, OPERATIONS, ROADMAP.
  - Renamed parity matrix to `docs/PARITY.md` and linked it from README/PLAN/SKILL.
- Tests:
  - `./configure.sh`
  - `make`
  - `contrib/ci/smoke.sh`
### 2026-02-04
- Changes:
  - Added Servers settings UI with test endpoint and remote health check.
- Tests:
  - Not run (UI + API change).
### 2026-02-04
- Changes:
  - Added Groups settings UI with stream group assignment and playlist group-title mapping.
- Tests:
  - Not run (UI + server change).
### 2026-02-04
- Changes:
  - Added Telegram alerts notifier with dedupe/throttling, stream/input events, and config reload alerts.
  - Added Telegram settings UI (enable, level, token/chat ID) with test endpoint and masking in settings API.
  - Added Telegram unit tests and mock server helper.
- Tests:
  - `./astra scripts/tests/telegram_unit.lua`
### 2026-02-04
- Changes:
  - Added InfluxDB export settings and runtime metrics push.
- Tests:
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 nohup ./astra /home/hex/test.json -p 9060` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 'TOKEN=$(curl -i -s -X POST http://127.0.0.1:9060/api/v1/auth/login -H "Content-Type: application/json" --data-binary "{\"username\":\"admin\",\"password\":\"admin\"}" | python3 -c "import re,sys; text=sys.stdin.read(); m=re.search(r\"(?i)set-cookie:.*astra_session=([^;]+)\", text); print(m.group(1) if m else \"\")"); curl -s http://127.0.0.1:9060/api/v1/streams -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/settings -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/metrics -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s "http://127.0.0.1:9060/api/v1/metrics?format=prometheus" -H "Cookie: astra_session=$TOKEN" | head -n 1; curl -s http://127.0.0.1:9060/api/v1/health/process -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/health/inputs -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/health/outputs -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s -X POST http://127.0.0.1:9060/api/v1/config/validate -H "Cookie: astra_session=$TOKEN" -H "X-CSRF-Token: $TOKEN" -H "Content-Type: application/json" --data-binary "{}" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/config/revisions -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s -X POST http://127.0.0.1:9060/api/v1/reload -H "Cookie: astra_session=$TOKEN" -H "X-CSRF-Token: $TOKEN" >/dev/null; curl -s "http://127.0.0.1:9060/api/v1/export?include_users=0" -H "Cookie: astra_session=$TOKEN" | head -n 1'`
### 2026-02-04
- Changes:
  - Added General stream defaults (timeouts/backup/keep-active) and applied them at runtime.
- Tests:
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 nohup ./astra /home/hex/test.json -p 9060` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 'TOKEN=$(curl -i -s -X POST http://127.0.0.1:9060/api/v1/auth/login -H "Content-Type: application/json" --data-binary "{\"username\":\"admin\",\"password\":\"admin\"}" | python3 -c "import re,sys; text=sys.stdin.read(); m=re.search(r\"(?i)set-cookie:.*astra_session=([^;]+)\", text); print(m.group(1) if m else \"\")"); curl -s http://127.0.0.1:9060/api/v1/streams -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/settings -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/metrics -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s "http://127.0.0.1:9060/api/v1/metrics?format=prometheus" -H "Cookie: astra_session=$TOKEN" | head -n 1; curl -s http://127.0.0.1:9060/api/v1/health/process -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/health/inputs -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/health/outputs -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s -X POST http://127.0.0.1:9060/api/v1/config/validate -H "Cookie: astra_session=$TOKEN" -H "X-CSRF-Token: $TOKEN" -H "Content-Type: application/json" --data-binary "{}" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/config/revisions -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s -X POST http://127.0.0.1:9060/api/v1/reload -H "Cookie: astra_session=$TOKEN" -H "X-CSRF-Token: $TOKEN" >/dev/null; curl -s "http://127.0.0.1:9060/api/v1/export?include_users=0" -H "Cookie: astra_session=$TOKEN" | head -n 1'`
### 2026-02-04
- Changes:
  - Added libdvbcsa auto-detection in `configure.sh` (biss_encrypt builds when the library is installed).
- Tests:
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 nohup ./astra /home/hex/test.json -p 9060` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 'TOKEN=$(curl -i -s -X POST http://127.0.0.1:9060/api/v1/auth/login -H "Content-Type: application/json" --data-binary "{\"username\":\"admin\",\"password\":\"admin\"}" | python3 -c "import re,sys; text=sys.stdin.read(); m=re.search(r\"(?i)set-cookie:.*astra_session=([^;]+)\", text); print(m.group(1) if m else \"\")"); curl -s http://127.0.0.1:9060/api/v1/streams -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/settings -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/metrics -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s "http://127.0.0.1:9060/api/v1/metrics?format=prometheus" -H "Cookie: astra_session=$TOKEN" | head -n 1; curl -s http://127.0.0.1:9060/api/v1/health/process -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/health/inputs -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/health/outputs -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s -X POST http://127.0.0.1:9060/api/v1/config/validate -H "Cookie: astra_session=$TOKEN" -H "X-CSRF-Token: $TOKEN" -H "Content-Type: application/json" --data-binary "{}" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/config/revisions -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s -X POST http://127.0.0.1:9060/api/v1/reload -H "Cookie: astra_session=$TOKEN" -H "X-CSRF-Token: $TOKEN" >/dev/null; curl -s "http://127.0.0.1:9060/api/v1/export?include_users=0" -H "Cookie: astra_session=$TOKEN" | head -n 1'`
### 2026-02-04
- Changes:
  - Added BISS/SRT args hints and validation; improved HLS inline parsing in outputs.
- Tests:
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh --with-libdvbcsa` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 nohup ./astra /home/hex/test.json -p 9060` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 'TOKEN=$(curl -i -s -X POST http://127.0.0.1:9060/api/v1/auth/login -H "Content-Type: application/json" --data-binary "{\"username\":\"admin\",\"password\":\"admin\"}" | python3 -c "import re,sys; text=sys.stdin.read(); m=re.search(r\"(?i)set-cookie:.*astra_session=([^;]+)\", text); print(m.group(1) if m else \"\")"); curl -s http://127.0.0.1:9060/api/v1/streams -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/settings -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/metrics -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s "http://127.0.0.1:9060/api/v1/metrics?format=prometheus" -H "Cookie: astra_session=$TOKEN" | head -n 1; curl -s http://127.0.0.1:9060/api/v1/health/process -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/health/inputs -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/health/outputs -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s -X POST http://127.0.0.1:9060/api/v1/config/validate -H "Cookie: astra_session=$TOKEN" -H "X-CSRF-Token: $TOKEN" -H "Content-Type: application/json" --data-binary "{}" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/config/revisions -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s -X POST http://127.0.0.1:9060/api/v1/reload -H "Cookie: astra_session=$TOKEN" -H "X-CSRF-Token: $TOKEN" >/dev/null; curl -s "http://127.0.0.1:9060/api/v1/export?include_users=0" -H "Cookie: astra_session=$TOKEN" | head -n 1'`
### 2026-02-04
- Changes:
  - Added General settings controls for session TTL, CSRF, and login rate limiting.
- Tests:
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh --with-libdvbcsa` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 nohup ./astra /home/hex/test.json -p 9060` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 grep -n "settings-auth-session-ttl" /home/hex/astra/web/index.html`
  - `ssh root@178.212.236.2 -p 40242 'TOKEN=$(curl -i -s -X POST http://127.0.0.1:9060/api/v1/auth/login -H "Content-Type: application/json" --data-binary "{\"username\":\"admin\",\"password\":\"admin\"}" | awk -F"astra_session=" "/Set-Cookie/ {print $2}" | cut -d";" -f1 | head -n 1); curl -s http://127.0.0.1:9060/api/v1/streams -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/settings -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/metrics -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s "http://127.0.0.1:9060/api/v1/metrics?format=prometheus" -H "Cookie: astra_session=$TOKEN" | head -n 1; curl -s http://127.0.0.1:9060/api/v1/health/process -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/health/inputs -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/health/outputs -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s -X POST http://127.0.0.1:9060/api/v1/config/validate -H "Cookie: astra_session=$TOKEN" -H "X-CSRF-Token: $TOKEN" -H "Content-Type: application/json" --data-binary "{}" >/dev/null; curl -s http://127.0.0.1:9060/api/v1/config/revisions -H "Cookie: astra_session=$TOKEN" >/dev/null; curl -s -X POST http://127.0.0.1:9060/api/v1/reload -H "Cookie: astra_session=$TOKEN" -H "X-CSRF-Token: $TOKEN" >/dev/null; curl -s "http://127.0.0.1:9060/api/v1/export?include_users=0" -H "Cookie: astra_session=$TOKEN" | head -n 1'`
### 2026-02-04
- Changes:
  - Added per-output BISS key field in the Output modal (applies to any output type).
- Tests:
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 nohup ./astra /home/hex/test.json -p 9060` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/index.html | grep -n "output-biss"`
  - `ssh root@178.212.236.2 -p 40242 curl -s -X POST http://127.0.0.1:9060/api/v1/auth/login -H 'Content-Type: application/json' --data-binary '{"username":"admin","password":"admin"}'`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/streams -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/settings -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/metrics -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s "http://127.0.0.1:9060/api/v1/metrics?format=prometheus" -H "Cookie: astra_session=<TOKEN>" | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/health/process -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/health/inputs -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/health/outputs -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s -X POST http://127.0.0.1:9060/api/v1/config/validate -H "Cookie: astra_session=<TOKEN>" -H "X-CSRF-Token: <TOKEN>" -H 'Content-Type: application/json' --data-binary '{}'`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/config/revisions -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s -X POST http://127.0.0.1:9060/api/v1/reload -H "Cookie: astra_session=<TOKEN>" -H "X-CSRF-Token: <TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s "http://127.0.0.1:9060/api/v1/export?include_users=0" -H "Cookie: astra_session=<TOKEN>" | head -n 1`
### 2026-02-04
- Changes:
  - Extended Output modal: HLS advanced fields, SCTP toggles, NP buffer fill, and SRT bridge advanced options.
- Tests:
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 nohup ./astra /home/hex/test.json -p 9060` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/index.html | grep -n "output-hls-naming"`
  - `ssh root@178.212.236.2 -p 40242 curl -s -X POST http://127.0.0.1:9060/api/v1/auth/login -H 'Content-Type: application/json' --data-binary '{"username":"admin","password":"admin"}'`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/streams -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/settings -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/metrics -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s "http://127.0.0.1:9060/api/v1/metrics?format=prometheus" -H "Cookie: astra_session=<TOKEN>" | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/health/process -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/health/inputs -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/health/outputs -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s -X POST http://127.0.0.1:9060/api/v1/config/validate -H "Cookie: astra_session=<TOKEN>" -H "X-CSRF-Token: <TOKEN>" -H 'Content-Type: application/json' --data-binary '{}'`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/config/revisions -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s -X POST http://127.0.0.1:9060/api/v1/reload -H "Cookie: astra_session=<TOKEN>" -H "X-CSRF-Token: <TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s "http://127.0.0.1:9060/api/v1/export?include_users=0" -H "Cookie: astra_session=<TOKEN>" | head -n 1`
### 2026-02-04
- Changes:
  - Added password policy settings in Users section (min length and required character classes).
- Tests:
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 nohup ./astra /home/hex/test.json -p 9060` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/index.html | grep -n "password-min-length"`
  - `ssh root@178.212.236.2 -p 40242 curl -s -X POST http://127.0.0.1:9060/api/v1/auth/login -H 'Content-Type: application/json' --data-binary '{"username":"admin","password":"admin"}'`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/streams -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/settings -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/metrics -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s "http://127.0.0.1:9060/api/v1/metrics?format=prometheus" -H "Cookie: astra_session=<TOKEN>" | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/health/process -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/health/inputs -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/health/outputs -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s -X POST http://127.0.0.1:9060/api/v1/config/validate -H "Cookie: astra_session=<TOKEN>" -H "X-CSRF-Token: <TOKEN>" -H 'Content-Type: application/json' --data-binary '{}'`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/config/revisions -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s -X POST http://127.0.0.1:9060/api/v1/reload -H "Cookie: astra_session=<TOKEN>" -H "X-CSRF-Token: <TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s "http://127.0.0.1:9060/api/v1/export?include_users=0" -H "Cookie: astra_session=<TOKEN>" | head -n 1`
### 2026-02-04
- Changes:
  - Added General settings fields for event webhook, analyze concurrency, and log/access log retention limits.
  - Treated outputs without explicit format as raw strings during save to avoid “format is required” errors.
  - Added `docs/astral-parity.md` and updated planning/skill docs for parity tracking.
- Tests:
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 nohup ./astra /home/hex/test.json -p 9060` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 curl -s -X POST http://127.0.0.1:9060/api/v1/auth/login -H 'Content-Type: application/json' --data-binary '{"username":"admin","password":"admin"}'`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/streams -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/settings -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/metrics -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s "http://127.0.0.1:9060/api/v1/metrics?format=prometheus" -H "Cookie: astra_session=<TOKEN>" | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/health/process -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/health/inputs -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/health/outputs -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s -X POST http://127.0.0.1:9060/api/v1/config/validate -H "Cookie: astra_session=<TOKEN>" -H "X-CSRF-Token: <TOKEN>" -H 'Content-Type: application/json' --data-binary '{}'`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/config/revisions -H "Cookie: astra_session=<TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s -X POST http://127.0.0.1:9060/api/v1/reload -H "Cookie: astra_session=<TOKEN>" -H "X-CSRF-Token: <TOKEN>"`
  - `ssh root@178.212.236.2 -p 40242 curl -s "http://127.0.0.1:9060/api/v1/export?include_users=0" -H "Cookie: astra_session=<TOKEN>" | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 ./astra scripts/export.lua --data-dir /home/hex/test.data --output /home/hex/astra-export.json` (in `/home/hex/astra`)
### 2026-02-03
- Changes:
  - Added MPTS tab (General/NIT/Advanced) and persisted MPTS config under `mpts_config` in stream settings.
  - Added `stream://` input type to the input editor for MPTS-friendly chaining.
  - Added UI toggle to disable MPTS fields when MPTS is off.
- Tests:
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 ./astra test.json -p 9060` (restart)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/index.html | grep -n "data-tab=\\\"mpts\\\""`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/index.html | grep -n "input-stream-id"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | grep -n "mptsCountry"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | grep -n "inputStreamId"`
### 2026-02-03
- Changes:
  - Replaced the EPG placeholder with editable fields (XMLTV ID, format, destination, codepage) and save them into stream config.
  - Added minimal EPG export on boot and stream changes (channels-only XMLTV/JSON).
  - Added EPG export interval setting and background timer for periodic exports.
- Tests:
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 ./astra test.json -p 9060` (restart)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/index.html | grep -n "settings-epg-interval"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | grep -n "epg_export_interval_sec"`
### 2026-02-03
- Changes:
  - Added stream-level exclude PID filter (`filter~`) with UI field and backend propagation to inputs.
  - Added Advanced tab checkboxes for SDT/EIT pass/disable flags and no-reload, applied to inputs when set.
- Tests:
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 ./astra test.json -p 9060` (restart)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/index.html | grep -n "stream-filter-exclude"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/index.html | grep -n "stream-no-sdt"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | grep -n "streamFilterExclude"`
### 2026-02-03
- Changes:
  - Allow streams to be saved with no outputs by filtering empty output rows in the UI.
  - When inline output parsing fails, fall back to saving the raw URL string instead of erroring on missing format.
  - Replace raw network errors in stream/adapter/login actions with a clearer allowlist-aware message.
- Tests:
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 ./astra test.json -p 9060` (restart)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | grep -n "formatNetworkError"`
### 2026-02-03
- Changes:
  - Treat empty numeric fields in the UI as unset so stream defaults apply (avoids invalid 0 values like `no_data_timeout_sec`).
  - Auto-generate stream IDs from names for new streams and keep HLS defaults in sync.
  - Validate `no_data_timeout_sec` in the UI to reject values below 1.
  - Sanitize stream config timing fields on the server before validation.
  - Follow HTTP redirects in the HTTP buffer reader and support `#ua`/`#user_agent` hints for buffer inputs.
  - Added inline output URL editing in stream Output List with best-effort parsing.
  - Allow renaming stream and adapter IDs in the UI, including dvb:// adapter reference updates.
  - Hide HLSSplitter/Buffer tools by default and enable them from Settings → General.
  - Preserve string outputs in the stream editor and validate them correctly (fixes "format is required" when outputs are URLs).
  - Allow streams to be saved without any outputs.
  - Replace raw "Failed to fetch" with a clearer network error message and retry API calls once.
  - Default stream backup mode is now passive; `backup_type: "disable"` is treated as `disabled`.
  - Render disabled streams with a muted/gray status styling instead of warning red.
  - Refreshed `SKILL.md` to lock workflow invariants and prevent lost updates.
  - Added Service tab fields (service type, codepage, HbbTV URL, CAS) with config wiring.
  - Support service type override in SDT and optional codepage encoding for service/provider strings.
  - Added Remap tab PID filter with validation and stream config wiring.
- Tests:
  - `curl -I http://127.0.0.1:8020/index.html`
  - `POST http://127.0.0.1:8020/api/v1/auth/login` (admin/admin)
  - `GET http://127.0.0.1:8020/api/v1/streams`
  - `GET http://127.0.0.1:8020/api/v1/stream-status`
  - `GET http://127.0.0.1:8020/api/v1/logs?limit=200`
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242` buffer smoke test (port 9047; HTTP buffer `sync_ok True`, failover to backup input)
  - `./astra scripts/server.lua -p 8015 --data-dir ./data_ui_check --web-dir ./web`
  - `curl -I http://127.0.0.1:8015/index.html`
  - `POST http://127.0.0.1:8015/api/v1/auth/login` (admin/admin)
  - `PUT http://127.0.0.1:8015/api/v1/settings` (`ui_splitter_enabled`, `ui_buffer_enabled`)
  - `POST/DELETE http://127.0.0.1:8015/api/v1/adapters` (rename adapter)
  - `POST/PUT/DELETE http://127.0.0.1:8015/api/v1/streams` (rename stream + update dvb:// input)
  - `ssh root@178.212.236.2 -p 40242 ./astra scripts/server.lua -p 9055 --data-dir ./data_ui_server --web-dir ./web`
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9055/index.html`
  - `ssh root@178.212.236.2 -p 40242 POST http://127.0.0.1:9055/api/v1/auth/login` (admin/admin)
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | sed -n '1357,1375p'`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | sed -n '5500,5535p'`
  - `ssh root@178.212.236.2 -p 40242 ./astra test.json -p 9060` (restart)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | sed -n '1357,1366p'`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | sed -n '580,650p'`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | sed -n '7125,7185p'`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | sed -n '7600,7685p'`
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 ./astra test.json -p 9060` (restart)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/index.html | grep -n "Default (passive)"`
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 ./astra test.json -p 9060` (restart)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/styles.css | grep -n "tile.disabled"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | grep -n "Disabled"`
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 ./astra test.json -p 9060` (restart)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | head -n 1`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/index.html | grep -n "stream-service-type"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | grep -n "service_type_id"`
  - `ssh root@178.212.236.2 -p 40242 ./configure.sh` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 make` (in `/home/hex/astra`)
  - `ssh root@178.212.236.2 -p 40242 ./astra test.json -p 9060` (restart)
  - `ssh root@178.212.236.2 -p 40242 curl -I http://127.0.0.1:9060/index.html`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/index.html | grep -n "stream-filter"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/app.js | grep -n "streamFilter"`
  - `ssh root@178.212.236.2 -p 40242 curl -s http://127.0.0.1:9060/api/v1/stream-status -H "Authorization: Bearer <token>"` (backup_type passive; disable → disabled)
  - `ssh root@178.212.236.2 -p 40242 PUT http://127.0.0.1:9055/api/v1/settings` (`ui_splitter_enabled`, `ui_buffer_enabled`)

### 2025-12-29
- Changes:
  - Added config revision history with LKG snapshots, boot markers, and admin restore endpoint.
  - Added config validation and safe reload endpoints, plus UI Config History panel with restore actions.
  - Added auto-rollback to LKG on failed reload/boot and marked boot failures.
- Tests:
  - `./configure.sh`
  - `make`
  - `tail -n 120 /home/hex/astra-server.log`
  - `tail -n 80 /home/hex/astra-keepalive.log`

### 2025-12-28
- Changes:
  - Added UDP output audio-fix (AAC normalize) runtime: analyzer probe + ffmpeg audio pass with exclusive output ownership and restart on input switch.
  - Exposed output audio-fix status in stream-status and wired Output List toggle/status + UDP audio-fix settings.
  - Documented UDP audio-fix and added an optional smoke test.
- Tests:
  - `./configure.sh`
  - `make`
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `tail -n 50 /home/hex/astra/astra-9000.log`

### 2025-12-28
- Changes:
  - Format output list URLs without protocol labels and normalize by output type (udp/http/hls/srt/rtp/file).
  - Show HLS paths as file URLs when only filesystem directories are known.
  - Add tooltip support for full output URLs in the list.
- Tests:
  - Not run (UI change only).

### 2025-12-28
- Changes:
  - Prevent passive backup from probing or switching while the active input is OK.
  - Mark unchecked passive inputs as UNKNOWN and style the UI badge accordingly.
  - Extend failover smoke notes with a passive stability check.
- Tests:
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts udp://127.0.0.1:13000?pkt_size=1316`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=800 -c:v mpeg2video -c:a mp2 -f mpegts udp://127.0.0.1:13001?pkt_size=1316`
  - `./astra /tmp/failover_test.json -p 9014 --data-dir ./data_failover_9014 --web-dir ./web`
  - `POST http://127.0.0.1:9014/api/v1/auth/login` (admin/admin)
  - `GET http://127.0.0.1:9014/api/v1/stream-status/failover_passive`
  - `GET http://127.0.0.1:9014/api/v1/stream-status/failover_active`
  - `GET http://127.0.0.1:9014/api/v1/stream-status/failover_active_stop`
  - `GET http://127.0.0.1:9014/api/v1/stream-status/failover_disabled`

### 2025-12-28
- Changes:
  - Use only the active input when building ffmpeg transcode args (single `-i`).
  - Expose `active_input_url` and `ffmpeg_input_url` in transcode status and stream status.
  - Show read-only transcode input in the editor and document the new status fields.
  - Extend transcode smoke notes to assert active vs ffmpeg input URLs.
- Tests:
  - `./configure.sh`
  - `make`
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `./astra ./fixtures/ada2-10815.json -p 9001 --data-dir ./data_test --web-dir ./web`
  - `POST http://127.0.0.1:9001/api/v1/auth/login` (admin/admin)
  - `GET http://127.0.0.1:9001/api/v1/settings`
  - `GET http://127.0.0.1:9001/api/v1/streams`
  - `./astra ./fixtures/sample.lua -p 9002 --data-dir ./data_test2 --web-dir ./web`
  - `POST http://127.0.0.1:9002/api/v1/auth/login` (admin/admin)
  - `GET http://127.0.0.1:9002/api/v1/settings`
  - `GET http://127.0.0.1:9002/api/v1/streams`
  - `./astra ./data_test_missing.json -p 9013`
  - `curl -I http://127.0.0.1:9013/index.html`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=1000 -c:v libx264 -preset veryfast -tune zerolatency -g 50 -keyint_min 50 -sc_threshold 0 -c:a aac -b:a 128k -f mpegts udp://127.0.0.1:12100?pkt_size=1316`
  - `./astra ./fixtures/transcode_cpu.json -p 9005 --data-dir ./data_transcode --web-dir ./web`
  - `POST http://127.0.0.1:9005/api/v1/auth/login`
  - `GET http://127.0.0.1:9005/api/v1/transcode-status/transcode_cpu_test` (RUNNING, `active_input_url` == `ffmpeg_input_url`)
  - `GET http://127.0.0.1:9005/api/v1/alerts?limit=5&stream_id=transcode_cpu_test` (after stopping input; `TRANSCODE_STALL`)
  - Not run: authenticated `/api/v1/streams` + `/api/v1/settings` + metrics/health/export on port 9000 (missing credentials).

### 2025-12-27
- Changes:
  - Add new stream backup modes (active, passive, disabled, active_stop_if_all_inactive) with stop-if-all-inactive logic.
  - Apply analyzer-based backup failover to transcode inputs with per-input status and restart on switch.
  - Reset input health state on activation to avoid passive failover flapping.
  - Update Backup UI fields/modes, fixtures, smoke docs, and stream backup documentation.
  - Adjust failover smoke expectations for passive mode and stop-if-all-inactive timing.
- Tests:
  - `./configure.sh`
  - `make`
  - `find /home/hex/astra -type f -exec touch -c {} +`
  - `make`
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `./astra ./fixtures/ada2-10815.json -p 9001 --data-dir ./data_test --web-dir ./web`
  - `POST http://127.0.0.1:9001/api/v1/auth/login` (admin/admin)
  - `GET http://127.0.0.1:9001/api/v1/settings` (http_play_stream)
  - `GET http://127.0.0.1:9001/api/v1/streams`
  - `./astra ./fixtures/sample.lua -p 9002 --data-dir ./data_test2 --web-dir ./web`
  - `POST http://127.0.0.1:9002/api/v1/auth/login` (admin/admin)
  - `GET http://127.0.0.1:9002/api/v1/settings` (hls_duration)
  - `GET http://127.0.0.1:9002/api/v1/streams`
  - `./astra ./data_test_missing.json -p 9013`
  - `curl -I http://127.0.0.1:9013/index.html`
  - Failover smoke: ffmpeg primary/backup + `./astra ./fixtures/failover.json -p 9004 --data-dir ./data_failover --web-dir ./web` with stream-status checks for passive/active/active_stop/disabled.
  - Not run: authenticated `/api/v1/streams` + `/api/v1/settings` + metrics/health/export on port 9000 (missing credentials).

### 2025-12-27
- Changes:
  - Move transcode restart/monitor settings to per-output watchdogs and drop user probe_url.
  - Add per-output monitor engines (ffprobe/auto/Astra Analyze), low-bitrate watchdog, and cooldown.
  - Expose per-output monitor status in transcode/stream status responses.
  - Update transcode docs and smoke notes for per-output monitor defaults.
- Tests:
  - `./configure.sh`
  - `make`
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=1000 -c:v libx264 -preset veryfast -tune zerolatency -g 50 -keyint_min 50 -sc_threshold 0 -c:a aac -b:a 128k -f mpegts udp://127.0.0.1:12100?pkt_size=1316`
  - `./astra ./fixtures/transcode_cpu.json -p 9005 --data-dir ./data_transcode --web-dir ./web &`
  - `POST http://127.0.0.1:9005/api/v1/auth/login`
  - `GET http://127.0.0.1:9005/api/v1/transcode-status/transcode_cpu_test`
  - `GET http://127.0.0.1:9005/api/v1/alerts?limit=5&stream_id=transcode_cpu_test` (TRANSCODE_STALL)
  - Not run: authenticated `/api/v1/streams` + `/api/v1/settings` on port 9000 (missing credentials).

### 2025-12-27
- Changes:
  - Add stream list view modes (table/compact/cards) with view menu and persistence.
  - Add Light/Dark/Auto theme variables and UI theme switching.
  - Wire stream table/compact actions to existing stream controls.
- Tests:
  - `./configure.sh`
  - `make`
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`

### 2025-12-27
- Changes:
  - Auto-fit tile text (title, bitrate, meta) and add consistent bitrate placeholders.
  - Prevent tile input rows from overflowing by wrapping badges/labels/copy button.
  - Truncate buffer card names/meta to avoid overflow in narrow panes.
- Tests:
  - `./configure.sh`
  - `make`
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`

### 2025-12-27
- Changes:
  - Keep HTTP output instances alive across stream refresh to avoid rebind aborts when ffmpeg inherits sockets.
  - Clean up empty HTTP output instances after refresh.
  - Treat existing HTTP output instances as valid for port checks (avoid force refresh regressions).
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra --log /home/hex/astra-keepalive.log --no-stdout scripts/server.lua -p 9016 --data-dir /home/hex/astra-data-keepalive --web-dir ./web &`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=160x90:rate=25 -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts udp://127.0.0.1:12000?pkt_size=1316`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=160x90:rate=25 -f lavfi -i sine=frequency=800 -c:v mpeg2video -c:a mp2 -f mpegts udp://127.0.0.1:12100?pkt_size=1316`
  - `POST http://127.0.0.1:9016/api/v1/auth/login`
  - `POST http://127.0.0.1:9016/api/v1/streams` (http_test)
  - `POST http://127.0.0.1:9016/api/v1/streams` (tc_test)
  - `PUT http://127.0.0.1:9016/api/v1/streams/http_test`
  - `grep -n 'bind() to 127.0.0.1:8022' /home/hex/astra-keepalive.log` (none)
  - `grep -n 'abort execution' /home/hex/astra-keepalive.log` (none)

### 2025-12-27
- Changes:
  - Run HTTP output port validation during force refresh to avoid aborts on busy ports.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra --log /home/hex/astra-server.log --no-stdout scripts/server.lua -p 9000 --data-dir /home/hex/astra-data --web-dir ./web &`
  - Not run: forced refresh via adapter save (would touch production data).

### 2025-12-27
- Changes:
  - Kill all ffmpeg processes when the API restart endpoint is invoked.
- Tests:
  - `./configure.sh`
  - `make`
  - Not run: `/api/v1/restart` (would terminate production ffmpeg processes on the server).

### 2025-12-27
- Changes:
  - Validate stream configs during runtime apply to prevent aborts on busy HTTP output ports.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra --debug --log /home/hex/astra-logs/stream-save-debug-20251227.log scripts/server.lua -p 9015 --data-dir /home/hex/astra-data --web-dir ./web &`
  - `curl -I http://127.0.0.1:9015/index.html`
  - `grep -n \"invalid stream config\" /home/hex/astra-logs/stream-save-debug-20251227.log`

### 2025-12-27
- Changes:
  - Updated the transcode smoke generator to use libx264/aac with zerolatency GOP for stable DTS.
  - Added `ffmpeg_global_args` (`+genpts`) to the transcode CPU fixture for cleaner smoke runs.
- Tests:
  - `./configure.sh`
  - `make`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=1000 -c:v libx264 -preset veryfast -tune zerolatency -g 50 -keyint_min 50 -sc_threshold 0 -c:a aac -b:a 128k -f mpegts udp://127.0.0.1:12100?pkt_size=1316`
  - `./astra ./fixtures/transcode_cpu.json -p 9005 --data-dir ./data_transcode --web-dir ./web &`
  - `POST http://127.0.0.1:9005/api/v1/auth/login`
  - `GET http://127.0.0.1:9005/api/v1/transcode-status/transcode_cpu_test`
  - `GET http://127.0.0.1:9005/api/v1/alerts?limit=5&stream_id=transcode_cpu_test`
  - `./astra scripts/server.lua -p 9012 --data-dir ./data_ui_9012 --web-dir ./web &`
  - Headless UI save flow via puppeteer-core (login + create stream + save; screenshots under `/home/hex/ui_screens/20251227_154524`)

### 2025-12-27
- Changes:
  - Added `utils.can_bind` to preflight HTTP output ports and avoid aborts on port conflicts.
  - Added stream config validation in the API (input/output format, transcode outputs, HTTP port availability) with clear errors.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9010 --data-dir ./data_smoke_9010 --web-dir ./web &`
  - `curl -I http://127.0.0.1:9010/index.html`
  - `curl -s http://127.0.0.1:9010/app.js | head -n 1`
  - `POST http://127.0.0.1:9010/api/v1/auth/login`
  - `GET http://127.0.0.1:9010/api/v1/streams`
  - `GET http://127.0.0.1:9010/api/v1/settings`
  - `PUT http://127.0.0.1:9010/api/v1/settings` (hls_duration=7)
  - `GET http://127.0.0.1:9010/api/v1/metrics`
  - `GET http://127.0.0.1:9010/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9010/api/v1/health/process`
  - `GET http://127.0.0.1:9010/api/v1/health/inputs`
  - `GET http://127.0.0.1:9010/api/v1/health/outputs`
  - `GET http://127.0.0.1:9010/api/v1/export?include_users=0`
  - `POST http://127.0.0.1:9010/api/v1/streams` (port conflict -> 400)
  - `POST http://127.0.0.1:9010/api/v1/streams` (stream_ok -> 200)

### 2025-12-27
- Changes:
  - Added a STARTING pre-probe banner for transcode status and a UDP probe restart toggle in the UI.
  - Added optional UDP probe-and-restart scheduling in transcode runtime.
  - Documented the new UDP probe restart behavior.
- Tests:
  - `./configure.sh`
  - `make`
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `POST http://127.0.0.1:9000/api/v1/auth/login`
  - `GET http://127.0.0.1:9000/api/v1/streams`
  - `GET http://127.0.0.1:9000/api/v1/settings`
  - `GET http://127.0.0.1:9000/api/v1/metrics`
  - `GET http://127.0.0.1:9000/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9000/api/v1/health/process`
  - `GET http://127.0.0.1:9000/api/v1/health/inputs`
  - `GET http://127.0.0.1:9000/api/v1/health/outputs`
  - `GET http://127.0.0.1:9000/api/v1/export?include_users=0`
  - `ffmpeg -re -f lavfi -i testsrc=size=640x360:rate=25 -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts udp://127.0.0.1:12120?pkt_size=1316&localport=12122`
  - `./astra ./tmp_transcode_udp_restart.json -p 9025 --data-dir ./data_transcode_udp_restart2 --web-dir ./web &`
  - `POST http://127.0.0.1:9025/api/v1/auth/login`
  - `GET http://127.0.0.1:9025/api/v1/transcode-status/transcode_udp_restart` (input_bitrate_kbps set, restarts_10min=1)

### 2025-12-27
- Changes:
  - Added libx264 repeat-headers toggle in transcode output modal and updated CPU presets.
  - Added UDP input bitrate pre-probe for transcode streams (runs before start, skips UDP probing while running).
  - Documented the UDP probe pre-start behavior and updated the UI hint text.
- Tests:
  - `./configure.sh`
  - `make`
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `POST http://127.0.0.1:9000/api/v1/auth/login`
  - `GET http://127.0.0.1:9000/api/v1/streams`
  - `GET http://127.0.0.1:9000/api/v1/settings`
  - `GET http://127.0.0.1:9000/api/v1/metrics`
  - `GET http://127.0.0.1:9000/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9000/api/v1/health/process`
  - `GET http://127.0.0.1:9000/api/v1/health/inputs`
  - `GET http://127.0.0.1:9000/api/v1/health/outputs`
  - `GET http://127.0.0.1:9000/api/v1/export?include_users=0`
  - `ffmpeg -re -f lavfi -i testsrc=size=640x360:rate=25 -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts udp://127.0.0.1:12112?pkt_size=1316&localport=12114`
  - `./astra ./tmp_transcode_udp.json -p 9023 --data-dir ./data_transcode_udp4 --web-dir ./web &`
  - `POST http://127.0.0.1:9023/api/v1/auth/login`
  - `GET http://127.0.0.1:9023/api/v1/transcode-status/transcode_udp_test` (input_bitrate_kbps)

### 2025-12-27
- Changes:
  - Added transcode input/output bitrate probing and exposed probe status fields in API.
  - Showed transcode in/out bitrate in tiles/analyze and expanded transcode error messaging.
  - Documented input presets and extended transcode smoke test coverage for bitrate fields.
- Tests:
  - `./configure.sh`
  - `make`
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `POST http://127.0.0.1:9000/api/v1/auth/login`
  - `GET http://127.0.0.1:9000/api/v1/streams`
  - `GET http://127.0.0.1:9000/api/v1/settings`
  - `GET http://127.0.0.1:9000/api/v1/metrics`
  - `GET http://127.0.0.1:9000/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9000/api/v1/health/process`
  - `GET http://127.0.0.1:9000/api/v1/health/inputs`
  - `GET http://127.0.0.1:9000/api/v1/health/outputs`
  - `GET http://127.0.0.1:9000/api/v1/export?include_users=0`
  - `./astra scripts/server.lua -p 9047 --data-dir ./data_buffer_9047 --web-dir ./web &`
  - `POST http://127.0.0.1:9047/api/v1/buffers/resources`
  - `GET http://127.0.0.1:9047/api/v1/buffers/resources`
  - `POST http://127.0.0.1:9047/api/v1/buffers/resources/buffer_test/inputs`
  - `ffmpeg -re -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts udp://127.0.0.1:12100?pkt_size=1316`
  - `./astra ./fixtures/transcode_cpu.json -p 9005 --data-dir ./data_transcode --web-dir ./web &`
  - `GET http://127.0.0.1:9005/api/v1/transcode-status/transcode_cpu_test` (state/out_time_ms/output_bitrate_kbps)
  - `GET http://127.0.0.1:9005/api/v1/alerts?limit=5&stream_id=transcode_cpu_test` (TRANSCODE_STALL)
  - `./astra ./tmp_transcode_http.json -p 9013 --data-dir ./data_transcode_http --web-dir ./web &`
  - `GET http://127.0.0.1:9013/api/v1/transcode-status/transcode_http_test` (state/input_bitrate_kbps/output_bitrate_kbps)
  - `ffmpeg -i udp://127.0.0.1:12112?pkt_size=1316 -t 2 -f null -`

### 2025-12-27
- Changes:
  - Added UI presets for HLSSplitter instances, stream outputs, and transcode profiles.
  - Added transcode status error note and clearer stream validation messages.
  - Added form subsection styling for preset blocks.
  - Added transcode log-to-main toggle and preset auto-fill for output URLs.
  - Added ffmpeg stderr mirroring into Astra log when enabled.
- Tests:
  - `./configure.sh`
  - `make`
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `./astra /home/hex/astra/tmp_transcode_test.json -p 9012 --data-dir /home/hex/astra-data-transcode-test --web-dir /home/hex/astra/web` (transcode source check)
  - `POST http://127.0.0.1:9012/api/v1/auth/login`
  - `GET http://127.0.0.1:9012/api/v1/stream-status/transcode_cpu_test`
  - `GET http://127.0.0.1:9012/api/v1/transcode-status/transcode_cpu_test`

### 2025-12-27
- Changes:
  - Added HLSSplitter form error display, dirty-state guard, and disabled actions/links/allow until saved.
  - Added transcode output modal validation with inline error messaging.
  - Recorded Phase 28 progress in `plan.md`.
- Tests:
  - `./configure.sh`
  - `make`
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`

### 2025-12-27
- Changes:
  - Added Phase 27 plan steps for server buffer 404 fix and restarted port 9000 server to load updated scripts.
  - Rebuilt Linux `./astra` binary on the server after rsync replaced it with a macOS build.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua --data-dir /home/hex/astra-data -p 9000 --web-dir /home/hex/astra/web &` (restart)
  - Manual UI check: pending (needs browser)

### 2025-12-27
- Changes:
  - Added Buffer UI presets (live+backup, multi-input, low latency) and preset apply workflow.
  - Documented buffer presets and clarified global vs per-resource settings.
  - Recorded Phase 26 progress in `plan.md`.
- Tests:
  - `./configure.sh`
  - `make`
  - `ffmpeg -y -f lavfi -i testsrc=size=160x90:rate=25 -f lavfi -i sine=frequency=1000 -t 6 -c:v mpeg2video -c:a mp2 -f mpegts ./tmp_buffer.ts`
  - `python3 -m http.server 18080 --directory .`
  - `./astra scripts/server.lua -p 9047 --data-dir ./data_buffer_9047 --web-dir ./web &`
  - `POST http://127.0.0.1:9047/api/v1/auth/login`
  - `PUT http://127.0.0.1:9047/api/v1/settings` (buffer enable, port 8090)
  - `POST http://127.0.0.1:9047/api/v1/buffers/resources`
  - `POST http://127.0.0.1:9047/api/v1/buffers/resources/buffer_test/inputs` (static HTTP file)
  - `POST http://127.0.0.1:9047/api/v1/buffers/reload`
  - `GET http://127.0.0.1:8090/play/test` (sync_ok True)
  - `GET http://127.0.0.1:9047/api/v1/buffer-status/buffer_test` (bytes_in > 0)
  - Note: static HTTP file source may log `RESOURCE_DOWN` after EOF.
  - Manual UI check: not run (no GUI access in CLI)

### 2025-12-26
- Changes:
  - Fixed Buffer UI draft/polling behavior, auto-id on save, and gated inputs/allow actions until saved.
  - Returned full buffer objects from API POST/PUT and added debug logs for buffer payloads.
  - Added quick buffer API curl smoke steps to `astra/AGENT.md`.
  - Show HTTP status codes in UI error messages.
  - Recorded Phase 25 progress in `plan.md`.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9047 --data-dir ./data_buffer_9047 --web-dir ./web &`
  - `POST http://127.0.0.1:9047/api/v1/auth/login`
  - `PUT http://127.0.0.1:9047/api/v1/settings` (buffer enable)
  - `POST http://127.0.0.1:9047/api/v1/buffers/resources`
  - `GET http://127.0.0.1:9047/api/v1/buffers/resources`
  - `POST http://127.0.0.1:9047/api/v1/buffers/resources/buffer_test/inputs`
  - `POST http://127.0.0.1:9047/api/v1/buffers/reload`
  - `GET http://127.0.0.1:9047/api/v1/buffer-status/buffer_test` (smart checkpoint + failover)
  - `PUT http://127.0.0.1:9047/api/v1/buffers/resources/buffer_test` (idr_parse)
  - `GET http://127.0.0.1:8090/play/test` (sync_ok True)

### 2025-12-26
- Changes:
  - Added config/UI/schema diff mapping for `astra-250612` vs astra-4 fork.
  - Added `astra/re/tools/extract_config_ui_map.py` and generated `astra/re/astra-250612-diff-config-ui.json`.
  - Extended `astra/re/astra-250612-diff-modules.md` with config/runtime + UI/JSON mapping notes.
  - Recorded Phase 24 completion in `plan.md`.
- Tests:
  - Not run (analysis only).

### 2025-12-26
- Changes:
  - Added module/option diff report and raw JSON mapping for `astra-250612` vs astra-4 fork.
  - Recorded Phase 23 module/option diff completion in `plan.md`.
- Tests:
  - Not run (analysis only).

### 2025-12-26
- Changes:
  - Added HTTP API spec and module deep dive notes for `astra-250612`.
  - Added clean-room Lua/C skeleton stubs under `astra/re/cleanroom`.
  - Recorded Phase 22 completion in `plan.md`.
- Tests:
  - Server observation: `./astra scripts/server.lua -p 9131 --data-dir ./data_re_9131 --web-dir ./web` + API queries via Bearer token (astra-250612 aborts without sqlite).

### 2025-12-26
- Changes:
  - Added clean-room compatibility spec for `astra-250612` in `astra/re/astra-250612-cleanroom-spec.md`.
  - Recorded Phase 21 clean-room spec completion in `plan.md`.
- Tests:
  - Not run (analysis only).

### 2025-12-26
- Changes:
  - Added `astra/re/astra-250612-report.md` with static analysis notes on libraries, modules, and function anchors.
  - Recorded Phase 20 reverse-engineering report completion in `plan.md`.
- Tests:
  - Not run (analysis only).

### 2025-12-26
- Changes:
  - Added Phase 19 map triage to `plan.md` and summarized key string xrefs/call-graph slices.
- Tests:
  - Not run (analysis only).

### 2025-12-26
- Changes:
  - Extended `ExportMaps.java` to emit function xrefs, call graph edges, and keyword string xrefs.
  - Regenerated Ghidra headless outputs (`call_graph.tsv`, `func_xref.tsv`, `key_xref.tsv`).
  - Recorded Phase 18 Ghidra extended export in `plan.md`.
- Tests:
  - `/opt/homebrew/opt/ghidra/libexec/support/analyzeHeadless astra/re/ghidra/project Astra250612 -import astra/astra-250612 -scriptPath astra/re/ghidra -postScript ExportMaps.java astra/re/ghidra/output -deleteProject`

### 2025-12-26
- Changes:
  - Added Ghidra headless export script and output maps under `astra/re/ghidra`.
  - Recorded the Ghidra headless export phase in `plan.md`.
- Tests:
  - `/opt/homebrew/opt/ghidra/libexec/support/analyzeHeadless astra/re/ghidra/project Astra250612 -import astra/astra-250612 -scriptPath astra/re/ghidra -postScript ExportMaps.java astra/re/ghidra/output -deleteProject`

### 2025-12-26
- Changes:
  - Added Phase 16 reverse-engineering deep dive to `plan.md` and marked it complete after rizin analysis.
  - Documented tool choice (rizin fallback) and progress in the plan.
- Tests:
  - Not run (analysis only).

### 2025-12-26
- Changes:
  - Added a plan phase to capture reverse-engineering notes for `astra-250612` (metadata, libraries, modules, CLI/systemd hints).
- Tests:
  - Not run (analysis only).

### 2025-12-26
- Changes:
  - Added HLSSplitter config preview endpoint and UI modal for generated XML.
  - Exposed splitter uptime/restart counters in list cards and detail panel.
  - Documented the config endpoint in READMEs and smoke steps.
  - Marked Phase 13 HLSSplitter enhancements as complete in plan.
- Tests:
  - `./configure.sh`
  - `make`
  - `ffmpeg -loglevel error -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=1000 -t 5 -c:v mpeg2video -c:a mp2 -f mpegts ./tmp_splitter.ts`
  - `python3 -m http.server 18080 --directory .`
  - `./astra scripts/server.lua -p 9041 --data-dir ./data_splitter_9041 --web-dir ./web &`
  - `POST http://127.0.0.1:9041/api/v1/auth/login`
  - `POST http://127.0.0.1:9041/api/v1/splitters`
  - `POST http://127.0.0.1:9041/api/v1/splitters/splitter_demo/allow`
  - `POST http://127.0.0.1:9041/api/v1/splitters/splitter_demo/links`
  - `POST http://127.0.0.1:9041/api/v1/splitters/splitter_demo/start`
  - `GET http://127.0.0.1:9041/api/v1/splitter-status/splitter_demo`
  - `GET http://127.0.0.1:9041/api/v1/splitters/splitter_demo/config`
  - `python3 (TS sync check on http://127.0.0.1:8089/tmp_splitter.ts)`
  - `POST http://127.0.0.1:9041/api/v1/splitters/splitter_demo/stop`

### 2025-12-26
- Changes:
  - Added HLSSplitter instances/links/allow to config import/export (API + CLI).
  - Refreshed splitters after API import and surfaced splitter counts in import summaries.
  - Extended default config/linting and docs for splitter export controls.
- Tests:
  - Not run (requires server smoke tests).

### 2025-12-26
- Changes:
  - Validated splitter allowRange rules in API/UI and added CIDR support to generated splitter XML.
  - Added splitter card health summary (OK/DOWN counts).
  - Reduced build warnings (fallthrough annotations, duff device, type-limits, dlsym pedantic, setjmp clobber) and documented clock-skew fix.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9060 --data-dir ./data_smoke_9060 --web-dir ./web > ./server_9060.log 2>&1 &`
  - `curl -I http://127.0.0.1:9060/index.html`
  - `curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:9060/app.js`
  - `POST http://127.0.0.1:9060/api/v1/auth/login`
  - `GET http://127.0.0.1:9060/api/v1/streams`
  - `GET http://127.0.0.1:9060/api/v1/settings`
  - `GET http://127.0.0.1:9060/api/v1/metrics`
  - `GET http://127.0.0.1:9060/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9060/api/v1/health/process`
  - `GET http://127.0.0.1:9060/api/v1/health/inputs`
  - `GET http://127.0.0.1:9060/api/v1/health/outputs`
  - `GET http://127.0.0.1:9060/api/v1/export?include_users=0`
  - `./astra scripts/export.lua --data-dir ./data_smoke_9060 --output ./astra-export.json`
  - `ffmpeg -nostdin -loglevel error -y -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=1000 -t 5 -c:v mpeg2video -c:a mp2 -f mpegts ./tmp_splitter.ts`
  - `python3 -m http.server 18080 --directory .`
  - `./astra scripts/server.lua -p 9043 --data-dir ./data_splitter_9043 --web-dir ./web &`
  - `POST http://127.0.0.1:9043/api/v1/auth/login`
  - `POST http://127.0.0.1:9043/api/v1/splitters`
  - `POST http://127.0.0.1:9043/api/v1/splitters/splitter_demo/allow (allowRange 127.0.0.1/32)`
  - `POST http://127.0.0.1:9043/api/v1/splitters/splitter_demo/links`
  - `POST http://127.0.0.1:9043/api/v1/splitters/splitter_demo/start`
  - `python3 (TS sync check on http://127.0.0.1:8093/tmp_splitter.ts)`
  - `POST http://127.0.0.1:9043/api/v1/splitters/splitter_demo/stop`

### 2025-12-26
- Changes:
  - Removed the redundant http_buffer typedef and silenced unused module_call parameter.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9056 --data-dir ./data_smoke_9056 --web-dir ./web > ./server_9056.log 2>&1 &`
  - `curl -I http://127.0.0.1:9056/index.html`
  - `curl -s http://127.0.0.1:9056/app.js | head -n 1`
  - `POST http://127.0.0.1:9056/api/v1/auth/login`
  - `GET http://127.0.0.1:9056/api/v1/streams`
  - `GET http://127.0.0.1:9056/api/v1/settings`
  - `GET http://127.0.0.1:9056/api/v1/metrics`
  - `GET http://127.0.0.1:9056/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9056/api/v1/health/process`
  - `GET http://127.0.0.1:9056/api/v1/health/inputs`
  - `GET http://127.0.0.1:9056/api/v1/health/outputs`
  - `GET http://127.0.0.1:9056/api/v1/export?include_users=0`
  - `./astra scripts/export.lua --data-dir ./data_smoke_9056 --output ./astra-export.json`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=160x90:rate=25 -f lavfi -i sine=frequency=1000 -c:v libx264 -preset veryfast -tune zerolatency -g 50 -keyint_min 50 -sc_threshold 0 -c:a mp2 -f mpegts -listen 1 http://127.0.0.1:18080/primary.ts &`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=160x90:rate=25 -f lavfi -i sine=frequency=800 -c:v libx264 -preset veryfast -tune zerolatency -g 50 -keyint_min 50 -sc_threshold 0 -c:a mp2 -f mpegts -listen 1 http://127.0.0.1:18081/backup.ts &`
  - `./astra scripts/server.lua -p 9047 --data-dir ./data_buffer_9047 --web-dir ./web &`
  - `POST http://127.0.0.1:9047/api/v1/auth/login`
  - `PUT http://127.0.0.1:9047/api/v1/settings (buffer_enabled, buffer_listen_port)`
  - `POST http://127.0.0.1:9047/api/v1/buffers/resources`
  - `POST http://127.0.0.1:9047/api/v1/buffers/resources/buffer_test/inputs (primary + backup)`
  - `POST http://127.0.0.1:9047/api/v1/buffers/reload`
  - `python3 (TS sync check on http://127.0.0.1:8090/play/test)`
  - `GET http://127.0.0.1:9047/api/v1/buffer-status/buffer_test (smart_checkpoint)`
  - `GET http://127.0.0.1:9047/api/v1/buffer-status/buffer_test (active_input_index=1)`
  - `PUT http://127.0.0.1:9047/api/v1/buffers/resources/buffer_test (keyframe_detect_mode=idr_parse)`
  - `POST http://127.0.0.1:9047/api/v1/buffers/reload`

### 2025-12-26
- Changes:
  - Fixed buffer module availability detection and smart-start target selection for early buffers.
  - Added multi-packet IDR scan buffering to improve SPS/PPS/keyframe detection.
  - Updated Buffer smoke tests (H264 sources, retries, PUT payload, failover ordering).
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9056 --data-dir ./data_smoke_9056 --web-dir ./web > ./server_9056.log 2>&1 &`
  - `curl -I http://127.0.0.1:9056/index.html`
  - `curl -s http://127.0.0.1:9056/app.js | head -n 1`
  - `POST http://127.0.0.1:9056/api/v1/auth/login`
  - `GET http://127.0.0.1:9056/api/v1/streams`
  - `GET http://127.0.0.1:9056/api/v1/settings`
  - `GET http://127.0.0.1:9056/api/v1/metrics`
  - `GET http://127.0.0.1:9056/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9056/api/v1/health/process`
  - `GET http://127.0.0.1:9056/api/v1/health/inputs`
  - `GET http://127.0.0.1:9056/api/v1/health/outputs`
  - `GET http://127.0.0.1:9056/api/v1/export?include_users=0`
  - `./astra scripts/export.lua --data-dir ./data_smoke_9056 --output ./astra-export.json`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=160x90:rate=25 -f lavfi -i sine=frequency=1000 -c:v libx264 -preset veryfast -tune zerolatency -g 50 -keyint_min 50 -sc_threshold 0 -c:a mp2 -f mpegts -listen 1 http://127.0.0.1:18080/primary.ts &`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=160x90:rate=25 -f lavfi -i sine=frequency=800 -c:v libx264 -preset veryfast -tune zerolatency -g 50 -keyint_min 50 -sc_threshold 0 -c:a mp2 -f mpegts -listen 1 http://127.0.0.1:18081/backup.ts &`
  - `./astra scripts/server.lua -p 9047 --data-dir ./data_buffer_9047 --web-dir ./web &`
  - `POST http://127.0.0.1:9047/api/v1/auth/login`
  - `PUT http://127.0.0.1:9047/api/v1/settings (buffer_enabled, buffer_listen_port)`
  - `POST http://127.0.0.1:9047/api/v1/buffers/resources`
  - `POST http://127.0.0.1:9047/api/v1/buffers/resources/buffer_test/inputs (primary + backup)`
  - `POST http://127.0.0.1:9047/api/v1/buffers/reload`
  - `python3 (TS sync check on http://127.0.0.1:8090/play/test)`
  - `GET http://127.0.0.1:9047/api/v1/buffer-status/buffer_test (smart_checkpoint)`
  - `GET http://127.0.0.1:9047/api/v1/buffer-status/buffer_test (active_input_index=1)`
  - `PUT http://127.0.0.1:9047/api/v1/buffers/resources/buffer_test (keyframe_detect_mode=idr_parse)`
  - `POST http://127.0.0.1:9047/api/v1/buffers/reload`

### 2025-12-26
- Changes:
  - Reviewed HLSSplitter implementation and updated `plan.md` follow-ups.
  - Marked Buffer Mode phase as complete in `plan.md`.
- Tests:
  - Not run (plan update only).

### 2025-12-26
- Changes:
  - Marked HLSSplitter phase as complete and added follow-up functions to `plan.md`.
- Tests:
  - Not run (docs only).

### 2025-12-26
- Changes:
  - Added HLSSplitter managed service (SQLite tables, config XML generator, process supervisor, health probes).
  - Added splitter CRUD/status/process API endpoints.
  - Added HLSSplitter UI view with instance/link/allow editors and output URL tools.
  - Documented HLSSplitter usage and smoke steps.
- Tests:
  - Not run (pending server smoke)

### 2025-12-26
- Changes:
  - Fixed HLS token rewrite to preserve segment paths while appending token/session_id.
  - Always set auth cookies on HLS playlist responses and documented the behavior.
  - Replaced the unstable Lua auth backend fixture with a Python backend for smoke tests.
  - Tuned auth fixture HLS settings and updated token-auth smoke steps.
  - Added auth limits/unique fixtures and backend header controls for max sessions/unique.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9050 --data-dir ./data_smoke_9050 --web-dir ./web > ./server_9050.log 2>&1 &`
  - `curl -I http://127.0.0.1:9050/index.html`
  - `curl -s http://127.0.0.1:9050/app.js | head -n 1`
  - `POST http://127.0.0.1:9050/api/v1/auth/login`
  - `GET http://127.0.0.1:9050/api/v1/streams`
  - `GET http://127.0.0.1:9050/api/v1/settings`
  - `GET http://127.0.0.1:9050/api/v1/metrics`
  - `GET http://127.0.0.1:9050/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9050/api/v1/health/process`
  - `GET http://127.0.0.1:9050/api/v1/health/inputs`
  - `GET http://127.0.0.1:9050/api/v1/health/outputs`
  - `GET http://127.0.0.1:9050/api/v1/export?include_users=0`
  - `./astra scripts/export.lua --data-dir ./data_smoke_9050 --output ./export_smoke_9050.json`
  - `python3 ./fixtures/auth_backend.py &`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts "udp://127.0.0.1:13200?pkt_size=1316" &`
  - `./astra ./fixtures/auth_play.json -p 9032 --data-dir ./data_auth_9032 --web-dir ./web &`
  - `curl -s -o /dev/null -w "%{http_code}\\n" http://127.0.0.1:9032/playlist.m3u8 | grep 403`
  - `curl -s "http://127.0.0.1:9032/playlist.m3u8?token=token1" | grep "token=token1"`
  - `curl -s "http://127.0.0.1:9032/hls/auth_demo/index.m3u8?token=token1" | grep "token=token1"`
  - `curl -s -D - -o /dev/null "http://127.0.0.1:9032/hls/auth_demo/index.m3u8?token=token1" | grep -i "set-cookie: astra_token"`
  - `POST http://127.0.0.1:9032/api/v1/auth/login`
  - `GET http://127.0.0.1:9032/api/v1/sessions?type=auth`
  - `./astra ./fixtures/auth_limits.json -p 9033 --data-dir ./data_auth_limits_9033 --web-dir ./web &`
  - `curl -s "http://127.0.0.1:9033/playlist.m3u8?token=token1" | head -n 1`
  - `curl -s "http://127.0.0.1:9033/hls/auth_demo/index.m3u8?token=token1" | grep "token=token1"`
  - `curl -s -o /dev/null -w "%{http_code}\\n" "http://127.0.0.1:9033/playlist.m3u8?token=token2" | grep 403`
  - `./astra ./fixtures/auth_unique.json -p 9034 --data-dir ./data_auth_unique_9034 --web-dir ./web &`
  - `curl -s "http://127.0.0.1:9034/playlist.m3u8?token=token1" | head -n 1`
  - `curl -s "http://127.0.0.1:9034/playlist.m3u8?token=token2" | head -n 1`
  - `POST http://127.0.0.1:9034/api/v1/auth/login`
  - `GET http://127.0.0.1:9034/api/v1/sessions?type=auth` (deny/allow counts)

### 2025-12-25
- Changes:
  - Added SRT/RTSP bridge inputs and SRT output via ffmpeg subprocesses.
  - Enabled SRT/RTSP UI input editor and SRT output editor fields.
  - Documented SRT/RTSP bridge config and optional smoke steps.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9054 --data-dir ./data_srt_9054 --web-dir ./web > ./server_9054.log 2>&1 &`
  - `curl -I http://127.0.0.1:9054/index.html`
  - `curl -s http://127.0.0.1:9054/index.html | grep 'app.js'`
  - `curl -s http://127.0.0.1:9054/app.js | head -n 1`
  - `POST http://127.0.0.1:9054/api/v1/auth/login`
  - `GET http://127.0.0.1:9054/api/v1/streams`
  - `GET http://127.0.0.1:9054/api/v1/settings`
  - `GET http://127.0.0.1:9054/api/v1/metrics`
  - `GET http://127.0.0.1:9054/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9054/api/v1/health/process`
  - `GET http://127.0.0.1:9054/api/v1/health/inputs`
  - `GET http://127.0.0.1:9054/api/v1/health/outputs`
  - `GET http://127.0.0.1:9054/api/v1/export?include_users=0`
  - `./astra scripts/export.lua --data-dir ./data_srt_9054 --output ./export_srt_9054.json`

### 2025-12-25
- Changes:
  - Completed the release checklist after server smoke verification.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9053 --data-dir ./data_release_9053 --web-dir ./web > ./server_9053.log 2>&1 &`
  - `curl -I http://127.0.0.1:9053/index.html`
  - `curl -s http://127.0.0.1:9053/index.html | grep 'app.js'`
  - `curl -s http://127.0.0.1:9053/app.js | head -n 1`
  - `POST http://127.0.0.1:9053/api/v1/auth/login`
  - `GET http://127.0.0.1:9053/api/v1/streams`
  - `GET http://127.0.0.1:9053/api/v1/settings`
  - `GET http://127.0.0.1:9053/api/v1/metrics`
  - `GET http://127.0.0.1:9053/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9053/api/v1/health/process`
  - `GET http://127.0.0.1:9053/api/v1/health/inputs`
  - `GET http://127.0.0.1:9053/api/v1/health/outputs`
  - `GET http://127.0.0.1:9053/api/v1/export?include_users=0`
  - `./astra scripts/export.lua --data-dir ./data_release_9053 --output ./export_release_9053.json`

### 2025-12-25
- Changes:
  - Added fixture configs for input variants, output formats, and NVIDIA transcode examples.
  - Documented fixtures location in READMEs.
- Tests:
  - `PORT=9051 ./contrib/ci/smoke.sh`

### 2025-12-25
- Changes:
  - Hardened CI smoke runner checks for UI assets to avoid pipefail failures.
- Tests:
  - `PORT=9050 ./contrib/ci/smoke.sh`

### 2025-12-25
- Changes:
  - Added login rate limiting and configurable session TTL.
  - Enforced CSRF checks for cookie-based state changes (Bearer auth bypasses).
  - Documented new auth/session settings and CSRF requirements.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9048 --data-dir ./data_security_9048 --web-dir ./web > ./server_9048.log 2>&1 &`
  - `curl -I http://127.0.0.1:9048/index.html`
  - `curl -s http://127.0.0.1:9048/index.html | grep 'transcode-output-preset'`
  - `curl -s http://127.0.0.1:9048/app.js | head -n 1`
  - `POST http://127.0.0.1:9048/api/v1/auth/login`
  - `GET http://127.0.0.1:9048/api/v1/streams`
  - `GET http://127.0.0.1:9048/api/v1/settings`
  - `GET http://127.0.0.1:9048/api/v1/metrics` (grep `lua_mem_kb`)
  - `GET http://127.0.0.1:9048/api/v1/metrics?format=prometheus` (grep `astra_lua_mem_kb`)
  - `GET http://127.0.0.1:9048/api/v1/health/process`
  - `GET http://127.0.0.1:9048/api/v1/health/inputs`
  - `GET http://127.0.0.1:9048/api/v1/health/outputs`
  - `GET http://127.0.0.1:9048/api/v1/export?include_users=0`
  - `./astra scripts/export.lua --data-dir ./data_security_9048 --output ./export_security_9048.json`

### 2025-12-25
- Changes:
  - Added lightweight perf timings for refresh/status paths in `runtime`.
  - Exposed Lua memory and perf gauges in `/api/v1/metrics` (JSON + Prometheus).
  - Documented profiling fields in READMEs.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9047 --data-dir ./data_perf_9047 --web-dir ./web > ./server_9047.log 2>&1 &`
  - `curl -I http://127.0.0.1:9047/index.html`
  - `curl -s http://127.0.0.1:9047/index.html | grep 'transcode-output-preset'`
  - `curl -s http://127.0.0.1:9047/app.js | head -n 1`
  - `POST http://127.0.0.1:9047/api/v1/auth/login`
  - `GET http://127.0.0.1:9047/api/v1/streams`
  - `GET http://127.0.0.1:9047/api/v1/settings`
  - `GET http://127.0.0.1:9047/api/v1/metrics` (grep `lua_mem_kb`)
  - `GET http://127.0.0.1:9047/api/v1/metrics?format=prometheus` (grep `astra_lua_mem_kb`)
  - `GET http://127.0.0.1:9047/api/v1/health/process`
  - `GET http://127.0.0.1:9047/api/v1/health/inputs`
  - `GET http://127.0.0.1:9047/api/v1/health/outputs`
  - `GET http://127.0.0.1:9047/api/v1/export?include_users=0`
  - `./astra scripts/export.lua --data-dir ./data_perf_9047 --output ./export_perf_9047.json`

### 2025-12-25
- Changes:
  - Wrapped schema migrations in transactions with rollback on failure.
  - Added automatic DB backups (`astra.db.bak.<timestamp>`) before new migrations.
  - Documented migration safety behavior in READMEs.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9046 --data-dir ./data_migrate_9046 --web-dir ./web > ./server_9046.log 2>&1 &`
  - `curl -I http://127.0.0.1:9046/index.html`
  - `curl -s http://127.0.0.1:9046/index.html | grep 'transcode-output-preset'`
  - `curl -s http://127.0.0.1:9046/app.js | head -n 1`
  - `POST http://127.0.0.1:9046/api/v1/auth/login`
  - `GET http://127.0.0.1:9046/api/v1/streams`
  - `GET http://127.0.0.1:9046/api/v1/settings`
  - `GET http://127.0.0.1:9046/api/v1/metrics`
  - `GET http://127.0.0.1:9046/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9046/api/v1/health/process`
  - `GET http://127.0.0.1:9046/api/v1/health/inputs`
  - `GET http://127.0.0.1:9046/api/v1/health/outputs`
  - `GET http://127.0.0.1:9046/api/v1/export?include_users=0`
  - `./astra scripts/export.lua --data-dir ./data_migrate_9046 --output ./export_migrate_9046.json`

### 2025-12-25
- Changes:
  - Added config linting and schema checks (`scripts/lint.lua`) for JSON/Lua configs.
  - Exposed payload read/validate/lint helpers in `scripts/config.lua`.
  - Documented lint usage in READMEs.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/lint.lua --config ./fixtures/ada2-10815.json`
  - `./astra scripts/lint.lua --config ./fixtures/sample.lua`
  - `./astra scripts/server.lua -p 9045 --data-dir ./data_lint_9045 --web-dir ./web > ./server_9045.log 2>&1 &`
  - `curl -I http://127.0.0.1:9045/index.html`
  - `curl -s http://127.0.0.1:9045/index.html | grep 'transcode-output-preset'`
  - `curl -s http://127.0.0.1:9045/app.js | head -n 1`
  - `POST http://127.0.0.1:9045/api/v1/auth/login`
  - `GET http://127.0.0.1:9045/api/v1/streams`
  - `GET http://127.0.0.1:9045/api/v1/settings`
  - `GET http://127.0.0.1:9045/api/v1/metrics`
  - `GET http://127.0.0.1:9045/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9045/api/v1/health/process`
  - `GET http://127.0.0.1:9045/api/v1/health/inputs`
  - `GET http://127.0.0.1:9045/api/v1/health/outputs`
  - `GET http://127.0.0.1:9045/api/v1/export?include_users=0`
  - `./astra scripts/export.lua --data-dir ./data_lint_9045 --output ./export_lint_9045.json`

### 2025-12-25
- Changes:
  - Added NVIDIA device validation for transcode jobs (blocks when GPU nodes are missing).
  - Warn on unknown transcode engine values and normalize to CPU.
  - Documented GPU validation behavior in `astra/README.md`.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9044 --data-dir ./data_gpu_9044 --web-dir ./web > ./server_9044.log 2>&1 &`
  - `curl -I http://127.0.0.1:9044/index.html`
  - `curl -s http://127.0.0.1:9044/index.html | grep 'transcode-output-preset'`
  - `curl -s http://127.0.0.1:9044/app.js | head -n 1`
  - `POST http://127.0.0.1:9044/api/v1/auth/login`
  - `GET http://127.0.0.1:9044/api/v1/streams`
  - `GET http://127.0.0.1:9044/api/v1/settings`
  - `GET http://127.0.0.1:9044/api/v1/metrics`
  - `GET http://127.0.0.1:9044/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9044/api/v1/health/process`
  - `GET http://127.0.0.1:9044/api/v1/health/inputs`
  - `GET http://127.0.0.1:9044/api/v1/health/outputs`
  - `GET http://127.0.0.1:9044/api/v1/export?include_users=0`
  - `./astra scripts/export.lua --data-dir ./data_gpu_9044 --output ./export_gpu_9044.json`

### 2025-12-25
- Changes:
  - Added transcode output presets (CPU/NVIDIA 1080p/720p/540p) in the UI modal.
  - Ensured `scripts/export.lua` exits after writing output.
  - Documented transcode preset usage in `astra/README.md`.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9042 --data-dir ./data_presets_9042 --web-dir ./web > ./server_9042.log 2>&1 &`
  - `curl -I http://127.0.0.1:9042/index.html`
  - `curl -s http://127.0.0.1:9042/index.html | grep 'transcode-output-preset'`
  - `curl -s http://127.0.0.1:9042/app.js | head -n 1`
  - `POST http://127.0.0.1:9042/api/v1/auth/login`
  - `GET http://127.0.0.1:9042/api/v1/streams`
  - `GET http://127.0.0.1:9042/api/v1/settings`
  - `GET http://127.0.0.1:9042/api/v1/metrics`
  - `GET http://127.0.0.1:9042/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9042/api/v1/health/process`
  - `GET http://127.0.0.1:9042/api/v1/health/inputs`
  - `GET http://127.0.0.1:9042/api/v1/health/outputs`
  - `GET http://127.0.0.1:9042/api/v1/export?include_users=0`
  - `./astra scripts/export.lua --data-dir ./data_presets_9042 --output ./export_presets_9042.json`

### 2025-12-25
- Changes:
  - Added in-memory log retention/rotation by time and max entries for UI logs.
  - Apply log retention settings at startup and on `/api/v1/settings` updates.
  - Documented log retention settings in README docs.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9040 --data-dir ./data_logs_9040 --web-dir ./web &`
  - `curl -I http://127.0.0.1:9040/index.html`
  - `curl -s http://127.0.0.1:9040/app.js | head -n 1`
  - `POST http://127.0.0.1:9040/api/v1/auth/login`
  - `GET http://127.0.0.1:9040/api/v1/streams`
  - `GET http://127.0.0.1:9040/api/v1/settings`
  - `GET http://127.0.0.1:9040/api/v1/metrics`
  - `GET http://127.0.0.1:9040/api/v1/metrics?format=prometheus`
  - `GET http://127.0.0.1:9040/api/v1/health/process`
  - `GET http://127.0.0.1:9040/api/v1/health/inputs`
  - `GET http://127.0.0.1:9040/api/v1/health/outputs`
  - `GET http://127.0.0.1:9040/api/v1/export?include_users=0`
  - `./astra scripts/export.lua --data-dir ./data_logs_9040 --output ./export_logs_9040.json`

### 2025-12-25
- Changes:
  - Added config export tooling: `/api/v1/export` and `scripts/export.lua`.
  - Added config export support for hashed users and options to omit sections.
  - Documented export usage in READMEs and smoke steps.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9036 --data-dir ./data_export_9036 --web-dir ./web &`
  - `POST http://127.0.0.1:9036/api/v1/auth/login`
  - `GET http://127.0.0.1:9036/api/v1/export?include_users=0`
  - `./astra scripts/export.lua --data-dir ./data_export_9036 --output ./export_9036.json`

### 2025-12-25
- Changes:
  - Added systemd unit and environment templates under `contrib/systemd/`.
  - Documented systemd setup in README docs.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9035 --data-dir ./data_systemd_9035 --web-dir ./web &`
  - `curl -I http://127.0.0.1:9035/index.html`
  - `POST http://127.0.0.1:9035/api/v1/auth/login`
  - `GET http://127.0.0.1:9035/api/v1/streams`
  - `GET http://127.0.0.1:9035/api/v1/settings`

### 2025-12-25
- Changes:
  - Added health endpoints for process, inputs, and outputs.
  - Documented health endpoints in READMEs and smoke steps.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9034 --data-dir ./data_health_9034 --web-dir ./web &`
  - `POST http://127.0.0.1:9034/api/v1/auth/login`
  - `GET http://127.0.0.1:9034/api/v1/health/process`
  - `GET http://127.0.0.1:9034/api/v1/health/inputs`
  - `GET http://127.0.0.1:9034/api/v1/health/outputs`

### 2025-12-25
- Changes:
  - Added `/api/v1/metrics` for summary counters (streams/adapters/sessions).
  - Added Prometheus-format export via `?format=prometheus`.
  - Added DB count helpers for streams/adapters/sessions.
  - Documented metrics endpoint in READMEs and smoke steps.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9033 --data-dir ./data_metrics_9033 --web-dir ./web &`
  - `POST http://127.0.0.1:9033/api/v1/auth/login`
  - `GET http://127.0.0.1:9033/api/v1/metrics`
  - `GET http://127.0.0.1:9033/api/v1/metrics?format=prometheus`

### 2025-12-25
- Changes:
  - Enforced password policy on user create/reset.
  - Added auth audit log storage + `/api/v1/audit` endpoint.
  - Added smoke steps for password policy + audit log.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra ./tmp_password_policy.json -p 9031 --data-dir ./data_policy_9031 --web-dir ./web &`
  - `curl -I http://127.0.0.1:9031/index.html`
  - `curl -s http://127.0.0.1:9031/app.js | head -n 1`
  - `POST http://127.0.0.1:9031/api/v1/auth/login`
  - `POST http://127.0.0.1:9031/api/v1/users (weak_user, short password -> reject)`
  - `POST http://127.0.0.1:9031/api/v1/users (strong_user, Strong123 -> ok)`
  - `GET http://127.0.0.1:9031/api/v1/audit`

### 2025-12-25
- Changes:
  - Added a lightweight release checklist to `plan.md`.
  - Documented HTTP Play HTTPS behavior via reverse proxy headers.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9030 --data-dir ./data_smoke_9030 --web-dir ./web &`
  - `curl -I http://127.0.0.1:9030/index.html`
  - `curl -s http://127.0.0.1:9030/app.js | head -n 1`
  - `POST http://127.0.0.1:9030/api/v1/auth/login`
  - `GET http://127.0.0.1:9030/api/v1/streams`
  - `GET http://127.0.0.1:9030/api/v1/settings`

### 2025-12-25
- Changes:
  - Added HTTP auth gating for HTTP Play, HLS routes, and HTTP output streams.
  - Added HTTP auth settings UI (enable/users/allow/deny/tokens/realm).
  - Documented HTTP auth smoke steps in `astra/AGENT.md`.
- Tests:
  - `./configure.sh`
  - `make`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts "udp://127.0.0.1:13100?pkt_size=1316" &`
  - `./astra ./tmp_http_auth.json -p 9028 --data-dir ./data_http_auth_9028 --web-dir ./web &`
  - `curl -I http://127.0.0.1:9028/playlist_auth.m3u8`
  - `curl -I "http://127.0.0.1:9028/playlist_auth.m3u8?token=token123"`
  - `curl -I -u admin:admin http://127.0.0.1:9028/playlist_auth.m3u8`

### 2025-12-25
- Changes:
  - Added user management API (`/api/v1/users`) with create/update/reset support.
  - Added users table fields (enabled/comment/created/last login) and login tracking.
  - Implemented Users UI with create/edit/disable/reset password flow.
  - Added user management smoke steps to `astra/AGENT.md`.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9027 --data-dir ./data_users_9027 --web-dir ./web &`
  - `curl -I http://127.0.0.1:9027/index.html`
  - `POST http://127.0.0.1:9027/api/v1/auth/login`
  - `GET http://127.0.0.1:9027/api/v1/users`
  - `POST http://127.0.0.1:9027/api/v1/users (demo_user)`
  - `PUT http://127.0.0.1:9027/api/v1/users/demo_user (disable)`
  - `POST http://127.0.0.1:9027/api/v1/users/demo_user/reset`

### 2025-12-25
- Changes:
  - Aligned HLS UI defaults (duration/quantity/naming) with runtime behavior.
  - Updated HLS static header defaults to match stream HLS defaults.
  - Added HLS/HTTP Play smoke test instructions to `astra/AGENT.md`.
- Tests:
  - `./configure.sh`
  - `make`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts "udp://127.0.0.1:13000?pkt_size=1316" &`
  - `./astra ./tmp_hls_http_play.json -p 9026 --data-dir ./data_hls_9026 --web-dir ./web &`
  - `curl -I http://127.0.0.1:9026/playlist_test.m3u8`
  - `curl -s http://127.0.0.1:9026/playlist_test.m3u8 | head -n 5`
  - `curl -I http://127.0.0.1:9026/hls/hls_demo/index.m3u8 | grep -i 'cache-control: no-cache'`
  - `segment=$(curl -s http://127.0.0.1:9026/hls/hls_demo/index.m3u8 | grep -v '^#' | head -n 1)`
  - `curl -I "http://127.0.0.1:9026${segment}" | grep -i 'cache-control: public, max-age=6'`

### 2025-12-25
- Changes:
  - Added access log buffer/API (`/api/v1/access-log`) and UI Access view.
  - Logged HTTP/HLS client connect/disconnect/timeout events for access log.
  - Added `stream_id` filter support for `/api/v1/logs` and UI input.
  - Added root `AGENT.md` + `SKILL.md` instructions aligned with plan workflow.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9025 --data-dir ./data_access_9025 --web-dir ./web &`
  - `curl -I http://127.0.0.1:9025/index.html`
  - `curl -s http://127.0.0.1:9025/index.html | grep 'view-access'`
  - `curl -s http://127.0.0.1:9025/index.html | grep 'log-stream-filter'`
  - `POST http://127.0.0.1:9025/api/v1/auth/login`
  - `GET http://127.0.0.1:9025/api/v1/logs?since=0&limit=5&stream_id=server`
  - `GET http://127.0.0.1:9025/api/v1/access-log?since=0&limit=5`

### 2025-12-25
- Changes:
  - Added server-side `/api/v1/sessions` filters (stream/login/ip/text) with optional pagination.
  - Wired Sessions UI to query the server with filter text and limit control.
  - Documented session query parameters in README docs.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9024 --data-dir ./data_sessions_9024 --web-dir ./web &`
  - `curl -I http://127.0.0.1:9024/index.html`
  - `curl -s http://127.0.0.1:9024/index.html | grep 'session-limit'`
  - `curl -s http://127.0.0.1:9024/app.js | grep 'buildSessionQuery'`
  - `POST http://127.0.0.1:9024/api/v1/auth/login`
  - `GET http://127.0.0.1:9024/api/v1/sessions?limit=1&text=admin`

### 2025-12-25
- Changes:
  - Added server-side `/api/v1/logs` filters (`level`, `text`) and wired UI queries.
  - Added Sessions view search + group by stream controls.
  - Added compact bitrate label in Analyze input header.
  - Added top-level `plan.md` with a tracked roadmap.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9023 --data-dir ./data_ui_phase6_9023 --web-dir ./web &`
  - `curl -I http://127.0.0.1:9023/index.html`
  - `curl -s http://127.0.0.1:9023/index.html | grep 'session-filter'`
  - `curl -s http://127.0.0.1:9023/index.html | grep 'session-group'`
  - `curl -s http://127.0.0.1:9023/index.html | grep 'log-level-filter'`
  - `curl -s http://127.0.0.1:9023/index.html | grep 'log-text-filter'`
  - `curl -s http://127.0.0.1:9023/app.js | grep 'logLevelFilter'`
  - `curl -s http://127.0.0.1:9023/app.js | grep 'buildLogQuery'`
  - `curl -s http://127.0.0.1:9023/app.js | grep 'input-bitrate'`
  - `POST http://127.0.0.1:9023/api/v1/auth/login`
  - `GET http://127.0.0.1:9023/api/v1/logs?since=0&limit=5&level=info&text=server`

### 2025-12-25
- Changes:
  - Added per-input failover details on stream tiles (state badges, bitrate, copy URL).
  - Added log level/text filters in the Logs view.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9022 --data-dir ./data_ui_phase6_9022 --web-dir ./web &`
  - `curl -I http://127.0.0.1:9022/index.html`
  - `curl -s http://127.0.0.1:9022/index.html | grep 'session-filter'`
  - `curl -s http://127.0.0.1:9022/index.html | grep 'session-group'`
  - `curl -s http://127.0.0.1:9022/index.html | grep 'log-level-filter'`
  - `curl -s http://127.0.0.1:9022/index.html | grep 'log-text-filter'`
  - `curl -s http://127.0.0.1:9022/app.js | grep 'logLevelFilter'`
  - `POST http://127.0.0.1:9022/api/v1/auth/login`
  - `GET http://127.0.0.1:9022/api/v1/logs?since=0&limit=5&level=info&text=server`
  - NOTE: failover runtime smoke not rerun in this pass.

### 2025-12-25
- Changes:
  - Added managed FFmpeg transcode stream type with watchdog restarts and alert logging.
  - Added subprocess module for exec+pipe and ffprobe-based A/V desync checks.
  - Added alerts storage/API and transcode status/restart endpoints.
  - Updated UI analyze view for transcode status and restart action.
  - Added Transcode tab in stream editor with ffmpeg/watchdog settings.
  - Added transcode fixture and smoke-test instructions.
- Tests:
  - `./configure.sh`
  - `make`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts "udp://127.0.0.1:12100?pkt_size=1316"`
  - `./astra ./fixtures/transcode_cpu.json -p 9005 --data-dir ./data_transcode --web-dir ./web`
  - `POST http://127.0.0.1:9005/api/v1/auth/login`
  - `GET http://127.0.0.1:9005/api/v1/transcode-status/transcode_cpu_test` (state=RUNNING, out_time_ms present)
  - `GET http://127.0.0.1:9005/api/v1/alerts?limit=5&stream_id=transcode_cpu_test` (TRANSCODE_STALL after input stop)
  - NOTE: UI changes not retested after Transcode tab update.

### 2025-12-24
- Changes:
  - Implemented input failover with passive/active modes and per-input health tracking.
  - Added failover status fields to stream status (`active_input_index`, input states, `last_switch`).
  - Updated UI to show input status details and backup configuration fields.
  - Added failover fixture (`fixtures/failover.json`) and updated docs/smoke tests.
- Tests:
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts "udp://127.0.0.1:12000?pkt_size=1316"`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=800 -c:v mpeg2video -c:a mp2 -f mpegts "udp://127.0.0.1:12001?pkt_size=1316"`
  - `./astra ./fixtures/failover.json -p 9004 --data-dir ./data_failover --web-dir ./web`
  - `POST http://127.0.0.1:9004/api/v1/auth/login`
  - `GET http://127.0.0.1:9004/api/v1/stream-status/failover_passive` (active_input_index 0 -> 1 -> 0)
  - `GET http://127.0.0.1:9004/api/v1/stream-status/failover_active` (active_input_index 0 -> 1 -> 0)

### 2025-12-24
- Changes:
  - Added config file auto-detection for `./astra <config.json|config.lua>` and `--config`.
  - Added Lua/JSON config parsing for startup import in `scripts/config.lua`.
  - Auto-create missing config files with defaults before import.
  - Default config runs to `<config>.data` when `--data-dir` is omitted.
  - Ensured `-p` always overrides stored `http_port` when provided.
  - Added fixtures for config smoke tests (`fixtures/ada2-10815.json`, `fixtures/sample.lua`).
  - Documented new config entrypoint and smoke checks.
  - Added a server build note (`./configure.sh`) to `AGENT.md`.
- Tests:
  - `./configure.sh`
  - `make`
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `POST http://127.0.0.1:9000/api/v1/auth/login`
  - `GET http://127.0.0.1:9000/api/v1/streams`
  - `GET http://127.0.0.1:9000/api/v1/settings`
  - `./astra ./fixtures/ada2-10815.json -p 9001 --data-dir ./data_test --web-dir ./web`
  - `curl -I http://127.0.0.1:9001/index.html`
  - `POST http://127.0.0.1:9001/api/v1/auth/login`
  - `GET http://127.0.0.1:9001/api/v1/settings`
  - `GET http://127.0.0.1:9001/api/v1/streams`
  - `./astra ./fixtures/sample.lua -p 9002 --data-dir ./data_test2 --web-dir ./web`
  - `curl -I http://127.0.0.1:9002/index.html`
  - `POST http://127.0.0.1:9002/api/v1/auth/login`
  - `GET http://127.0.0.1:9002/api/v1/settings`
  - `GET http://127.0.0.1:9002/api/v1/streams`
  - `./astra ./data_test_missing.json -p 9003`
  - `test -f ./data_test_missing.json`
  - `test -f ./data_test_missing.data/astra.db`
  - `curl -I http://127.0.0.1:9003/index.html`

### 2025-12-24
- Changes:
  - Documented SemVer/deprecation window and minimal test/lint/format standards.
  - Added acceptance-criteria requirement to AGENT/SKILL checklists.
  - Marked Phase 3 (Live Metrics + Analyze) as done pending server verification.
  - Updated Phase 4/5 status and noted remaining HLS/HTTP Play wiring TODOs.
  - Wired `hls_pass_data` into HLS output and defaulted it to "pass" for compatibility.
  - Implemented `http_play_no_tls` to force `http://` URLs in playlists.
- Tests:
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `POST http://127.0.0.1:9000/api/v1/auth/login`
  - `GET http://127.0.0.1:9000/api/v1/streams`
  - `GET http://127.0.0.1:9000/api/v1/settings`

### 2025-12-22
- Changes:
  - Added newcamd softcam module to build and linked libcrypto/libm/pthread/dl.
- Tests:
  - Not run (pending server rebuild and smoke tests).

### 2025-12-22
- Changes:
  - Added adapter status polling and API endpoint for DVB signal metrics.
  - Added adapter signal/lock display in the Adapters view.
- Tests:
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `POST http://127.0.0.1:9000/api/v1/auth/login`
  - `GET http://127.0.0.1:9000/api/v1/adapter-status`
  - `GET http://127.0.0.1:9000/api/v1/adapters`
  - `GET http://127.0.0.1:9000/api/v1/streams`
  - `GET http://127.0.0.1:9000/api/v1/settings`

### 2025-12-22
- Changes:
  - Added an Adapters view with list and inline editor layout.
  - Scoped tab handling for stream vs adapter editors to prevent cross-activation.
  - Reorganized adapter form into General/LNB/Advanced sections.
- Tests:
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `POST http://127.0.0.1:9000/api/v1/auth/login`
  - `GET http://127.0.0.1:9000/api/v1/adapters`
  - `GET http://127.0.0.1:9000/api/v1/streams`
  - `GET http://127.0.0.1:9000/api/v1/settings`

### 2025-12-22
- Changes:
  - Skip DVB adapter initialization when frontend device is unavailable/busy to avoid server abort.
  - Sanitize stream map keys to avoid aborts on long map identifiers (e.g., audio.rus).
  - Gracefully handle missing DVB adapters/inputs without aborting the whole server.
- Tests:
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `POST http://127.0.0.1:9000/api/v1/auth/login`
  - `POST http://127.0.0.1:9000/api/v1/import`
  - `GET http://127.0.0.1:9000/api/v1/streams`
  - `GET http://127.0.0.1:9000/api/v1/settings`

### 2025-12-22
- Changes:
  - Added SQLite UPSERT compatibility fallback for older SQLite versions.
- Tests:
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `POST http://127.0.0.1:9000/api/v1/auth/login`
  - `GET http://127.0.0.1:9000/api/v1/streams`
  - `GET http://127.0.0.1:9000/api/v1/settings`

### 2025-12-22
- Changes:
  - Added JSON import (API `/api/v1/import`, CLI `--import`/`--import-mode`).
  - Added softcam list loading from settings and legacy user cipher handling.
  - Added UI import form for JSON configs.
- Tests:
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `POST http://127.0.0.1:9000/api/v1/auth/login`
  - `POST http://127.0.0.1:9000/api/v1/import`
  - `GET http://127.0.0.1:9000/api/v1/streams`
  - `GET http://127.0.0.1:9000/api/v1/adapters`
  - `GET http://127.0.0.1:9000/api/v1/settings`

### 2025-12-22
- Changes:
  - Added `AGENT.md`, `SKILL.md`, and this changelog template.
  - Documented workflow, working function registry, and smoke tests.
- Tests:
  - `curl -I http://127.0.0.1:9000/index.html`
  - `curl -s http://127.0.0.1:9000/app.js | head -n 1`
  - `POST http://127.0.0.1:9000/api/v1/auth/login`
  - `GET http://127.0.0.1:9000/api/v1/streams`
  - `GET http://127.0.0.1:9000/api/v1/settings`
### 2025-12-25
- Changes:
  - Replaced transcode outputs JSON textarea with a structured output list + modal in the stream editor.
  - Wired transcode outputs form values into the saved stream config.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9011 --data-dir ./data_ui_transcode_9011 --web-dir ./web &`
  - `curl -I http://127.0.0.1:9011/index.html`
  - `curl -s http://127.0.0.1:9011/index.html | grep 'transcode-output-list'`
  - `curl -s http://127.0.0.1:9011/app.js | head -n 1`
  - `POST http://127.0.0.1:9011/api/v1/auth/login`
  - `POST http://127.0.0.1:9011/api/v1/streams` (transcode payload, enabled=false)
  - `GET http://127.0.0.1:9011/api/v1/streams/transcode_ui_test`
  - `DELETE http://127.0.0.1:9011/api/v1/streams/transcode_ui_test`
### 2025-12-25
- Changes:
  - Show per-input failover status on stream tiles (active input label + all inputs list).
  - Reused stream-status input metadata for UI tooltips and state badges.
- Tests:
  - `./configure.sh`
  - `make`
  - `./astra scripts/server.lua -p 9016 --data-dir ./data_ui_inputs_9016 --web-dir ./web &`
  - `curl -I http://127.0.0.1:9016/index.html`
  - `curl -s http://127.0.0.1:9016/app.js | grep 'tile-inputs'`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts "udp://127.0.0.1:12000?pkt_size=1316" &`
  - `ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 -f lavfi -i sine=frequency=800 -c:v mpeg2video -c:a mp2 -f mpegts "udp://127.0.0.1:12001?pkt_size=1316" &`
  - `./astra ./fixtures/failover.json -p 9017 --data-dir ./data_failover_ui --web-dir ./web &`
  - `POST http://127.0.0.1:9017/api/v1/auth/login`
  - `GET http://127.0.0.1:9017/api/v1/stream-status/failover_passive` (inputs + switch checks)
  - `GET http://127.0.0.1:9017/api/v1/stream-status/failover_active` (switch + return checks)
### 2026-02-05
- Changes:
  - Added PCR smoothing (EWMA) options and pass-through EIT/CAT handling in MPTS mux.
  - Added `spts_only` guard, LCN descriptor tag override, and MPTS stats for bitrate/null%/PSI interval.
  - Fixed PAT program counting so `strict_pnr`/`spts_only` detect multi-PAT reliably.
  - Removed unused `pcr_from_pmt` flag to silence build warning.
  - Updated MPTS UI with bulk actions, pass sources, PCR smoothing fields, LCN tag input, and built-in manual/enable action.
  - Added MPTS runtime stats panel (bitrate/null%/PSI) to the editor UI.
  - Added LCN version alias (`nit.lcn_version`) and UI warning for NIT version precedence.
  - Added PAT/SDT scan helper to build `mpts_services` from multi-PAT inputs.
  - Added multi-tag LCN output (`nit.lcn_descriptor_tags`) for receiver compatibility.
  - Added MPTS stats line to stream tiles and SPTS-only duplicate-input warning.
  - Added `smoke_mpts_spts_only.sh` to validate SPTS-only rejection of multi-PAT inputs.
  - Added `/api/v1/mpts/scan` + UI probe button to auto-fill services from UDP inputs.
  - Reused shared input sockets when multiple MPTS services point to the same input URL.
  - Improved MPTS probe UX (prefill from existing input + UDP/RTP validation).
  - Added optional runtime auto-probe (`advanced.auto_probe`) to populate services from UDP/RTP inputs.
  - Auto-probe no longer requires `timeout` binary; it falls back to direct scan.
  - Added auto-probe smoke test and fixture (`smoke_mpts_auto_probe.sh`, `mpts_auto_probe.json`).
  - Extended CI smoke coverage (PID collision + pass tables) and added TS PID scanner.
  - Extended SPTS generator to emit SDT/EIT/CAT for pass-through tests.
- Tests:
  - `python3 -m py_compile tools/gen_spts.py tools/scan_pid.py`
  - `contrib/ci/smoke_mpts_pid_collision.sh`
  - `contrib/ci/smoke_mpts_pass_tables.sh`
  - `contrib/ci/smoke_mpts.sh`
  - `contrib/ci/smoke_mpts_strict_pnr.sh`
  - Not run (auto-probe UI/runtime update)
  - Not run (auto-probe smoke)
### 2026-02-05
- Changes:
  - MPTS: generate PAT/SDT/NIT as multi-section DVB PSI/SI tables (max 1024 bytes per section) to avoid truncation with large service counts.
  - Tools: `tools/gen_spts.py` supports `--program-count` and correct PSI packetization across multiple TS packets.
  - CI: add `contrib/ci/smoke_mpts_multisection.sh` + `tools/mpts_si_verify.py` and run it in GitHub Actions `mpts-smoke`.
- Tests:
  - `contrib/ci/smoke_mpts.sh`
  - `contrib/ci/smoke_mpts_pid_collision.sh`
  - `contrib/ci/smoke_mpts_pass_tables.sh`
  - `contrib/ci/smoke_mpts_strict_pnr.sh`
  - `contrib/ci/smoke_mpts_spts_only.sh`
  - `contrib/ci/smoke_mpts_auto_probe.sh`
  - `contrib/ci/smoke_mpts_multisection.sh`
