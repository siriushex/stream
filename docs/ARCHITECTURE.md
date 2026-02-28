# ARCHITECTURE

## 1. Цель
Документ фиксирует реальную архитектуру Stream по состоянию кода репозитория и задает границы изменений для runtime/API/UI/DevOps.

Основной приоритет системы: стабильность dataplane (вещание) выше control-plane (UI/аналитика/админ-контуры).

## 2. Технологический стек
- Core runtime: C (`main.c`, `core/*`, `modules/*`)
- Runtime orchestration/API: Lua (`scripts/*.lua`)
- UI: Vanilla JS/HTML/CSS (`web/*`)
- Хранилище: SQLite (`stream.db`, опционально отдельный `observability.db`)
- Операционный запуск: systemd units (`stream@<instance>.service`)

## 3. Логические контуры

### 3.1 Dataplane
Dataplane отвечает за ingest/relay/transcode/delivery.

Ключевые части:
- `scripts/stream.lua` — жизненный цикл потоков, входы/выходы, runtime-статус.
- `scripts/transcode.lua` — transcode pipeline, watchdog/restart логика.
- C-модули `modules/*` — протоколы и low-level I/O.

Требование: dataplane не должен блокироваться тяжелыми операциями control-plane.

### 3.2 Control-plane
Control-plane отвечает за UI/API/config/auth/observability/ops.

Ключевые части:
- `scripts/server.lua` — bootstrap и HTTP роутинг (`/api`, `/play`, `/input`, `/live`, web assets).
- `scripts/api.lua` — `/api/v1/*` endpoints, валидация, mutation paths, метрики API.
- `scripts/config.lua` — schema, migrations, чтение/запись settings/streams/adapters/sessions.
- `web/app.js` — UI state, polling scheduler, view modes, servers integration.

## 4. Boot и модульная загрузка
Boot происходит через `scripts/server.lua`:
1. Загружаются базовые модули (`base`, `config`, `stream`, `auth`, `runtime`, `api`, и др.).
2. Поднимается HTTP сервер и маршруты:
   - Web UI (`/`, `/web/*`)
   - Playback (`/play/*`, `/input/*`, `/live/*`)
   - API (`/api/v1/*`)
3. Применяются settings из SQLite, после чего стартуют runtime jobs/timers.

## 5. Данные и хранилища

### 5.1 `stream.db` (операционное хранилище)
Используется для:
- `settings`, `users`, `sessions`
- `streams`, `adapters`, `alerts`, `audit`
- operational metadata (splitter/buffer/config revisions)
- DVR metadata:
  - archive/backup state (`dvr_segments`, `dvr_backup_state`, `dvr_backup_cycle_items`, `dvr_events`)
  - distributed sync (`dvr_streams`, `dvr_remote_links`, `dvr_remote_outbox`, `dvr_remote_sync_state`)

`config.lua` обеспечивает schema migration и обратную совместимость SQL (включая fallback для старых sqlite по upsert).

### 5.2 `observability.db` (изолированное хранилище метрик)
Поддерживается отдельная БД для наблюдаемости (`config.init_observability_db`):
- Таблицы: `ai_metrics_rollup`, `ai_log_events`, `system_metrics_rollup`
- Индексы под range queries + `resolution_sec` (10/60)
- WAL/busy-timeout для снижения lock-contention

Fallback: при недоступности отдельной БД чтение/запись может откатиться в `stream.db` (совместимость legacy).

## 6. API архитектура

### 6.1 Базовые API группы
`scripts/api.lua` реализует:
- stream/adapters/settings/users/sessions/log/access
- observability endpoints
- dvb auto-search/full-scan
- DVR archive/backup endpoints (`/api/v1/dvr/*`)
- distributed DVR control endpoints (`/api/v1/servers/dvr/*`)
- remote servers bridge (`stream_v1`, `astra_legacy`, `dvr_v1`)

### 6.2 API telemetry
Встроена per-route телеметрия:
- latency p50/p95/p99
- request rate
- status/error counters
- отдельный учет 401/403/302
- request-id correlation

### 6.3 Auth модель
- Web/API auth через локальные users/sessions (`config.ensure_admin` создает bootstrap admin при пустой БД).
- Stream on_play auth через `scripts/auth.lua`:
  - rules (allow/deny по token/ip/ua/country)
  - backend chain
  - token source (`query/header/cookie/auto`)
  - session_keys hashing и cache/recheck
  - runtime normalization для `auth_backends` с `portal_url` (Ministra/TMS endpoint auto-resolve, даже если `backends[]` пустой), включая перенос `portal_params` в backend query params

