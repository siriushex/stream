# PLAN

План описывает контуры разработки и проверяемые этапы. Один этап = один thread = один набор затрагиваемых файлов.

## 1. Общий формат этапа
- Цель
- Scope (что входит / что не входит)
- Артефакты (код/тесты/дока)
- Проверки (команды)
- Риски
- Definition of Done

## 2. Этапы и зависимости

### Этап 0 (done): Project Operating System
- Цель: зафиксировать процесс разработки и обязательные опорные документы.
- Артефакты: `AGENTS.md`, `docs/*`, `AI_NOTES.md`.
- DoD: выполнен.

### Этап 1 (done): Observability master-switch + read-only режим
- Цель: сбор метрик только при `observability_enabled=true`.
- Scope: `scripts/config.lua`, `scripts/ai_observability.lua`, `scripts/system_metrics.lua`, `scripts/api.lua`, `web/app.js`.
- Результат: OFF режим останавливает ingest, read-only API доступен.
- DoD: выполнен.

### Этап 2 (done): Observability storage/perf hardening
- Цель: снизить влияние observability на runtime.
- Scope: batch writer, `resolution_sec`, индексы, separate `observability.db`, collector status.
- Результат: 10s/60s layers, bounded queue, degrade mode.
- DoD: выполнен.

### Этап 3 (done): DVB Auto Search + Full Scan core
- Цель: безопасное восстановление сигнала и анализ сетки без stampede.
- Scope: leader lock, queue, breaker, type-flip, full-scan jobs/presets/api/ui.
- Результат: serial autoswitch, manual selected stream creation из scan.
- DoD: выполнен.

### Этап 4 (in progress): UI accuracy and high-load status fidelity
- Цель: ускорить и сделать точнее realtime-отображение статусов/битрейта/CC/PES на больших инстансах.
- Scope:
  - runtime status fast-path и polling cadence
  - статусы `CC/PES` в карточках и таблице
  - минимизация false OFFLINE при 100+ streams
- Файлы:
  - `scripts/runtime.lua`
  - `scripts/api.lua`
  - `web/app.js`
  - таргетные tests в `scripts/tests/*`
- Проверки:
  1) `./configure.sh && make -j"$(nproc)"`
  2) `node --check web/app.js`
  3) `./stream scripts/tests/runtime_status_lite_fastpath_unit.lua`
  4) `./stream scripts/tests/stream_status_ids_api_unit.lua`
- Риски:
  - рост CPU при слишком частом poll
  - stale counters в смешанном local/remote dashboard
- DoD:
  - UI показывает актуальные counters без ложных OFFLINE всплесков
  - регресс-тесты status API зелёные

### Этап 5 (in progress): Distributed DVR foundation (origin + dvr_v1)
- Цель: базовый распределенный контур DVR без влияния на dataplane.
- Scope:
  - schema/migrations для `dvr_streams`, remote links/outbox/sync state
  - API `dvr_v1` (`/api/v1/dvr/*`) для streams/state/archive
  - backup state-machine primitives:
    - выбор текущего backup-сегмента без повторов в рамках цикла
    - commit прогресса и cursor-resume
    - cycle exhausted -> optional rebuild from oldest
    - backup start policy per-stream: `sequential` или `time_offset` (`backup_start_offset_hours`)
  - local single-server DVR path:
    - `dvr.configure()` local writer/cleanup tick
    - dedicated `/dvr/play/*` archive upstream (не alias обычного `/play`)
    - progress commit на disconnect для cursor-resume
  - dvr server source-ingest path:
    - writer по `dvr_streams.source_url` для импортированных stream (без зависимости от `runtime.streams`)
    - pause/resume через `record_enabled`/`recording_paused` из `dvr_streams`
  - API backup control:
    - `GET/POST /api/v1/dvr/backup/next-segment`
    - `POST /api/v1/dvr/backup/progress`
    - `POST /api/v1/dvr/backup/cursor/reset-bulk`
    - `POST /api/v1/dvr/backup/cycle/rebuild-bulk`
  - origin endpoints `/api/v1/servers/dvr/*`:
    - import/sync/bulk record
    - backup maintenance proxy (`backup/cursor/reset`, `backup/cycle/rebuild`)
    - backup maintenance transport: bulk-first (`*-bulk`) with legacy per-stream fallback on `404`
  - remote adapter `dvr_v1` в `remote_servers.lua`
  - базовый UI support для `DVR API v1` в Servers modal
  - stream editor DVR UX:
    - tab `DVR` в `Edit Stream`
    - per-stream local archive path (`config.dvr.path`)
    - per-stream remote DVR binding (`config.dvr.mode=remote`, `config.dvr.remote_server_id`) with non-blocking post-save sync
  - input editor DVR UX:
    - input type `DVR` (`dvr_server_id`, `dvr_stream_id`, `dvr_mode`)
    - serialization как HTTP input с `#input_type=dvr`
    - backend auto-binding: при `stream upsert` DVR input metadata инициализирует `config.dvr.remote_*`