## 7. Observability архитектура
- Master switch: `observability_enabled` (settings).
- OFF режим:
  - ingestion/collectors остановлены
  - API чтения истории разрешен (read-only mode)
- ON режим:
  - base rollup 60s
  - optional high-res 10s (adaptive pool, bounded)
  - overload degrade logic (DB busy/queue pressure/CPU pressure)
- Поддержан worker backend (`observability_worker`) с метаданными состояния writer/queue/degrade.

## 8. DVB Auto Signal Search и Full Scan
Реализовано в `scripts/api.lua`:
- Global coordinator:
  - leader lock
  - single active task
  - queue dedup + priority + fairness
  - circuit breaker/freeze
- Adapter-level autoswitch:
  - candidate profiles (free FE only)
  - confirm window/cooldown
  - optional standalone type-flip recovery (S2->S->S2)
- Full scan:
  - presets + manual custom plans
  - jobs/grid/channels persistence
  - export/create selected streams

## 9. Remote servers integration
`scripts/remote_servers.lua` и API `/api/v1/servers/*`:
- Поддержка `stream_v1`, `astra_legacy`, `dvr_v1`
- Probe/detect + cached capabilities
- CRUD/action для remote streams
- Error classification (включая auth mismatch) и rate-limit на remote mutating actions
- Astra sanitize path: удаляются неподдерживаемые поля при upsert в legacy API
- Status hydration path сохраняет runtime поля (`bitrate`, `raw_bitrate_kbps`, `cc_errors`, `pes_errors`, `updated_at`, `transcode`) при `include_status=true`, чтобы Dashboard/Analyze не теряли remote error counters.
- Для больших remote списков status-enrichment выполняется периодически с throttling, чтобы не перегружать control-plane и при этом не оставлять Dashboard без runtime-обновлений.

## 10. Distributed DVR (origin + dvr server)
- Origin server:
  - управляет эфиром и failover,
  - импортирует local streams на удаленный DVR (`/api/v1/servers/dvr/import-streams`),
  - синхронизирует mode-state через outbox (`/api/v1/servers/dvr/sync-state`),
  - при import строит на DVR минимальный канонический config (single source input + local DVR metadata),
  - защищает import от self-origin loop (`origin_url == target dvr host:port`) по умолчанию,
  - auto-sync state в `ingest_state` учитывает локальный DVR mode (`LIVE/FAIL_CONFIRMED/DVR_ACTIVE/RECOVERING_TO_LIVE`) как приоритетный источник и только затем fallback по `runtime` статусу,
  - проксирует bulk maintenance backup-state на DVR:
    - `/api/v1/servers/dvr/backup/cursor/reset`
    - `/api/v1/servers/dvr/backup/cycle/rebuild`.
- DVR server (`dvr_v1`):
  - хранит архив и backup state,
  - предоставляет CRUD/record endpoints (`/api/v1/dvr/streams/*`),
  - при локальном `GET /api/v1/streams` синтезирует `dvr_only` stream rows из `dvr_streams` (если нет локального `config.streams` ряда), чтобы импортированные remote DVR channels были видимы в Dashboard/UI,
  - пишет архив не только для локальных runtime-stream, но и для импортированных `dvr_streams` по `source_url` (independent source-ingest writer),
  - принимает идемпотентный `ingest-state` по `state_seq`,
  - для source open failures в remote writer использует retry-backoff (anti retry-storm),
  - поддерживает backup maintenance как single и bulk:
    - `/api/v1/dvr/backup/cursor/reset`
    - `/api/v1/dvr/backup/cursor/reset-bulk`
    - `/api/v1/dvr/backup/cycle/rebuild`
    - `/api/v1/dvr/backup/cycle/rebuild-bulk`.
- Local single-server mode:
  - `dvr.configure()` запускает локальный writer/retention tick;
  - `/dvr/internal/play/<stream_id>` (и legacy `/dvr/play/<stream_id>?internal=1`) отдает архивный сегмент через backup cycle/cursor (`anti-repeat`);
  - `/dvr/archive/play/<stream_id>` отдает архивный сегмент stateless (без изменения backup cursor/cycle);
  - при disconnect `backup_commit_progress` фиксирует прогресс сегмента (lock+duration estimate), что дает resume без повтора внутри цикла.
  - backup-start policy поддерживает два режима:
    - `sequential` (дефолт, с последнего непроигранного сегмента),
    - `time_offset` (старт с сегмента, ближайшего к `now + backup_start_offset_hours*3600`, например `-24h`);
    - после exhaust текущего cycle rebuild принудительно стартует с oldest сегмента (инвариант anti-repeat + предсказуемый полный проход архива).
  - stream-level `config.dvr.path`/`config.dvr.archive_path` переопределяет корень архива для конкретного канала (иначе используется `data_dir/dvr`).
- Stream editor (UI):
  - вкладка `Edit Stream -> DVR` управляет `config.dvr` на уровне канала (`enabled`, `backup_enabled`, `retention_days`, `path`, `mode`, `remote_server_id`);
  - `Input settings` поддерживает `Type=DVR`: input сохраняется как HTTP URL (`/play` или `/dvr/play`) с метаданными `#input_type=dvr&dvr_server_id=...&dvr_stream_id=...`;
  - backend при `stream upsert` читает DVR input metadata и автоматически инициализирует `config.dvr.mode=remote` + `remote_server_id`/`remote_stream_id` (если валиден `dvr_v1` server), после чего включается стандартный remote DVR sync;
  - для режима `remote` UI после `Save` выполняет non-blocking sync в `dvr_v1` (`import-streams` + `record/bulk`), не блокируя сохранение локального конфига при ошибках удаленного DVR.
- Origin import URL auth policy:
  - при `servers/dvr/import-streams` source URL строится через `token` (если задан),
  - если token не задан, используется basic-auth fallback (`origin_login/password` -> origin server creds -> target server creds), чтобы DVR нода могла читать `/play/{id}` даже при включенной web auth на origin.
- Надежность:
  - outbox + retry/backoff на origin,
  - dedup `ingest_state` и bounded queue (`dvr_remote_outbox_max`) для защиты от queue-storm при недоступном DVR,
  - `/api/v1/servers/status` для `dvr_v1` отдает `dvr_sync` (queue/retry/last_error), чтобы UI показывал здоровье distributed sync,
  - при недоступности DVR dataplane не блокируется.

## 11. UI архитектура
`web/app.js`:
- Central state + incremental render
- Unified polling scheduler:
  - in-flight guard
  - backoff
  - hidden-tab pause
- Dashboard view modes: cards/table/compact
- Table sorting + batch actions
- Remote stream labels/grouping
- Adapter advanced UX для auto-search/type-flip/full-scan
- DVR Servers UX:
  - server type `DVR API v1`,
  - modal actions для import/bulk record,
  - modal bulk actions для backup maintenance (reset cursor/rebuild cycle),
  - sortable remote streams table (`ID/Name/Type/Enabled/Retention/On Air/Bitrate/Uptime/Input/Last error`) для быстрого triage.

## 12. Шардинг и multi-instance
- Runtime shard routing отражен в `scripts/runtime.lua` и `scripts/sharding.lua`.
- Systemd-based apply/preflight для shard instances.
- API/sharding операции не должны ломать локальную single-instance совместимость.

## 13. Архитектурные решения (Decision log)

### Decision A: Observability master switch + read-only OFF mode
- Context: Нужно исключить влияние observability на вещание.
- Chosen: `observability_enabled` гейтит сбор; чтение истории разрешено.
- Consequences: Предсказуемое поведение и управляемая нагрузка.

### Decision B: Separate observability storage
- Context: Lock/contention в общей БД ухудшал latency.
- Chosen: поддержка `observability.db` + fallback.
- Consequences: ниже риск влияния метрик на control/dataplane.

### Decision C: DVB autoswitch anti-stampede
- Context: одновременная деградация нескольких адаптеров.
- Chosen: global serial queue + breaker.
- Consequences: медленнее массовое восстановление, но выше стабильность.

### Decision D: Remote server editing through native remote API
- Context: локальное сохранение могло ломать remote Astra config.
- Chosen: server-type aware sanitize + remote CRUD/action endpoints.
- Consequences: выше совместимость с Astra/Stream API, меньше повреждений удаленного конфига.

### Decision E: Distributed DVR non-blocking sync
- Context: нужен DVR backup контур без влияния на вещание.
- Chosen: origin->dvr state sync через outbox (retry/backoff) и `dvr_v1` server type.
- Consequences: при падении DVR эфир сохраняется, sync восстанавливается асинхронно.