- Файлы:
  - `scripts/config.lua`
  - `scripts/dvr.lua`
  - `scripts/api.lua`
  - `scripts/remote_servers.lua`
  - `scripts/server.lua`
  - `web/index.html`
  - `web/app.js`
  - `scripts/tests/dvr_ingest_state_unit.lua`
  - `scripts/tests/servers_dvr_import_sync_unit.lua`
  - `scripts/tests/dvr_backup_cycle_unit.lua`
  - `scripts/tests/dvr_backup_api_unit.lua`
  - `scripts/tests/dvr_local_playback_progress_unit.lua`
  - `scripts/tests/remote_servers_dvr_backup_bulk_unit.lua`
- Проверки:
  1) `./configure.sh && make -j"$(sysctl -n hw.ncpu)"`
  2) `node --check web/app.js`
  3) `./stream scripts/tests/dvr_ingest_state_unit.lua`
  4) `./stream scripts/tests/servers_dvr_import_sync_unit.lua`
  5) `./stream scripts/tests/dvr_backup_cycle_unit.lua`
  6) `./stream scripts/tests/dvr_backup_api_unit.lua`
  7) `./stream scripts/tests/dvr_local_playback_progress_unit.lua`
  8) `./stream scripts/tests/dvr_remote_writer_source_url_unit.lua`
  9) `./stream scripts/tests/runtime_status_lite_fastpath_unit.lua`
  10) `./stream scripts/tests/stream_status_ids_api_unit.lua`
  11) `./stream scripts/tests/remote_servers_dvr_backup_bulk_unit.lua`
- Риски:
  - рост очереди outbox при долгой недоступности DVR
  - несогласованность state при некорректных seq со стороны origin
- DoD:
  - `dvr_v1` probe/list/get/upsert/delete/action доступны через unified remote adapter
  - import локальных stream-id на DVR работает идемпотентно
  - sync-state пишет outbox и корректно обновляет `dvr_remote_sync_state`
  - auto-sync в distributed DVR передает расширенные mode (`FAIL_CONFIRMED`/`RECOVERING_TO_LIVE`) из local DVR state, а не только coarse `on_air`
  - origin proxy backup operations (`cursor reset` / `cycle rebuild`) работают по выбранным `stream_ids`
  - origin -> dvr backup maintenance использует bulk endpoints, а для старых dvr нод корректно откатывается в per-stream fallback
  - `Type=DVR` input можно указать вручную; при сохранении backend автоматически подхватывает binding и синхронизирует channel на удаленном DVR идемпотентно
  - backup cycle не повторяет сегмент в рамках цикла (anti-repeat)
  - cursor прогресса восстанавливается между вызовами API
  - при exhausted cycle поддержан controlled restart с oldest сегмента
  - на одном сервере `/dvr/play/<id>` отдает архивный сегмент и корректно двигает cursor при disconnect
  - на `dvr_v1` архив пишется для импортированных stream через `dvr_streams.source_url` даже без локального `runtime.streams`

### Этап 6 (in progress): Remote servers parity and safe CRUD for Astra legacy
- Цель: полноценная работа с удаленными stream-инстансами в Dashboard/Editor без повреждения remote config.
- Scope:
  - stricter sanitize map для Astra legacy
  - корректный remote bitrate/status hydration (включая CC/PES/transcode поля в Dashboard runtime stats)
  - UX для Servers modal/streams list (включая сортировку по ключевым колонкам)
- Зависимости: Этап 4.
- DoD:
  - remote CRUD идёт только через `servers/*` API
  - unsupported Astra fields не попадают в remote payload
  - remote streams корректно отображаются в Dashboard

### Этап 7 (in progress): Auth backends productization (Ministra/TMS first)
- Цель: интуитивный setup “portal URL only” + advanced под капотом.
- Scope:
  - UI presets/minimal mode
  - backend normalization and safe defaults (runtime-side fallback from `portal_url` when `backends[]` не заданы, с поддержкой `portal_params`)
  - docs + acceptance checklist
- Зависимости: Этап 5.
- DoD:
  - типовые Ministra/TMS сценарии проходят без ручного low-level ввода
  - совместимость с существующими `auth://backend` потоками сохранена

### Этап 8 (planned): Security/DevOps hardening
- Цель: закрыть MUST/SHOULD security items и закрепить release discipline.
- Scope:
  - sensitive-data CI enforcement
  - installer transport hardening strategy
  - rollback/backup checklists and smoke automation
- Зависимости: параллельно с этапами 5-6 по независимым файлам docs/scripts/ci.
- DoD:
  - security findings triaged (MUST/SHOULD/NICE)
  - практический runbook для `.2` и `.6` актуален

## 3. Правило завершения любого этапа
Этап считается завершенным только когда:
1. Код и тесты в репозитории.
2. Обновлены релевантные docs.
3. Обновлен `AI_NOTES.md`.
4. Пройден обязательный минимум проверок из `AGENTS.md`.
