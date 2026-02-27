# AI_NOTES

# Изменения — Этап 0: Внедрение Project Operating System

## Что сделано
- Обновлен корневой `AGENTS.md`:
  - добавлены постоянные правила разработки по контурам;
  - зафиксированы thread-правила и рекомендация plan mode;
  - добавлен обязательный порядок действий и DoD;
  - добавлено требование обязательного обновления `AI_NOTES.md`;
  - добавлены команды качества под текущий стек.
- Созданы базовые опорные документы:
  - `docs/ARCHITECTURE.md`
  - `docs/INVARIANTS.md`
  - `docs/PLAN.md`
  - `docs/DEVOPS.md`
  - `docs/SECURITY_REVIEW.md`

## Почему так
- Чтобы Codex имел постоянный и проверяемый процесс работы в каждом новом thread.
- Чтобы архитектурный контекст и решения не терялись между задачами.

## Риски / ограничения
- Документы созданы как baseline и требуют поэтапного наполнения по фактическим задачам.
- Разделы security findings пока пустые и должны заполняться по результатам ревью.

## Как проверить
1) Проверить наличие файлов:
```bash
ls -1 docs/ARCHITECTURE.md docs/INVARIANTS.md docs/PLAN.md docs/DEVOPS.md docs/SECURITY_REVIEW.md AI_NOTES.md
```
2) Проверить, что новый процесс зафиксирован:
```bash
sed -n '1,260p' AGENTS.md
```

# Изменения — Этап 1: Статус ошибок CC/PES в UI

## Что сделано
- В `/Users/mac/0009/astra/web/app.js` изменен статус потока при проблемах:
  - вместо общего `Online (issues)` теперь показывается текущий счетчик ошибок:
    - `CC <N>`
    - `PES <N>`
    - `CC <N> • PES <N>`
- Добавлена нормализация источника ошибок для статуса:
  - для обычных потоков — по активному input/top-level счетчикам;
  - для transcode — приоритет `output_cc_errors/output_pes_errors`, затем суммарно по `outputs_status`.

## Почему так
- Оператору нужен сразу видимый тип проблемы и текущее количество ошибок без открытия Analyze/деталей.
- Убрана неоднозначная формулировка `Online (issues)`.

## Риски / ограничения
- При очень длинных значениях статусный бейдж может быть визуально плотнее, но текст остается однострочным и коротким.
- Если backend не отдает счетчики, UI оставляет fallback `Online (issues)`.

## Как проверить
1) Проверка синтаксиса:
```bash
node --check /Users/mac/0009/astra/web/app.js
```
2) Проверка наличия новой логики:
```bash
rg -n "resolveStreamIssueCounters|formatStreamIssuesStatusLabel|Online \\(issues\\)" /Users/mac/0009/astra/web/app.js
```
3) Ручная проверка в UI:
- открыть Dashboard;
- на потоке с ошибками убедиться, что в статусе виден `CC`/`PES` и число, а не `Online (issues)`.

# Изменения — Этап 2: Наполнение опорной документации по фактическому коду

## Что сделано
- Полностью актуализированы документы:
  - `/Users/mac/0009/astra/docs/ARCHITECTURE.md`
  - `/Users/mac/0009/astra/docs/INVARIANTS.md`
  - `/Users/mac/0009/astra/docs/PLAN.md`
  - `/Users/mac/0009/astra/docs/DEVOPS.md`
  - `/Users/mac/0009/astra/docs/SECURITY_REVIEW.md`
- Зафиксированы текущие архитектурные контуры из кода:
  - dataplane/control-plane границы;
  - observability master-switch + separate storage;
  - DVB auto-search queue/leader/breaker/type-flip;
  - remote servers (`stream_v1`/`astra_legacy`) и sanitize-поведение;
  - UI polling/sorting/batch actions.
- В `SECURITY_REVIEW.md` сформирован baseline findings list (MUST/SHOULD/NICE) и план закрытия.

## Почему так
- Предыдущие версии документов были шаблонными и не отражали текущую реализацию.
- Для стабильной дальнейшей разработки и ревью нужен единый источник правды по архитектуре, инвариантам, этапам и эксплуатации.

## Риски / ограничения
- Документы фиксируют состояние текущего репозитория; при изменении runtime/API должны обновляться синхронно в том же этапе.
- В security findings часть пунктов требует отдельной реализации (например forced password change).

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(nproc)"
```
2) Синтаксис UI:
```bash
node --check /Users/mac/0009/astra/web/app.js
```
3) Обязательные runtime tests:
```bash
/Users/mac/0009/astra/stream /Users/mac/0009/astra/scripts/tests/runtime_status_lite_fastpath_unit.lua
/Users/mac/0009/astra/stream /Users/mac/0009/astra/scripts/tests/stream_status_ids_api_unit.lua
```
4) Проверка наполнения docs:
```bash
sed -n '1,220p' /Users/mac/0009/astra/docs/ARCHITECTURE.md
sed -n '1,220p' /Users/mac/0009/astra/docs/INVARIANTS.md
sed -n '1,260p' /Users/mac/0009/astra/docs/PLAN.md
sed -n '1,260p' /Users/mac/0009/astra/docs/DEVOPS.md
sed -n '1,260p' /Users/mac/0009/astra/docs/SECURITY_REVIEW.md
```

# Изменения — Этап 4: Стабильность статуса UI под высокой нагрузкой

## Что сделано
- В `/Users/mac/0009/astra/web/app.js` добавлен механизм freshness для статусов:
  - вычисление `updated_at` по top-level/active-input/transcode;
  - детекция stale-статуса (`STREAM_STATUS_STALE_SEC`);
  - short offline grace (`STREAM_STATUS_OFFLINE_GRACE_MS`) через `streamLiveCache`.
- Логика статусов обновлена:
  - вместо ложного `Offline` на stale-снимке показывается `Syncing`;
  - `No data on active input` не показывается на stale-снимке;
  - плитки/плеер используют display-live состояние, а не только сырой `stats.on_air`.
- Улучшено покрытие ids-пулинга на больших инстансах:
  - `STATUS_POLL_IDS_MAX`: `180 -> 240`;
  - `STATUS_POLL_IDS_FALLBACK_MAX`: `24 -> 48`.
- Добавлена очистка `streamLiveCache` при удалении стрима и при пересборке индекса, чтобы не копился stale cache.
- Дополнительно исправлен edge-case stale+transcode:
  - `RUNNING`/`STARTING`/`RESTARTING` больше не удерживают бесконечный `Online` при устаревшем snapshot;
  - live-state теперь считается “боевым” только на свежих timestamps, дальше действует только короткий grace-window.
- Приведён Analyze-контур к той же stale-safe логике:
  - `openAnalyze` и poll analyze job теперь используют `resolveDisplayLiveState(...)`, а не сырой `stats.on_air`;
  - в `Input status` для Analyze показывается `Syncing` на stale вместо ложного `No`;
- `pollAnalyzeCamStats`/`pollAnalyzeJob` рендерят секции с актуальным `state.stats[stream.id]`, а не с устаревшим snapshot.

# Изменения — Этап 5: DVR UX — условное отображение детальных настроек

## Что сделано
- В `/Users/mac/0009/astra/web/app.js` обновлена `updateStreamDvrFields()`:
  - блок `stream-dvr-config-block` теперь скрыт, когда оба свитча OFF:
    - `DVR archive recording = OFF`
    - `DVR backup playback = OFF`
  - блок автоматически показывается только если включён хотя бы один из двух режимов.
- Кнопки backup-операций (`Reset backup cursor`, `Rebuild backup cycle`) теперь активируются только при:
  - включённом `DVR backup playback`,
  - сохранённом локальном стриме,
  - валидном контексте режима (`local`/`remote` с выбранным сервером).
- Убран лишний вызов локального storage-detect, когда DVR полностью выключен (оба свитча OFF).

## Почему так
- UX становится предсказуемым: расширенные параметры не мешают, пока DVR не активирован.
- Backup-действия теперь не вводят в заблуждение, когда backup-режим фактически выключен.
- Уменьшены лишние фоновые обращения к API при полностью выключенном DVR.

## Риски / ограничения
- Для старых сессий браузера может потребоваться hard refresh, чтобы подхватить обновлённый `app.js`.
- Если включён только `archive` (без `backup`), backup-кнопки останутся disabled — это ожидаемое поведение.

## Как проверить
1) Проверка синтаксиса:
```bash
node --check /Users/mac/0009/astra/web/app.js
```
2) Базовые runtime регрессы:
```bash
/Users/mac/0009/astra/stream /Users/mac/0009/astra/scripts/tests/runtime_status_lite_fastpath_unit.lua
/Users/mac/0009/astra/stream /Users/mac/0009/astra/scripts/tests/stream_status_ids_api_unit.lua
```
3) Ручной UX smoke:
- открыть `Edit Stream -> DVR`;
- выключить оба свитча: блок детальных настроек скрыт;
- включить любой свитч: блок показан;
- включить `DVR backup playback` для сохранённого стрима: кнопки `Reset/Rebuild` доступны.
- Скорректирован uptime-трекер таблицы:
  - `resolveModelInputUptime` больше не наращивает uptime по stale timestamp.

## Почему так
- На инстансах с большим числом потоков часть карточек успевает устаревать между циклами частичного polling (`ids=`), из-за чего UI показывал ложный `OFFLINE / No data on active input`.
- Новая схема снижает такие ложные срабатывания без изменения backend-контрактов и без увеличения нагрузки на dataplane.

## Риски / ограничения
- Краткая grace-задержка может удерживать `Online` до 15 секунд после реального падения на редко-поллимых карточках.
- Для точного SLA по времени реакции нужно сверять поведение на боевом наборе 120+ потоков.

## Как проверить
1) Синтаксис UI:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
2) Таргетные unit-тесты runtime/api:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```
3) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(nproc)"
```

# Изменения — Этап 4: `backup_active_warm_max` в legacy failover

## Что сделано
- В `/Users/mac/0009/astra/scripts/stream.lua` исправлена логика `update_connections()`:
  - добавлен расчёт warm-standby кандидатов для `active` и `active_stop_if_all_inactive`;
  - `backup_active_warm_max` теперь реально ограничивает число фоновых warm inputs;
  - warm-кандидаты удерживаются подключёнными по приоритету входов (в порядке списка, исключая активный).
- В `update_connections()` добавлена корректная маркировка `input_data.warm`:
  - `warm=true` только для выбранных standby-входов;
  - активный/probing/невыбранные входы не остаются в ложном warm-состоянии.
- Добавлен таргетный unit-тест:
  - `/Users/mac/0009/astra/scripts/tests/stream_failover_warm_max_unit.lua`.

## Почему так
- Ранее `backup_active_warm_max` считывался в failover-конфиг, но не влиял на фактическое удержание standby-входов в legacy pipeline.
- Из-за этого в `active` не было постоянного фонового warm-режима для резервов, что расходилось с ожидаемой политикой failover.

## Риски / ограничения
- В `active` режиме может вырасти число одновременно открытых входов (до `1 + backup_active_warm_max` + probing), что повышает сетевую/CPU нагрузку.
- При очень большом `backup_active_warm_max` возможен лишний ресурсный overhead; рекомендуется оставлять консервативные значения.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(nproc)"
```
2) Синтаксис UI:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Таргетный unit-тест фикса:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/stream_failover_warm_max_unit.lua
```
4) Базовый регресс runtime status API:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

# Изменения — Этап 4: Приоритизация status polling для 120+ потоков

## Что сделано
- В `/Users/mac/0009/astra/web/app.js` доработан `collectStatusPollIds()`:
  - для `table` polling теперь приоритетно берет ID именно текущей страницы, а не случайный срез `streamTableRows`;
  - для `compact` добавлен детерминированный список `streamCompactIds`;
  - добавлен приоритетный слой проблемных потоков (offline/stale/CC/PES issues), чтобы они опрашивались чаще.
- Добавлены вспомогательные функции:
  - `collectStreamTableVisiblePollIds()`
  - `collectStreamCompactVisiblePollIds()`
  - `collectStatusIssuePriorityIds()`
- Добавлен легкий TTL-кэш приоритета проблемных ID (`statusPollIssuePriorityCache`), чтобы не пересчитывать ranking каждый тик без нужды.
- Инвалидация этого кэша добавлена при обновлении статусов и пересборке stream index.

## Почему так
- На больших инстансах (100+ потоков) часть реальных проблемных потоков могла обновляться поздно из-за неполного приоритета в `ids=` polling.
- Новая схема сохраняет bounded polling, но быстрее подтягивает “критичные” строки (CC/PES/offline/stale), что делает UI более близким к real-time без агрессивного роста нагрузки.

## Риски / ограничения
- Ranking проблемных потоков опирается на текущий `state.localStats`; если backend не отдает часть счетчиков, приоритет будет менее точным.
- При очень больших списках потоков (>240) все равно используется ротация, но теперь с более предсказуемым приоритетом.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(sysctl -n hw.ncpu)"
```
2) Синтаксис UI:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Регресс статусных тестов:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

# Изменения — Этап 5: Distributed DVR foundation (origin + dvr_v1)

## Что сделано
- В `/Users/mac/0009/astra/scripts/config.lua` добавлены migration-таблицы/индексы для distributed DVR:
  - `dvr_streams`
  - `dvr_remote_links`
  - `dvr_remote_outbox`

# Изменения — Этап 5: Восстановление детальных полей DVR в Stream Editor

## Что сделано
- В `/Users/mac/0009/astra/web/app.js` добавлена единая нормализация boolean-флагов `toBoolish(...)` (поддержка `true/false`, `1/0`, `"1"/"0"`, `"true"/"false"`, `"on"/"off"`, `"yes"/"no"`).
- На вкладке `Edit stream -> DVR` детальный блок настроек (`mode/retention/path/server`) больше не скрывается полностью при выключенных свичах — поля доступны для преднастройки.
- Обновлено чтение флагов DVR в `openEditor()`:
  - `config.dvr.enabled` читается с fallback на legacy алиас `config.dvr.archive_enabled`;
  - `config.dvr.backup_enabled` читается через bool-нормализацию.
- Обновлен distributed DVR sync (`syncStreamDvrRemoteConfig`):
  - `record_enabled` теперь вычисляется через ту же bool-нормализацию и учитывает legacy алиас `archive_enabled`.

## Почему так
- На части инстансов DVR-флаги приходили нестрого типизированными (`"1"`, `"true"`, legacy алиасы), из-за чего UI считал DVR выключенным и скрывал детальные настройки.
- Единая bool-нормализация убирает несовместимость между legacy/remote конфигами и текущим UI.

## Риски / ограничения
- Изменение затрагивает только UI-слой интерпретации флагов и не меняет runtime/Lua-контракты.
- Если в конфиге записаны нестандартные строки, не входящие в белый список (`true/false/on/off/yes/no/1/0`), поведение останется fallback.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(sysctl -n hw.ncpu)"
```
2) Синтаксис UI:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Базовый регресс runtime/API:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```
4) Ручная проверка:
- открыть `Edit stream -> DVR`;
- убедиться, что при `dvr.enabled=1|"1"|"true"` и/или `dvr.archive_enabled=...` детальный блок (`mode/retention/path/server`) отображается корректно.

# Изменения — Этап 5: Stream Editor DVR tab + per-stream archive path

## Что сделано
- В `/Users/mac/0009/astra/web/index.html` добавлена вкладка `DVR` в `Edit Stream` с простым UX:
  - `Enable DVR recording for this stream`
  - `Enable DVR backup playback on source fail`
  - `DVR mode`: `Local archive` / `DVR server`
  - `Retention (days)`
  - `Archive path` (local mode)
  - `DVR server` + кнопка перехода в `Settings -> Servers` (remote mode)
- В `/Users/mac/0009/astra/web/app.js` добавлен полный wiring новой вкладки:
  - загрузка значений из `config.dvr` при открытии редактора;
  - динамика UI (скрытие/показ local/remote полей);
  - сохранение `config.dvr` из формы с валидацией;
  - сохранение и переиспользование уже существующих dvr-полей stream-конфига (без потери дополнительных полей).
- После сохранения локального stream для `config.dvr.mode=remote` добавлен non-blocking post-save sync:
  - `POST /api/v1/servers/dvr/import-streams`
  - `POST /api/v1/servers/dvr/record/bulk`
  - локальное сохранение stream не откатывается при ошибке удаленного DVR, в UI показывается warning.
- В `/Users/mac/0009/astra/scripts/dvr.lua` добавана поддержка stream-level пути архива:
  - `dvr.settings_for_stream()` теперь читает `config.dvr.path`/`config.dvr.archive_path`;
  - `dvr.segment_paths()` поддерживает optional archive root;
  - writer использует per-stream archive root при создании сегментов.
- В `/Users/mac/0009/astra/scripts/server.lua` путь lock-файла для `/dvr/play/<id>` теперь строится с учетом stream-level archive root.
- Добавлен unit-тест:
  - `/Users/mac/0009/astra/scripts/tests/dvr_archive_path_unit.lua`
  - проверяет нормализацию absolute/relative/file:// путей и использование custom archive root.
- Обновлены документы:
  - `/Users/mac/0009/astra/docs/ARCHITECTURE.md`
  - `/Users/mac/0009/astra/docs/PLAN.md`

## Почему так
- Нужен Flussonic-подобный простой per-stream UX для DVR прямо в `Edit Stream`, без перехода по нескольким экранам.
- Оператору нужен выбор между локальным архивом и remote DVR в одном месте.
- Переключение на remote DVR не должно ломать эфир и блокировать обычное сохранение stream-конфига.
- Персональный путь архива на канал нужен для управляемого хранения и разнесения архивов.

## Риски / ограничения
- Remote DVR sync запускается после локального save и зависит от доступности удаленного DVR/API.
- Для `mode=remote` binding через `remote_server_id` опирается на наличие корректно настроенного `dvr_v1` сервера в `Settings -> Servers`.

# Изменения — Этап 5: DVR local storage detection в Stream Editor

## Что сделано
- В `/Users/mac/0009/astra/web/index.html` в `Edit Stream -> DVR -> Local` добавлены:
  - `datalist` для поля `Archive path`;
  - кнопка `Detect local disks`;
  - подсказка с рекомендованным путем.
- В `/Users/mac/0009/astra/web/app.js` добавлен локальный storage flow:
  - `loadStreamDvrLocalStorageCandidates()` (GET `/api/v1/dvr/storage/candidates`);
  - кэш на 5 минут, защита от дублирующих in-flight запросов;
  - авто-подстановка `recommended_path` в локальный `Archive path`, если поле пустое;
  - авто-подстановка не “перетирает” ручное редактирование: после пользовательского ввода/очистки поле не заполняется обратно без явного `Detect local disks`;
  - подсказка в UI с предупреждением, если recommendation пришёл с системного диска.
- В `updateStreamDvrFields()` локальный storage detect вызывается автоматически для local mode (без force), чтобы оператор сразу видел актуальный рекомендованный путь.

## Почему так
- Для локального DVR ранее был только ручной ввод пути, что повышало риск записи на системный диск.
- Новый UX выравнивает local mode с remote mode: оператору сразу доступны обнаруженные mount points и безопасный default.

## Риски / ограничения
- Авто-подстановка срабатывает только при пустом `Archive path`; уже введенный путь не перезаписывается.
- Если API storage candidates недоступен, UI остаётся работоспособным и использует ручной путь/дефолт, но показывает ошибку detect.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(sysctl -n hw.ncpu)"
```
2) UI синтаксис:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Базовый регресс runtime/API:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
./stream scripts/tests/dvr_backup_api_unit.lua
```
4) Ручная проверка:
- открыть `Edit stream -> DVR`;
- в режиме `Local archive` нажать `Detect local disks`;
- убедиться, что `Archive path` получает рекомендованный путь (если пусто), а список путей доступен через datalist.
- При недоступности DVR серверов UI показывает warning, но stream сохраняется локально (intended non-blocking behavior).

## Как проверить
1) `node --check /Users/mac/0009/astra/web/app.js`
2) `/Users/mac/0009/astra/stream /Users/mac/0009/astra/scripts/tests/dvr_archive_path_unit.lua`
3) `/Users/mac/0009/astra/stream /Users/mac/0009/astra/scripts/tests/runtime_status_lite_fastpath_unit.lua`
4) `/Users/mac/0009/astra/stream /Users/mac/0009/astra/scripts/tests/stream_status_ids_api_unit.lua`
5) `cd /Users/mac/0009/astra && ./configure.sh && make -j"$(nproc)"`
  - `dvr_remote_sync_state`
  - расширение `dvr_backup_state` полями `recording_paused`, `last_state_seq`.
- В `/Users/mac/0009/astra/scripts/dvr.lua` реализованы:
  - CRUD для `dvr_streams`;
  - `apply_ingest_state` с idempotency по `state_seq`;
  - remote-link/sync/outbox storage helpers;
  - исправлен bootstrap fallback source URL (`dvr_sanitize_id` вместо отсутствующей функции).
- В `/Users/mac/0009/astra/scripts/remote_servers.lua` добавлен полноценный адаптер `dvr_v1`:
  - detect/probe;
  - list/get/upsert/delete/action;
  - bulk upsert, bulk record, ingest-state transport.
- В `/Users/mac/0009/astra/scripts/api.lua` добавлены:
  - local DVR endpoints `/api/v1/dvr/*`;
  - origin distributed endpoints `/api/v1/servers/dvr/*`;
  - outbox sender + auto-sync tick.
- В `/Users/mac/0009/astra/scripts/server.lua` добавлен `"/dvr/play/*"` alias route.
- В UI:
  - `/Users/mac/0009/astra/web/index.html`: новый тип сервера `DVR API v1`, кнопки import/bulk record в Servers modal.
  - `/Users/mac/0009/astra/web/app.js`: dvr server type handling, dvr modal actions, dvr status rendering.
- Критичный фикс в API runtime:
  - убран crash `too many local variables` в `api.lua` через перевод DVR-хелперов в `api._dvr_*` функции.

## Почему так
- Нужно реализовать отдельный распределенный DVR-контур без блокировки эфирного dataplane.
- `dvr_v1` как отдельный server type позволяет безопасно разделить origin control и DVR storage/playback контуры.
- Outbox-модель синка сохраняет non-blocking поведение при недоступности DVR.

## Риски / ограничения
- Пока реализован foundation-слой (API/storage/sync), без полного playback state-machine для anti-repeat цикла на уровне runtime-плеера.
- На долгом недоступном DVR outbox может расти; требуются дальнейшие лимиты/breaker/hardening в следующих подэтапах.
- Build-команда из AGENTS с `nproc` на macOS недоступна; использован эквивалент `sysctl -n hw.ncpu`.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(sysctl -n hw.ncpu)"
```
2) UI синтаксис:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) DVR таргетные unit-тесты:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/dvr_ingest_state_unit.lua
./stream scripts/tests/servers_dvr_import_sync_unit.lua
```
4) Базовый runtime регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

# Изменения — Этап 6/7: Astra sanitize hardening + Auth backend portal-only runtime fallback

## Что сделано
- В `/Users/mac/0009/astra/scripts/remote_servers.lua` усилен sanitize для `astra_legacy` upsert:
  - расширен strip-list stream-only ключей (`dvr`, `backup_adapter*`, `auto_signal_*`, `satellite_type_flip_recovery`, `runtime/stats/remote/ui/issues`);
  - добавлена нормализация `input/output` (только непустые строковые URL);
  - добавлена нормализация `map` с защитой от склейки вида `video=..., audio=...udp://...`;
  - `id/name` принудительно trim перед отправкой в Astra API.
- Обновлён таргетный тест `/Users/mac/0009/astra/scripts/tests/servers_streams_upsert_astra_sanitize_unit.lua`:
  - проверяет stripping новых stream-only полей;
  - проверяет sanitize повреждённого `map`.
- В `/Users/mac/0009/astra/scripts/auth.lua` добавлен runtime fallback для режима “portal URL only”:
  - если в `settings.auth_backends.<id>` нет `backends[]`, но есть `portal_url`, endpoint строится автоматически;
  - поддержаны Ministra/TMS провайдеры (`/stalker_portal/server/api/chk_flussonic_tmp_link.php`, `/api/drm/auth_token`);
  - для Ministra/TMS при отсутствии явного `session_keys_default` подставляется безопасный дефолт.
- В `/Users/mac/0009/astra/scripts/tests/auth_backend_unit.lua` добавлены кейсы:
  - portal-only Ministra;
  - portal-only TMS.
- Документация обновлена:
  - `/Users/mac/0009/astra/docs/PLAN.md` (Stage 7 переведён в `in progress`);
  - `/Users/mac/0009/astra/docs/ARCHITECTURE.md` (добавлен runtime portal normalization).

## Почему так
- На практике remote Astra edit/save должен исключать попадание stream-only параметров и повреждённых полей в payload.
- Режим “ввёл только URL портала” должен быть устойчив не только в UI, но и на runtime при ручной/внешней конфигурации `auth_backends`.

## Риски / ограничения
- `map` sanitize использует эвристику по `://`; в нестандартных map-строках с URL-подобными подстроками может отрезать хвост.
- Runtime fallback строит один endpoint из `portal_url`; multi-backend схемы остаются в advanced (`backends[]` вручную).

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) Синтаксис UI:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Таргетные тесты:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/servers_streams_upsert_astra_sanitize_unit.lua
./stream scripts/tests/auth_backend_unit.lua
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

# Изменения — Этап 6: Servers modal sorting для remote streams

## Что сделано
- В `/Users/mac/0009/astra/web/index.html` заголовки таблицы `Settings -> Servers -> Streams` переведены в сортируемые кнопки:
  - `ID`, `Name`, `Type`, `Enabled`, `Retention`, `On Air`, `Bitrate`, `Uptime`, `Input`, `Last error`.
- В `/Users/mac/0009/astra/web/app.js` добавлен полный client-side sorting для remote streams modal:
  - новое состояние `serverStreamsSortKey/serverStreamsSortDir`;
  - нормализация ключа и сравнение по текстовым/числовым полям;
  - сортировка стабильна (tie-break по исходному индексу);
  - поддержка toggle `asc/desc` по повторному клику на заголовок;
  - синхронизация UI-индикаторов активной сортировки.
- В `/Users/mac/0009/astra/web/styles.css` выровнены строки таблицы и добавлен стиль для сортируемых заголовков в remote streams modal.
- В `/Users/mac/0009/astra/docs/PLAN.md` уточнен scope этапа 6: сортировка в Servers modal зафиксирована как часть UX-паритета.

## Почему так
- На больших удаленных списках streams оператору нужен быстрый локальный анализ по bitrate/errors/uptime без ручного фильтра и без backend-перезапросов.
- Это закрывает UX-часть текущего этапа (Remote parity) без изменений API-контрактов.

## Риски / ограничения
- Сортировка сейчас клиентская для уже загруженного списка; при очень больших объемах потребуется server-side pagination/sort.
- Удаленные значения `active_input` могут приходить как текст; в сортировке используется best-effort парсинг числа из строки.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) UI синтаксис:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Таргетные runtime/remote tests:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
./stream scripts/tests/servers_streams_list_astra_legacy_unit.lua
./stream scripts/tests/servers_streams_list_astra_partial_status_unit.lua
./stream scripts/tests/servers_streams_list_astra_status_auth_fallback_unit.lua
./stream scripts/tests/servers_streams_list_stream_v1_status_fields_unit.lua
```

# Изменения — Этап 6: Remote dashboard runtime parity (bitrate/CC/PES/transcode)

## Что сделано
- В `/Users/mac/0009/astra/scripts/remote_servers.lua` расширен `apply_stream_status(...)`:
  - теперь переносит не только `on_air/bitrate/uptime/input`, но и:
  - `raw_bitrate_kbps`, `cc_errors`, `pes_errors`, `clients_count`,
  - `updated_at`, `updated_raw_at`, `scrambled`,
  - `transcode_state`, `transcode`, `inputs` (если есть в status payload).
- В `/Users/mac/0009/astra/web/app.js` доработана нормализация remote runtime stats:
  - добавлены парсеры `parseRemoteCounter`, `parseRemoteTimestampSec`,
  - добавлена нормализация `transcode` (`output_cc_errors/output_pes_errors/outputs_status/...`),
  - в `normalizeRemoteDashboardStats(...)` теперь заполняются:
    - top-level `cc_errors/pes_errors/raw_bitrate_kbps/updated_at`,
    - `transcode_state` + `transcode`,
    - детализированные `inputs[*]` с bitrate/errors/updated_at.
- В `/Users/mac/0009/astra/web/app.js` добавлен `mergeRemoteRuntimeStats(...)`:
  - partial remote snapshot больше не затирает предыдущие поля runtime (битрейт/cc/pes/transcode/input counters),
  - при неполных ответах сохраняется непрерывность отображения в Dashboard.
- В `/Users/mac/0009/astra/web/app.js` доработан polling enrichment для крупных remote-инстансов:
  - добавлен периодический status-enrichment для списков больше `API_REMOTE_DASHBOARD_STATUS_MAX_ITEMS`,
  - добавлены ограничители `API_REMOTE_DASHBOARD_STATUS_HARD_MAX_ITEMS`, `API_REMOTE_DASHBOARD_STATUS_LARGE_EVERY_POLLS`, `API_REMOTE_DASHBOARD_STATUS_LARGE_FORCE_MS`,
  - статус на больших remote списках обновляется реже и безопасно, но не “застывает” на list-only snapshots.
- В `hasRemoteRuntimeStats(...)` добавлены признаки runtime для remote:
  - `cc_errors/pes_errors`,
  - `transcode_state/transcode`.
- Обновлены unit-тесты remote streams status:
  - `/Users/mac/0009/astra/scripts/tests/servers_streams_list_astra_legacy_unit.lua`
  - `/Users/mac/0009/astra/scripts/tests/servers_streams_list_astra_partial_status_unit.lua`
  - `/Users/mac/0009/astra/scripts/tests/servers_streams_list_astra_status_auth_fallback_unit.lua`
  - `/Users/mac/0009/astra/scripts/tests/servers_streams_list_stream_v1_status_fields_unit.lua`
  - проверки на pass-through `cc/pes` и `transcode` полей.
- Обновлены docs:
  - `/Users/mac/0009/astra/docs/ARCHITECTURE.md`
  - `/Users/mac/0009/astra/docs/PLAN.md`

## Почему так
- На remote-инстансах в Dashboard терялись counters ошибок и часть runtime-меты после `servers/streams/list`, из-за чего UI показывал неполную картину.
- Этот слой делает remote отображение ближе к локальному статусу без изменения dataplane.

## Риски / ограничения
- Качество данных ограничено тем, что реально возвращает remote API (разные Astra/Stream версии).
- При серверах, где status endpoint отдаёт только минимальные поля, часть метрик останется пустой.

## Как проверить
1) Синтаксис UI:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
2) Таргетные remote unit-тесты:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/servers_streams_list_astra_legacy_unit.lua
./stream scripts/tests/servers_streams_list_astra_partial_status_unit.lua
./stream scripts/tests/servers_streams_list_astra_status_auth_fallback_unit.lua
./stream scripts/tests/servers_streams_list_stream_v1_status_fields_unit.lua
```
3) Базовый runtime регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```
4) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```

# Изменения — Этап 4: API regession coverage для точечного `stream-status/{id}?lite=1`

## Что сделано
- В `/Users/mac/0009/astra/scripts/tests/stream_status_ids_api_unit.lua` расширено покрытие:
  - добавлены stubs `runtime.get_stream_status_lite` и `runtime.get_stream_status`;
  - добавлен сценарий `GET /api/v1/stream-status/single?lite=1` с проверкой:
    - `transcode.output_cc_errors`
    - `transcode.output_pes_errors`;
  - добавлен сценарий `GET /api/v1/stream-status/single-full` для проверки полного endpoint path.

## Почему так
- До этого тест фиксировал pass-through счётчиков только через список (`ids=`).
- Теперь регресс-покрытие закрывает оба пути: list (`/stream-status?ids=...`) и single (`/stream-status/{id}`), что защищает realtime-индикацию CC/PES в UI от слома при будущих изменениях API-роутинга.

## Риски / ограничения
- Изменение только тестовое, runtime-контракты не менялись.
- Для full интеграции remote-sharding path нужны отдельные integration smoke на инстансе.

## Как проверить
1) Таргетный тест:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/stream_status_ids_api_unit.lua
```
2) Базовый регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
```

# Изменения — Этап 5: Локальный DVR pause/resume инвариант в unit-покрытии

## Что сделано
- В `/Users/mac/0009/astra/scripts/tests/dvr_local_recovering_mode_unit.lua` добавлены проверки `recording_paused` для полного цикла local backup:
  - `LIVE` -> `recording_paused=false`
  - `FAIL_CONFIRMED` -> `recording_paused=false`
  - `DVR_ACTIVE` -> `recording_paused=true`
  - `RECOVERING_TO_LIVE` -> `recording_paused=true`
  - `LIVE` после recovery -> `recording_paused=false`.

## Почему так
- Это ключевой инвариант distributed/local DVR: при backup-воспроизведении запись должна быть на паузе, а после восстановления — возобновляться.
- Ранее тест проверял только `mode`, что не ловило возможный regression по `recording_paused`.

## Риски / ограничения
- Изменение только тестовое; production-поведение не изменялось.
- Покрытие остается unit-уровнем, для end-to-end нужна отдельная проверка на инстансе.

## Как проверить
1) Таргетные DVR тесты:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/dvr_local_recovering_mode_unit.lua
./stream scripts/tests/dvr_local_playback_progress_unit.lua
./stream scripts/tests/dvr_backup_cycle_unit.lua
```

# Изменения — Этап 5: Локальные bulk-действия DVR backup в Dashboard/Table

## Что сделано
- В `/Users/mac/0009/astra/web/index.html` в toolbar таблицы Dashboard добавлены кнопки:
  - `DVR reset cursor`
  - `DVR rebuild cycle`
- В `/Users/mac/0009/astra/web/app.js` добавлены локальные действия:
  - `resetLocalStreamDvrBackupCursor(stream)` -> `POST /api/v1/dvr/backup/cursor/reset`
  - `rebuildLocalStreamDvrBackupCycle(stream, ...)` -> `POST /api/v1/dvr/backup/cycle/rebuild`
- Расширен `runStreamTableDvrBulkAction(...)`:
  - новые action: `dvr-reset-cursor`, `dvr-rebuild-cycle`
  - применяются только к локальным потокам (remote по-прежнему skip)
  - добавлены итоговые статусы выполнения.
- Расширено состояние кнопок в `syncStreamTableSelectionUi()`:
  - disable/enable для новых bulk-кнопок по тем же правилам selection/busy.

## Почему так
- Это закрывает требование “полный DVR/DVR backup функционал локально на одном сервере”.
- Ранее backup maintenance (`cursor reset`, `cycle rebuild`) был только в `Settings -> Servers -> DVR`.
- Теперь оператор может массово управлять backup-cycle прямо из локального Dashboard/Table.

## Риски / ограничения
- Для remote DVR потоков эти действия в Dashboard намеренно не выполняются (чтобы не смешивать локальный и remote контуры); для remote остаётся `Settings -> Servers`.
- Массовые операции выполняются последовательно по выбранным потокам, что безопаснее, но медленнее на очень больших выборках.

## Как проверить
1) UI синтаксис:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
2) DVR/API regression:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/dvr_backup_api_unit.lua
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```
3) Ручной smoke:
- открыть `Dashboard -> View: Table`;
- выбрать несколько локальных каналов;
- нажать `DVR reset cursor`, затем `DVR rebuild cycle`;
- проверить, что операции завершаются без ошибок и UI остаётся отзывчивым.

# Изменения — Этап 5: Local DVR backup bulk API + UI single-request path

## Что сделано
- В `/Users/mac/0009/astra/scripts/api.lua` добавлены локальные bulk endpoints:
  - `POST /api/v1/dvr/backup/cursor/reset-bulk`
  - `POST /api/v1/dvr/backup/cycle/rebuild-bulk`
- Для дедуп/валидации списка добавлен helper:
  - `api._dvr_collect_stream_ids(...)`.
- В `/Users/mac/0009/astra/web/app.js` Dashboard bulk-action для локального DVR backup переведен на single-request:
  - `dvr-reset-cursor` теперь вызывает один `reset-bulk`;
  - `dvr-rebuild-cycle` теперь вызывает один `rebuild-bulk`;
  - remote streams по-прежнему безопасно пропускаются.
- В `/Users/mac/0009/astra/scripts/tests/dvr_backup_api_unit.lua` добавлены проверки новых bulk endpoints.
- Обновлены документы контрактов:
  - `/Users/mac/0009/astra/docs/ARCHITECTURE.md`
  - `/Users/mac/0009/astra/docs/PLAN.md`
  - `/Users/mac/0009/astra/docs/INVARIANTS.md`

## Почему так
- При массовых действиях по 100+ потокам последовательные N запросов создают лишнюю нагрузку на control-plane.
- Bulk endpoint’ы дают предсказуемое поведение и меньше сетевых/HTTP overhead без изменения dataplane.

## Риски / ограничения
- Bulk вызов может частично завершиться (`affected < total`); UI уже показывает failed list count.
- Логика intentionally не “применить ко всем” без явного списка `stream_ids`.

## Как проверить
1) UI синтаксис:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
2) DVR/API unit:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/dvr_backup_api_unit.lua
./stream scripts/tests/dvr_backup_cycle_unit.lua
```
3) Базовый runtime регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

# Изменения — Этап 5: Валидация bulk DVR backup endpoints

## Что сделано
- В `/Users/mac/0009/astra/scripts/tests/dvr_backup_api_unit.lua` добавлены негативные сценарии:
  - `POST /api/v1/dvr/backup/cursor/reset-bulk` с пустым `stream_ids` -> `400`;
  - `POST /api/v1/dvr/backup/cycle/rebuild-bulk` с пустым `stream_ids` -> `400`.

## Почему так
- Это закрепляет контракт bulk API и защищает от некорректных интеграционных вызовов из UI/скриптов.

## Риски / ограничения
- Изменение только тестовое; runtime поведение API не менялось.

## Как проверить
1) Таргетные тесты:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/dvr_backup_api_unit.lua
./stream scripts/tests/servers_dvr_import_sync_unit.lua
```
2) Базовый регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

# Изменения — Этап 4: Устранение `Online (issues)` и false `OFFLINE` при больших списках

## Что сделано
- В `/Users/mac/0009/astra/web/app.js` убран fallback-лейбл `Online (issues)` в `getStreamStatusInfo(...)`.
  - Теперь при проблемах показывается только конкретный статус по счетчикам: `CC N`, `PES N`, `CC N • PES N`.
  - Если quality-flag есть, но счетчиков `CC/PES` нет, статус остается `Online` (без расплывчатой метки).
- Добавлен динамический порог stale:
  - новая функция `computeStatusStaleThresholdSec(...)`;
  - `isStatusStale(...)` теперь учитывает текущий polling cadence и размер инстанса.
- Для больших инстансов (`120+` потоков) увеличен допустимый stale-window, чтобы chunk polling не вызывал ложные кратковременные переходы в `Offline`.

## Почему так
- Пользовательский сценарий требовал убрать двусмысленный `Online (issues)` и показывать только измеримые `CC/PES`.
- При ротационном polling (`ids=...`) старый фиксированный stale порог мог давать ложный `Offline` на загруженных дашбордах.

## Риски / ограничения
- Если проблема не выражается через `CC/PES` (например, только scrambled-флаг без счетчиков), карточка может остаться `Online`.
- Динамический stale-порог слегка увеличивает задержку детекта реального offline на очень больших инстансах, но уменьшает false-positive.

## Как проверить
1) Проверка синтаксиса UI:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
2) Таргетные runtime-тесты:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```
3) Ручная проверка в Dashboard:
- на проблемном потоке статус должен быть `CC ...` / `PES ...`, без `Online (issues)`;
- на инстансе 120+ потоков не должно быть коротких ложных `Offline` всплесков при нормальном вещании.

# Изменения — Этап 4: Realtime CC/PES для transcode в lite status

## Что сделано
- В `/Users/mac/0009/astra/scripts/transcode.lua` доработан `transcode.get_status_lite(id)`:
  - добавлены агрегированные поля:
    - `output_cc_errors`
    - `output_pes_errors`
    - `output_scrambled`
  - `updated_at` теперь учитывает не только progress timestamp, но и последние timestamps output monitor (`cc/pes/scrambled/probe`).
- Это позволяет Dashboard (lite polling) видеть актуальные output error counters у transcode-каналов без переключения на full-status.
- Добавлен unit-тест:
  - `/Users/mac/0009/astra/scripts/tests/transcode_status_lite_output_errors_unit.lua`
  - проверяет суммирование `CC/PES`, `output_scrambled=true` и корректный `updated_at`.

## Почему так
- До правки UI часто не получал `CC/PES` по transcode в режиме `lite`, потому что поля были только в full status.
- Из-за этого realtime-отображение ошибок в больших инстансах было неполным.

## Риски / ограничения
- Суммирование `output_cc_errors/output_pes_errors` — агрегат по всем output monitors, а не per-output detail (для детализации нужен full status).
- Незначительный CPU overhead: один короткий проход по `output_monitors` на каждый `get_status_lite`, что приемлемо для текущего polling.

## Как проверить
1) Новый unit:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/transcode_status_lite_output_errors_unit.lua
```
2) Базовые регрессии runtime:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```
3) UI синтаксис:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```

# Изменения — Этап 5: Origin proxy для DVR backup maintenance (reset/rebuild)

## Что сделано
- В `/Users/mac/0009/astra/scripts/api.lua` добавлены новые origin endpoints:
  - `POST /api/v1/servers/dvr/backup/cursor/reset`
  - `POST /api/v1/servers/dvr/backup/cycle/rebuild`
- Оба endpoint работают только для `dvr_v1` сервера, требуют `admin` и явный список `stream_ids`, после чего проксируют вызов через `remote_servers.lua`.
- В `/Users/mac/0009/astra/web/index.html` в modal `Servers -> Remote streams` добавлены кнопки:
  - `Reset backup cursor`
  - `Rebuild backup cycle`
- В `/Users/mac/0009/astra/web/app.js` добавлены:
  - элементы, скрытие/disable логика для новых DVR-кнопок,
  - bulk handlers по выбранным stream-ам,
  - UI actions с confirm и статусом `affected/failed`.
- Обновлен unit-тест `/Users/mac/0009/astra/scripts/tests/servers_dvr_import_sync_unit.lua`:
  - проверяет оба новых origin endpoint и корректную передачу payload в remote adapter.
- Обновлены документы:
  - `/Users/mac/0009/astra/docs/ARCHITECTURE.md`
  - `/Users/mac/0009/astra/docs/INVARIANTS.md`
  - `/Users/mac/0009/astra/docs/PLAN.md`

## Почему так
- Это закрывает operational gap distributed DVR: оператор может управлять backup-cycle удалённого DVR пакетно из origin UI, без ручных запросов на DVR node.
- Ограничение только на выбранные `stream_ids` снижает риск случайных массовых сбросов.

## Риски / ограничения
- `Rebuild backup cycle` запускается с `include_partial=true` по умолчанию в UI; тонкие параметры (`min_partial_sec`) пока только через API.
- Если remote DVR частично недоступен, возможны частичные ошибки в `failed[]`; операция не атомарная между stream-ами.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) UI синтаксис:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Тесты DVR origin/remote:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/servers_dvr_import_sync_unit.lua
./stream scripts/tests/dvr_ingest_state_unit.lua
./stream scripts/tests/dvr_backup_api_unit.lua
```
4) Базовый runtime регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

# Изменения — Этап 5: Servers status DVR sync health (API + UI)

## Что сделано
- В `/Users/mac/0009/astra/scripts/api.lua` обновлён `GET /api/v1/servers/status`:
  - для серверов типа `dvr_v1` в ответ добавляется `dvr_sync` из `dvr_store.get_remote_sync_health(server_id)`.
- В `/Users/mac/0009/astra/web/app.js` доработан рендер Settings → Servers:
  - под основным badge статуса выводится строка `DVR sync: ...` (queue/ready/retry/max/next/oldest),
  - цветовая индикация (`ok/warn`) и tooltip с расширенной диагностикой (`links/sync_rows/last_error`).
- В `/Users/mac/0009/astra/web/styles.css` добавлены стили для вторичной строки статуса (`.server-status-meta`).
- Добавлен новый unit-тест:
  - `/Users/mac/0009/astra/scripts/tests/servers_status_dvr_health_unit.lua`
  - валидирует, что `/api/v1/servers/status` возвращает `dvr_sync` и корректные счетчики outbox/retry.

## Почему так
- Для distributed DVR оператору нужен быстрый health-check очереди sync прямо в таблице Servers, без ручного SQL/логов.
- Диагностика outbox/retry/last_error сокращает время обнаружения деградации Origin→DVR синка.

## Риски / ограничения
- Строка `DVR sync` показывает агрегированное состояние outbox на момент polling; кратковременные пики между тиками могут быть не видны.
- Tooltip хранит последний известный `last_error`; это не полный event-log.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) UI синтаксис:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Таргетные тесты:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/servers_status_dvr_health_unit.lua
./stream scripts/tests/servers_dvr_import_sync_unit.lua
./stream scripts/tests/dvr_outbox_hardening_unit.lua
./stream scripts/tests/dvr_ingest_state_unit.lua
./stream scripts/tests/dvr_backup_api_unit.lua
```
4) Базовый runtime регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

# Изменения — Этап 5: DVR outbox hardening (dedup + bounded queue)

## Что сделано
- В `/Users/mac/0009/astra/scripts/dvr.lua` усилен `dvr_remote_outbox`:
  - добавлена дедупликация `ingest_state` по `stream_id + dvr_server_id + event_type + state_seq/mode/reason`;
  - добавлено удаление устаревших queued-состояний с меньшим/равным `state_seq` для того же stream/server;
  - добавлен bounded-лимит очереди `dvr_remote_outbox_max` (по умолчанию `2000`) с prune oldest.
- Добавлен helper `dvr.outbox_count()` для контроля размера очереди в тестах/диагностике.
- Добавлен новый unit-тест:
  - `/Users/mac/0009/astra/scripts/tests/dvr_outbox_hardening_unit.lua`
  - проверяет:
    - dedup одинакового `ingest_state`;
    - replacement устаревшего seq новым;
    - жёсткий cap очереди и prune oldest.
- Актуализированы документы:
  - `/Users/mac/0009/astra/docs/ARCHITECTURE.md`
  - `/Users/mac/0009/astra/docs/INVARIANTS.md`

## Почему так
- При недоступном DVR auto-sync мог ставить одинаковые state-события повторно, что вело к росту outbox и лишним retry.
- Новый механизм сохраняет только актуальное состояние для stream/server и предотвращает queue-storm без влияния на dataplane.

## Риски / ограничения
- При очень маленьком `dvr_remote_outbox_max` возможно агрессивное удаление старых несвязанных событий; рекомендуется не ставить слишком низкие значения в production.
- Дедуп ориентирован на `ingest_state`; для других event_type оставлена простая дедупликация по одинаковому payload JSON.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) UI синтаксис:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Таргетные тесты:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/dvr_outbox_hardening_unit.lua
./stream scripts/tests/dvr_ingest_state_unit.lua
./stream scripts/tests/servers_dvr_import_sync_unit.lua
```
4) Базовый runtime регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

# Изменения — Этап 5: Локальный recovery для DVR backup (`RECOVERING_TO_LIVE`)

## Что сделано
- В `/Users/mac/0009/astra/scripts/dvr.lua` доработан локальный state-machine:
  - добавлена отдельная фаза `RECOVERING_TO_LIVE` после выхода из `DVR_ACTIVE`;
  - теперь используется `backup_recover_stable_sec` перед возвратом в `LIVE`;
  - во время `RECOVERING_TO_LIVE` `recording_paused=true` (запись не стартует раньше стабильного возврата).
- Усилена синхронизация `dvr_streams` runtime-метаданных:
  - обновление строки больше не ждёт 15 секунд, если изменились `record_enabled`/`recording_paused`/`last_mode`/`last_reason`;
  - throttle 15s остаётся только для неизменного состояния.
- Добавлена очистка локальных таймер-карт `fault_since/recover_since` для неактивных потоков, чтобы не копились stale markers.
- Добавлен новый unit-тест:
  - `/Users/mac/0009/astra/scripts/tests/dvr_local_recovering_mode_unit.lua`
  - проверяет цепочку `LIVE -> FAIL_CONFIRMED -> DVR_ACTIVE -> RECOVERING_TO_LIVE -> LIVE`.

## Почему так
- Ранее `backup_recover_stable_sec` был в настройках, но не использовался в локальном поведении.
- Мгновенный возврат `DVR_ACTIVE -> LIVE` создавал риск раннего resume и флаппинга на нестабильном входе.
- Обновление `dvr_streams` с фиксированным hold могло давать заметно устаревший статус DVR в UI.

## Риски / ограничения
- При слишком большом `backup_recover_stable_sec` возврат в live будет намеренно задержан.
- В фазе `RECOVERING_TO_LIVE` запись остаётся на паузе по дизайну; это корректно для anti-flap, но нужно учитывать в SLA записи.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) UI синтаксис:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) DVR unit tests:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/dvr_local_recovering_mode_unit.lua
./stream scripts/tests/dvr_local_playback_progress_unit.lua
./stream scripts/tests/dvr_backup_cycle_unit.lua
./stream scripts/tests/dvr_ingest_state_unit.lua
./stream scripts/tests/dvr_streams_list_api_metadata_unit.lua
```
4) Базовый runtime регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

# Изменения — Этап 5: DVR backup cycle anti-repeat + progress API

## Что сделано
- В `/Users/mac/0009/astra/scripts/dvr.lua` добавлены примитивы backup state-machine:
  - `dvr.get_cycle_item(...)`
  - `dvr.backup_select_segment(...)`
  - `dvr.backup_commit_progress(...)`
- Реализована логика:
  - выбор текущего сегмента из цикла без повторов (`pending -> playing -> done/skipped`);
  - сохранение и восстановление `cursor_offset_sec` (resume в пределах сегмента);
  - обработка `cycle exhausted` с опциональным rebuild нового цикла с oldest сегмента.
- В `/Users/mac/0009/astra/scripts/api.lua` добавлены новые endpoints:
  - `GET/POST /api/v1/dvr/backup/next-segment`
  - `POST /api/v1/dvr/backup/progress`
- Добавлен таргетный unit-тест:
  - `/Users/mac/0009/astra/scripts/tests/dvr_backup_cycle_unit.lua`
  - покрывает anti-repeat, resume offset, exhausted cycle и controlled restart.
- Добавлен API unit-тест:
  - `/Users/mac/0009/astra/scripts/tests/dvr_backup_api_unit.lua`
  - проверяет контракты `/api/v1/dvr/backup/next-segment` и `/api/v1/dvr/backup/progress`.

## Почему так
- Это закрывает недостающий шаг плана для backup playback orchestration без внедрения тяжелой логики в dataplane.
- Управление циклом и cursor вынесено в явные API-контракты, что упрощает интеграцию Origin↔DVR и последующий `/dvr/play` runtime слой.

## Риски / ограничения
- Текущий шаг покрывает state/cycle orchestration и API, но не включает отдельный runtime endpoint c TS-stream выдачей архива (`/dvr/play/<id>` как сегментный источник).
- `segment_guard_sec` пока задается через payload (или default), без полного policy-layer на stream settings в этом подэтапе.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) Синтаксис UI:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) DVR unit:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/dvr_ingest_state_unit.lua
./stream scripts/tests/servers_dvr_import_sync_unit.lua
./stream scripts/tests/dvr_backup_cycle_unit.lua
./stream scripts/tests/dvr_backup_api_unit.lua
```
4) Базовый runtime регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

# Изменения — Этап 5: Local single-server DVR playback path (`/dvr/play`)

## Что сделано
- В `/Users/mac/0009/astra/scripts/server.lua` добавлен отдельный upstream callback `http_dvr_play_stream` для `/dvr/play/*`:
  - больше не используется alias обычного `/play/*`;
  - сегмент выбирается через `dvr.backup_select_segment(...)` (cycle/cursor, anti-repeat);
  - сегмент отдается как `file://...` input с lock-файлом.
- В `http_dvr_play_stream` добавлен commit прогресса при disconnect:
  - читается lock offset;
  - оценивается `played_sec`;
  - вызывается `dvr.backup_commit_progress(...)` для cursor-resume/advance.
- В `/Users/mac/0009/astra/scripts/server.lua` подключен `dvr.configure()` на старте сервера, чтобы локальный writer/tick был активен в single-server режиме.
- В `/Users/mac/0009/astra/scripts/base.lua` расширен internal auth bypass для loopback запросов на `/dvr/play/*` (с `?internal=1`) по тем же правилам, что `/play`.
- В `/Users/mac/0009/astra/scripts/dvr.lua` добавлены helper-функции:
  - `dvr.read_lock_bytes(path)`
  - `dvr.estimate_segment_played_sec(segment, lock_bytes, fallback_elapsed_sec)`
- Добавлен новый unit-тест:
  - `/Users/mac/0009/astra/scripts/tests/dvr_local_playback_progress_unit.lua`
  - покрывает lock parsing, played_sec estimate и `done -> next segment` через `backup_commit_progress`.
- Актуализированы документы:
  - `/Users/mac/0009/astra/docs/ARCHITECTURE.md`
  - `/Users/mac/0009/astra/docs/INVARIANTS.md`
  - `/Users/mac/0009/astra/docs/PLAN.md`

## Почему так
- Ранее `/dvr/play/*` фактически шел через live `/play/*`, из-за чего локальный DVR backup не был полноценным.
- Выделенный архивный upstream + commit прогресса закрывают ключевой сценарий “DVR и backup на одном сервере” без распределенного DVR-хоста.

## Риски / ограничения
- Оценка `played_sec` по lock/size является приближенной (best-effort), особенно на нестандартных TS-файлах.
- Для автоматического включения backup в chain поток должен иметь корректный backup input на `/dvr/play/<id>`.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) Синтаксис UI:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) DVR таргетные тесты:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/dvr_ingest_state_unit.lua
./stream scripts/tests/servers_dvr_import_sync_unit.lua
./stream scripts/tests/dvr_backup_cycle_unit.lua
./stream scripts/tests/dvr_backup_api_unit.lua
./stream scripts/tests/dvr_local_playback_progress_unit.lua
```
4) Базовый runtime регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

# Изменения — Этап 5: Servers → DVR streams batch selection (multi-select)

## Что сделано
- В `/Users/mac/0009/astra/web/index.html` доработан modal `Remote streams`:
  - добавлена колонка выбора с `Select all`;
  - добавлен счётчик выбранных строк `Selected: N`.
- В `/Users/mac/0009/astra/web/app.js` реализован полноценный multi-select для `Servers -> Streams`:
  - новое состояние `serverStreamsSelected: Set`;
  - выбор/снятие выбора по чекбоксам строк;
  - массовый `select all` по текущему фильтру;
  - очистка stale selection после reload списка;
  - выделение выбранных строк и отдельный `focused` stream для fast-poll.
- Изменена логика batch-действий для DVR:
  - `Enable record`/`Disable record` работают только по выбранным stream id;
  - кнопки record автоматически disabled при пустом выборе;
  - `Import channels` работает как:
    - есть выбор -> импорт только выбранных,
    - выбора нет -> `import_all=true`.
- В `/Users/mac/0009/astra/web/styles.css` обновлена сетка таблицы и стили:
  - новая колонка checkbox,
  - корректные `nth-child` для многострочных полей,
  - визуальный highlight выбранных строк.

## Почему так
- Это закрывает функциональный разрыв в этапе distributed DVR UI: оператору нужен безопасный batch-control, а не одиночное действие по “активной” строке.
- Multi-select в modal снижает риск ошибочного массового изменения записей и делает поведение импорт/record предсказуемым.

## Риски / ограничения
- Batch selection пока реализован только в `Servers -> Streams` modal (не в основном dashboard table для remote rows).
- При очень больших списках remote streams (>1000) рендер остаётся клиентским; серверная пагинация для modal ещё не добавлена.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) Синтаксис UI:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Базовый runtime регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```
4) Ручной smoke (Settings -> Servers -> Streams):
- отметить 2-3 строки и нажать `Enable record`;
- убедиться, что changed только выбранные;
- снять выбор и запустить `Import channels` -> уходит режим `import_all`;
- включить фильтр, нажать `Select all`, проверить что выбираются только отфильтрованные строки.

# Изменения — Этап 5: Локальный DVR control в Dashboard + API dvr metadata

## Что сделано
- В `/Users/mac/0009/astra/web/index.html` в `Dashboard -> Table` добавлены bulk-кнопки:
  - `DVR ON`
  - `DVR OFF`
  - `DVR retention`
- В `/Users/mac/0009/astra/web/app.js` реализованы локальные bulk-операции DVR для выбранных потоков:
  - `runStreamTableDvrBulkAction(...)`;
  - `setLocalStreamDvrConfig(...)` с patch только `config.dvr`;
  - remote-потоки в этом действии пропускаются (без риска повредить remote API контур).
- В `/Users/mac/0009/astra/web/app.js` обновлена модель DVR статуса в таблице:
  - `OFF` / `REC` / `PAUSED(BACKUP)` вместо примитивного `on/off`;
  - приоритет `recording_paused` и `last_mode == DVR_ACTIVE`.
- В `/Users/mac/0009/astra/scripts/api.lua` расширены ответы:
  - `GET /api/v1/streams`
  - `GET /api/v1/streams/{id}`
  теперь включают `dvr`-метаданные (`record_enabled`, `recording_paused`, `retention_days`, `last_mode`, `last_state_seq`, `updated_ts`) при наличии строки в `dvr_streams`.
- Добавлен новый unit-тест:
  - `/Users/mac/0009/astra/scripts/tests/dvr_streams_list_api_metadata_unit.lua`
  - валидирует выдачу `dvr`-метаданных в `list/get` API.

## Почему так
- Это закрывает требование “полный DVR/DVR-backup функционал локально на одном сервере” без обязательного удалённого DVR-инстанса.
- Оператор получает массовое локальное управление записью прямо из Dashboard, а UI показывает фактический режим DVR по данным runtime/store.

## Риски / ограничения
- Bulk DVR действия в Dashboard применяются только к локальным потокам; для remote DVR остаётся отдельный контур `Servers -> Streams`.
- `dvr`-метаданные в `list_streams` добавляют один batched lookup `dvr_store.list_streams`, что даёт небольшой overhead control-plane, но без влияния на dataplane.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) UI синтаксис:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Тесты DVR/API:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/dvr_streams_list_api_metadata_unit.lua
./stream scripts/tests/dvr_bulk_record_retention_only_unit.lua
./stream scripts/tests/dvr_backup_api_unit.lua
./stream scripts/tests/servers_dvr_import_sync_unit.lua
./stream scripts/tests/dvr_ingest_state_unit.lua
```
4) Базовый runtime регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

# Изменения — Этап 7: Auth backends portal-only completion + portal params

## Что сделано
- В `/Users/mac/0009/astra/scripts/auth.lua` завершена runtime-нормализация portal-only backend:
  - добавлена нормализация `portal_params` (sanitize map);
  - при `backends[]` пустом и `portal_url` заданном endpoint создаётся автоматически как раньше, но теперь с `params` из `portal_params`;
  - если `backends[]` уже задан, но у первого backend нет `params`, `portal_params` подмешиваются в него.
- В `/Users/mac/0009/astra/web/app.js` доведён UI-контур simple setup:
  - завершено использование helper-логики для resolved URL из `portal_url`;
  - для portal-only режима сохранение теперь не форсирует `backends[]` (runtime fallback покрывает это);
  - поддержано сохранение `portal_params` из строки вида `https://portal ... key=value;`;
  - в таблице Auth backends URL корректно отображается и для portal-only конфигов;
  - в modal portal поле корректно восстанавливается вместе с `portal_params`.
- В `/Users/mac/0009/astra/scripts/tests/auth_backend_unit.lua` добавлен тест:
  - portal-only + `portal_params` действительно доходят в backend query.
- Обновлены документы:
  - `/Users/mac/0009/astra/docs/ARCHITECTURE.md`
  - `/Users/mac/0009/astra/docs/PLAN.md`

## Почему так
- Цель этапа 7 — реальный “portal URL only” сценарий без ручного low-level заполнения backend URL.
- Ранее runtime fallback умел автосборку endpoint, но UI всегда сохранял `backends[]`; теперь simple и runtime работают согласованно, включая static query-параметры портала.

## Риски / ограничения
- Если оператор одновременно заполняет `Portal address` и ручной список `Backend URLs`, приоритет у ручного списка (advanced mode).
- `portal_params` применяются как query params; для нестандартных backend-схем с body-only auth это не покрывается и остаётся advanced-настройкой.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) UI синтаксис:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Таргетные тесты auth/runtime:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/auth_backend_unit.lua
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

# Изменения — Этап 5: Distributed DVR auto-sync mode fidelity

## Что сделано
- В `/Users/mac/0009/astra/scripts/api.lua` доработан auto-sync origin -> DVR:
  - добавлен `api._dvr_local_mode_hint(stream_id)` для чтения свежего локального DVR state из `dvr_streams`;
  - `api._dvr_mode_from_status(...)` теперь сначала использует локальный mode (`LIVE/FAIL_CONFIRMED/DVR_ACTIVE/RECOVERING_TO_LIVE`), и только при отсутствии свежего state делает fallback по `runtime status`.
- В `/Users/mac/0009/astra/scripts/tests/servers_dvr_import_sync_unit.lua` добавлен сценарий:
  - auto-sync должен отправлять `RECOVERING_TO_LIVE` для stream с таким локальным mode даже если coarse runtime status указывает `on_air=false`.
- Обновлены документы:
  - `/Users/mac/0009/astra/docs/ARCHITECTURE.md`
  - `/Users/mac/0009/astra/docs/PLAN.md`

## Почему так
- Ранее periodic auto-sync строил режим только из `status.on_air`, что схлопывало state machine до `LIVE/DVR_ACTIVE`.
- Для корректной distributed backup-логики нужны промежуточные состояния (`FAIL_CONFIRMED` и `RECOVERING_TO_LIVE`) от локального DVR контура.

## Риски / ограничения
- При устаревшем `dvr_streams.updated_ts` (>30s) включается fallback по runtime статусу.
- Если локальный state не обновляется из-за сбоя local tick, remote может временно получать coarse mode.

## Как проверить
1) Таргетные DVR tests:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/servers_dvr_import_sync_unit.lua
./stream scripts/tests/dvr_ingest_state_unit.lua
./stream scripts/tests/dvr_outbox_hardening_unit.lua
```
2) Базовый runtime регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```
3) UI синтаксис:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```

# Изменения — Этап 5: DVR backup maintenance bulk-first transport + legacy fallback

## Что сделано
- В `/Users/mac/0009/astra/scripts/remote_servers.lua` доработан транспорт backup maintenance для `dvr_v1`:
  - `remote_servers.dvr_backup_cursor_reset(...)` теперь сначала вызывает bulk endpoint:
    - `POST /api/v1/dvr/backup/cursor/reset-bulk`
  - `remote_servers.dvr_backup_cycle_rebuild(...)` теперь сначала вызывает bulk endpoint:
    - `POST /api/v1/dvr/backup/cycle/rebuild-bulk`
  - при ответе `404` автоматически включается legacy fallback на per-stream вызовы:
    - `POST /api/v1/dvr/backup/cursor/reset`
    - `POST /api/v1/dvr/backup/cycle/rebuild`
  - сохранена дедупликация `stream_ids` и обратная совместимость callback payload.
- Добавлен таргетный unit-тест:
  - `/Users/mac/0009/astra/scripts/tests/remote_servers_dvr_backup_bulk_unit.lua`
  - проверяет:
    - bulk-success для cursor reset;
    - fallback `404 -> per-stream` для cycle rebuild;
    - сохранение `include_partial/min_partial_sec` в fallback запросах.
- Обновлён план:
  - `/Users/mac/0009/astra/docs/PLAN.md` дополнен требованием bulk-first transport и новым тестом в обязательных проверках Этапа 5.

## Почему так
- На больших списках потоков per-stream maintenance вызывает лишний шторм запросов на DVR server.
- Bulk-first снижает latency и нагрузку control-plane.
- Legacy fallback нужен для совместимости со старыми DVR нодами, где bulk endpoints ещё отсутствуют.

## Риски / ограничения
- Если удалённый DVR отдаёт `404` на bulk, срабатывает fallback и количество запросов снова растёт до `N`.
- Для новых нод поведение лучше по перформансу, но mixed-cluster временно может работать в двух режимах.

## Как проверить
1) Таргетные тесты:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/remote_servers_dvr_backup_bulk_unit.lua
./stream scripts/tests/servers_dvr_import_sync_unit.lua
./stream scripts/tests/dvr_backup_api_unit.lua
```
2) Базовый runtime регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```
3) UI синтаксис:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```

# Изменения — Этап 5: `servers/dvr/sync-state` ad-hoc direct-send (без saved server id)

## Что сделано
- В `/Users/mac/0009/astra/scripts/api.lua` доработан `api._servers_dvr_sync_state`:
  - если запрос идёт с сохранённым `server.id`, поведение прежнее:
    - enqueue в `dvr_remote_outbox`;
    - отправка через outbox + retry path.
  - если запрос ad-hoc (без `id`), включён direct-send path:
    - сразу вызывается `remote_servers.dvr_ingest_state(...)`;
    - ответ возвращается как `{ queued=false, sent=true/false }`;
    - `defer=true` для ad-hoc запрещён с явной ошибкой `400`.
  - для ad-hoc без явного `state_seq` добавлен auto-seq (`os.time()`), чтобы remote не отклонял событие как duplicate с `state_seq=1`.
- Добавлен unit-тест:
  - `/Users/mac/0009/astra/scripts/tests/servers_dvr_import_sync_unit.lua`
  - проверяет ad-hoc sync-state без `id`:
    - `200 OK`,
    - `queued=false`,
    - фактический вызов remote ingest.

## Почему так
- В e2e на `.2` обнаружился практический сбой:
  - `POST /api/v1/servers/dvr/sync-state` без saved `id` возвращал `500` (`stream_id/dvr_server_id/event_type required`).
- Для API-интеграций и ручного ops-тестирования нужен предсказуемый ad-hoc режим без зависимости от сохранения server profile в settings.

## Риски / ограничения
- Ad-hoc режим intentionally не использует outbox/retry (он одноразовый direct-send).
- Надёжная доставка с ретраями остаётся только для saved server (`id`) пути.

## Как проверить
1) Локальные тесты:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/servers_dvr_import_sync_unit.lua
./stream scripts/tests/dvr_outbox_hardening_unit.lua
./stream scripts/tests/dvr_backup_api_unit.lua
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
node --check web/app.js
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) Smoke на `.2`:
```bash
curl -sS -X POST http://<test-node>:9060/api/v1/servers/dvr/sync-state \
  -H 'Content-Type: application/json' \
  -d '{"type":"dvr_v1","host":"127.0.0.1","port":9061,"login":"admin","password":"admin","stream_id":"nbc","mode":"DVR_ACTIVE"}'
```
Ожидаемо: `200`, `queued=false`.
3) Проверка применения ad-hoc sync:
```bash
curl -sS -X POST http://<test-node>:9060/api/v1/servers/dvr/sync-state \
  -H 'Content-Type: application/json' \
  -d '{"type":"dvr_v1","host":"127.0.0.1","port":9061,"login":"admin","password":"admin","stream_id":"nbc","mode":"DVR_ACTIVE"}'
```
Ожидаемо: в `remote.state` будет `applied=true`, `ignored_duplicate=false`, а на DVR (`:9061`) у потока `recording_paused=true`.

# Изменения — Этап 4: Standalone type-flip trigger по `CC + PES` за 60 секунд

## Что сделано
- В `/Users/mac/0009/astra/scripts/api.lua` изменена логика standalone type-flip (`S2->S->S2`):
  - вместо `no_data + PES` теперь используется `CC delta + PES delta` по всем потокам адаптера;
  - окно деградации для standalone режима зафиксировано на `60` секунд;
  - пороги по умолчанию изменены на:
    - `type_flip_cc_threshold = 50`
    - `type_flip_pes_threshold = 50`
  - reason при срабатывании теперь `cc_pes`.
- Сохранена backward-compatibility по входному флагу:
  - `no_data_pes_only` поддерживается как legacy alias, но routed в новую `cc_pes_only` ветку.
- Обновлены таргетные unit-тесты:
  - `/Users/mac/0009/astra/scripts/tests/dvb_autosearch_type_flip_nodata_pes_unit.lua`
  - `/Users/mac/0009/astra/scripts/tests/dvb_autosearch_type_flip_independent_unit.lua`
  - `/Users/mac/0009/astra/scripts/tests/dvb_autosearch_type_flip_unit.lua`

## Почему так
- Текущая эксплуатация показала, что standalone type-flip не должен ждать `no_data`, когда есть массовый рост `CC/PES`.
- Новый критерий напрямую соответствует операционному условию: триггер при `CC > 50` и `PES > 50` за минуту по адаптеру.

## Риски / ограничения
- При шумных линиях с кратковременными всплесками `CC/PES` возможны более частые автотриггеры.
- Старый сценарий `no_data` без выраженного роста `CC/PES` в standalone режиме больше не является самостоятельным триггером.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(sysctl -n hw.ncpu)"
```
2) Таргетные unit-тесты по изменённому контуру:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/dvb_autosearch_type_flip_nodata_pes_unit.lua
./stream scripts/tests/dvb_autosearch_type_flip_independent_unit.lua
./stream scripts/tests/dvb_autosearch_type_flip_unit.lua
./stream scripts/tests/dvb_autosearch_cc_delta_unit.lua
./stream scripts/tests/dvb_autosearch_queue_unit.lua
```
3) Базовый регресс:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
node --check web/app.js
```

# Изменения — Этап 5: Distributed DVR writer для `dvr_streams.source_url`

## Что сделано
- В `/Users/mac/0009/astra/scripts/dvr.lua` реализован независимый source-ingest writer для DVR-ноды:
  - добавлен контур `remote_streams` в runtime state DVR writer;
  - запись архивных сегментов теперь запускается для строк `dvr_streams` с `record_enabled=true` и `recording_paused=false`, даже если поток отсутствует в `runtime.streams`;
  - writer открывает вход через `source_url` (`init_input(parse_url(...))`) и пишет в архив через `file_output`.
- Для локального runtime writer и нового source-ingest writer унифицированы:
  - открытие writer через общий helper `dvr_writer_open_from_upstream(...)`;
  - flush/cleanup через общий helper `dvr_writer_flush_and_cleanup(...)`.
- В `dvr_writer_finalize(...)` добавлено корректное закрытие source input (`kill_input`) для remote writer, чтобы не оставлять висящие input-инстансы.
- В `dvr.local_tick()`:
  - убрана жёсткая зависимость от наличия `runtime.streams` (tick продолжает работать для distributed DVR even when runtime empty);
  - добавлен проход по `dvr.list_streams(record_enabled=true)` для source-ingest;
  - добавлена безопасная очистка remote writer-ов, которые вышли из active набора.
- Добавлен rate-limit логирования ошибок открытия remote source:
  - событие `DVR_REMOTE_RECORD_OPEN_FAIL` не чаще 1 раза в 30 секунд на stream.
- Добавлен unit-тест:
  - `/Users/mac/0009/astra/scripts/tests/dvr_remote_writer_source_url_unit.lua`
  - проверяет старт записи по `source_url` без `runtime.streams` и финализацию сегмента при отключении записи.

## Почему так
- До правки distributed DVR foundation покрывал API/sync/state, но фактический archive writer работал только через локальный runtime-контур (`runtime.streams` + `stream_cfg.dvr`).
- На DVR-ноде после `import-streams` запись для удалённых источников (`source_url`) могла не стартовать, если эти потоки не существовали как локальные runtime stream.
- Новый контур закрывает этот функциональный разрыв без вмешательства в dataplane origin.

## Риски / ограничения
- Для `source_url=file://...` без валидного TS возможны диагностические сообщения input-модуля (`first PCR is not found`), это не ломает writer-контур теста.
- Source-ingest writer intentionally не использует runtime `on_air`; управление pause/resume идёт через `record_enabled`/`recording_paused` и `ingest-state`.
- На одном stream_id одновременно не ведутся два writer-а:
  - приоритет у локального runtime writer (если stream активен в `runtime.streams` и dvr включён там),
  - source-ingest writer для такого id пропускается.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) Таргетные DVR тесты:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/dvr_remote_writer_source_url_unit.lua
./stream scripts/tests/dvr_local_playback_progress_unit.lua
./stream scripts/tests/dvr_local_recovering_mode_unit.lua
./stream scripts/tests/dvr_backup_cycle_unit.lua
./stream scripts/tests/dvr_backup_api_unit.lua
./stream scripts/tests/dvr_ingest_state_unit.lua
./stream scripts/tests/dvr_outbox_hardening_unit.lua
./stream scripts/tests/servers_dvr_import_sync_unit.lua
```
3) Базовый регресс и UI синтаксис:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
node --check web/app.js
```

# Изменения — Этап 5: DVR tab visibility fix (`hidden` attr)

## Что сделано
- В `/Users/mac/0009/astra/web/index.html` для DVR-блоков в `Edit Stream` добавлен HTML-атрибут `hidden`:
  - `#stream-dvr-config-block`
  - `#stream-dvr-remote-fields`
- В `/Users/mac/0009/astra/web/app.js` (`updateStreamDvrFields`) переключение видимости переведено на двойной режим:
  - `classList.toggle('hidden', ...)`
  - `element.hidden = ...`

## Почему так
- На инстансе `.2` блок настроек DVR оставался видимым при выключенных чекбоксах, потому что CSS-класс `hidden` не гарантировал `display:none` для этих контейнеров.
- Атрибут `hidden` уже поддерживается общим правилом `[hidden]{display:none!important}`, поэтому состояние стало детерминированным.

## Риски / ограничения
- Изменение затрагивает только вкладку DVR stream-editor и не меняет backend/API контракты.

## Как проверить
1) `node --check /Users/mac/0009/astra/web/app.js`
2) `/Users/mac/0009/astra/stream /Users/mac/0009/astra/scripts/tests/runtime_status_lite_fastpath_unit.lua`
3) `/Users/mac/0009/astra/stream /Users/mac/0009/astra/scripts/tests/stream_status_ids_api_unit.lua`
4) UI smoke:
   - открыть `Edit Stream -> DVR`;
   - при выключенных `Enable DVR recording` и `Enable DVR backup` конфиг-блок скрыт;
   - при включении — появляется;
   - при `DVR mode=remote` показывается только блок выбора DVR server.

# Изменения — Этап 5: Fix пустого PNGTS list запроса для New Stream

## Что сделано
- В `/Users/mac/0009/astra/web/app.js` (`loadPngtsExistingList`) добавлена проверка `stream.id`.
- Для нового потока без ID (`New Stream`) запрос `/api/v1/streams//pngts/list` больше не отправляется.
- Вместо этого список existing PNGTS очищается локально (`existingFiles=[]`) и рендерится пустое состояние.

## Почему так
- При открытии `New Stream` фронт создавал лишний 404/console error на endpoint с пустым stream id.
- Ошибка не критична для функционала, но засоряет консоль и мешает реальной диагностике UI.

## Риски / ограничения
- Изменение локальное для UI helper и не затрагивает backend/API.

## Как проверить
1) `node --check /Users/mac/0009/astra/web/app.js`
2) открыть `New Stream` и убедиться, что в консоли нет запроса `/api/v1/streams//pngts/list`.
3) `/Users/mac/0009/astra/stream /Users/mac/0009/astra/scripts/tests/runtime_status_lite_fastpath_unit.lua`
4) `/Users/mac/0009/astra/stream /Users/mac/0009/astra/scripts/tests/stream_status_ids_api_unit.lua`

# Изменения — Этап 5: Stream editor DVR UX simplification (local/remote)

## Что сделано
- В `/Users/mac/0009/astra/web/index.html` переработана вкладка `Edit Stream -> DVR`:
  - `Enable DVR recording` и `Enable DVR backup` переведены в switch-формат с короткими подсказками.
  - Добавлены явные runtime-подсказки:
    - `#stream-dvr-summary` (текущее состояние DVR-конфига),
    - `#stream-dvr-mode-hint` (пояснение выбранного режима).
- В `/Users/mac/0009/astra/web/app.js` расширена логика `updateStreamDvrFields()`:
  - динамический summary для `disabled/local/remote`;
  - предупреждение при `remote` без настроенного DVR server;
  - динамический placeholder пути архива от текущего `stream_id` (`/var/lib/stream/dvr/<id>`).
- Добавлены обработчики обновления summary/hints при изменениях:
  - `stream id`,
  - `dvr mode`,
  - `dvr server`,
  - `dvr path`,
  - DVR switches.
- В `/Users/mac/0009/astra/web/styles.css` добавлены стили для нового DVR-блока (`stream-dvr-*`) без изменения общих UI-контрактов.

## Почему так
- По требованиям UX нужно сделать DVR-конфиг в канале более простым и понятным:
  - включил,
  - выбрал local path или remote DVR server,
  - сохранил.
- Динамические подсказки снижают число ошибочных конфигов (особенно `remote` без выбранного DVR server) до нажатия `Save`.

## Риски / ограничения
- Изменения фронтовые; backend/API контракты не менялись.
- При очень кастомных темах возможно потребуется мелкая подстройка отступов для новых `stream-dvr-*` классов.

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) UI syntax/regression:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Runtime smoke tests:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
./stream scripts/tests/dvr_backup_api_unit.lua
./stream scripts/tests/servers_dvr_import_sync_unit.lua
```
4) Ручной сценарий:
- открыть `Edit Stream -> DVR`;
- включить/выключить оба DVR switches и проверить скрытие/показ блока настроек;
- выбрать `remote` и убедиться, что при отсутствии DVR server есть явное предупреждение;
- изменить `stream id` и проверить обновление placeholder пути локального архива.

# Изменения — Hotfix: safe `filter` / `filter~` normalization in `init_input`

## Что сделано
- В `/Users/mac/0009/astra/scripts/base.lua` устранён crash на старте для каналов с `pnr` и нестроковыми `filter`/`filter~`:
  - добавлен helper `normalize_filter_csv(value)`,
  - поддержаны варианты:
    - `nil` -> `nil`,
    - `string` -> `string.split(...)`,
    - `table` -> передаётся как есть.
- Убраны безусловные вызовы `string.split(conf.filter, ",")` и `string.split(conf["filter~"], ",")`, которые могли падать с ошибкой `string required`.

## Почему так
- На `.2` после restart `stream@prod` падал в цикле:
  - `[split] string required`
  - `scripts/base.lua -> init_input -> channel_prepare_input`.
- Причина: нестроковое значение `filter`/`filter~` в runtime-конфиге, при этом `split` ожидал строку.

## Риски / ограничения
- Поведение для корректных строковых фильтров не изменилось.
- Для некорректных scalar-типов (`number/boolean`) теперь значение игнорируется (safe fallback), а не валит процесс.

## Как проверить
1) Локально:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```
2) На `.2` после выкладки `scripts/base.lua`:
- `systemctl is-active stream@prod.service` -> `active`
- `curl http://127.0.0.1:9060/` -> `200`

# Изменения — Этап 5: `servers/dvr/import-streams` host/proto fallback for `origin_url`

## Что сделано
- В `/Users/mac/0009/astra/scripts/api.lua` добавлен helper:
  - `api._dvr_resolve_origin_url_from_request(request)`
  - источник: `x-forwarded-host` / `host` + `x-forwarded-proto` (fallback `http`)
  - нормализация через существующий `api._dvr_normalize_origin_base_url(...)`.
- В `api._servers_dvr_import_streams(...)` добавлен третий fallback резолва `origin_url`:
  1) `body.origin_url`
  2) `body.origin_server_id` -> settings servers entry
  3) HTTP request headers (`host/proto`)
- Обновлён таргетный тест:
  - `/Users/mac/0009/astra/scripts/tests/servers_dvr_import_sync_unit.lua`
  - добавлен сценарий импорта без `origin_url` с headers `host + x-forwarded-proto`,
  - проверка `origin_url` в ответе и `source_url` у импортируемого stream.

## Почему так
- В реальном UI/ops-флоу часто вызывают import без ручного `origin_url`.
- Новый fallback убирает лишнюю ручную настройку и делает `Import channels` более устойчивым за reverse proxy.

## Риски / ограничения
- Если proxy передаёт некорректный `Host`, импорт построит `source_url` на его основе.
- При отсутствии `origin_url`, `origin_server_id` и корректного `host` endpoint по-прежнему вернёт `400` (это ожидаемо).

## Как проверить
1) Unit/regression:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/servers_dvr_import_sync_unit.lua
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
node --check web/app.js
```
2) API smoke:
- выполнить `POST /api/v1/servers/dvr/import-streams` без `origin_url`;
- убедиться, что ответ `200` и содержит нормализованный `origin_url` из `Host` request.

# Изменения — Этап 5: Edit Stream → DVR backup maintenance actions wired

## Что сделано
- В `/Users/mac/0009/astra/web/app.js` завершена интеграция кнопок во вкладке `Edit Stream -> DVR`:
  - `Reset backup cursor`
  - `Rebuild backup cycle`
- Добавлены helper-функции для безопасного контекста действий:
  - `getEditorDvrActionContext()`
  - `resetEditorStreamDvrBackupCursor()`
  - `rebuildEditorStreamDvrBackupCycle()`
- Реализована корректная маршрутизация по режиму DVR:
  - `local` -> `/api/v1/dvr/backup/cursor/reset` и `/api/v1/dvr/backup/cycle/rebuild`
  - `remote` -> `/api/v1/servers/dvr/backup/cursor/reset` и `/api/v1/servers/dvr/backup/cycle/rebuild` (по одному `stream_id`)
- Добавлена защита UI/контекста:
  - действия доступны только для сохраненного локального stream (не `isNew`, не remote-stream editor),
  - в `remote` режиме кнопки активны только при выбранном DVR server.
- Добавлены явные `confirm`-диалоги и статус-сообщения по результату действий.

## Почему так
- Без wiring кнопки в `Edit Stream -> DVR` были визуально доступны, но не выполняли backend maintenance.
- Единый безопасный контекст исключает ошибочные вызовы API для неподходящего режима/несохраненного стрима.
- Разделение local/remote endpoint соответствует архитектуре distributed DVR и инвариантам admin-only операций.

## Риски / ограничения
- Для remote режима операции зависят от доступности выбранного `dvr_v1` сервера; при сетевой ошибке выполняется только статус-ошибка в UI.
- Для remote-stream editor действия намеренно недоступны (maintenance настраивается для локального origin stream editor).

## Как проверить
1) Сборка:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(command -v nproc >/dev/null 2>&1 && nproc || sysctl -n hw.ncpu)"
```
2) Синтаксис UI:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Таргетные тесты:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/dvr_backup_api_unit.lua
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```
4) Ручной сценарий:
- открыть `Edit Stream -> DVR` для локального сохраненного стрима;
- в `local` режиме нажать `Reset backup cursor` и `Rebuild backup cycle` -> получить успешный status;
- переключить на `remote`, выбрать DVR server и повторить -> запросы уходят через `/api/v1/servers/dvr/backup/*`;
- убедиться, что для `New stream` и remote-stream editor кнопки disabled.

# Изменения — Этап 5: Remote DVR channel ON/OFF switch with immediate API command

## Что сделано
- В `/Users/mac/0009/astra/web/app.js` доработан поток `Edit Stream -> DVR (remote mode)`:
  - свитч `Remote DVR channel` теперь отправляет команду сразу при переключении (`change`), без ожидания `Save`.
- Добавлены helper-функции:
  - `getDvrBulkErrors(payload)` — нормализует ошибки из `failed` и `errors`.
  - `dvrBulkErrorsAreOnlyStreamNotFound(errors, streamId)` — безопасный кейс для `OFF`, когда канала на DVR ещё нет.
  - `getEditorRemoteDvrProvisionContext()` — проверяет контекст (локальный сохранённый stream, remote mode, выбран DVR server, нет несохранённого rename ID).
  - `buildEditorDvrConfigForRemoteSync(remoteChannelEnabled)` — собирает payload из текущей формы.
  - `applyEditorRemoteDvrChannelEnabled(remoteChannelEnabled)` — единая точка немедленного remote DVR вызова.
- Обновлена `syncStreamDvrRemoteConfig(streamId, streamConfig, opts)`:
  - учитывает `dvr.remote_channel_enabled`;
  - `ON`: `import-streams` + `record/bulk`;
  - `OFF`: `record/bulk` с `record_enabled=false` (без принудительного import);
  - корректно обрабатывает bulk-ошибки remote DVR.
- В обработчике свитча добавлены:
  - rollback UI при ошибке,
  - статусы результата,
  - `boostStatusPolling()` и `scheduleStreamSync()` после успешной команды.

## Почему так
- Требование: свитч должен "непосредственно" отправлять API-команду и управлять каналом на удалённом DVR.
- Повторное использование `syncStreamDvrRemoteConfig` убирает дублирование логики между `Save` и немедленной командой из UI.
- Проверка контекста защищает от отправки команды при несохранённом rename stream ID.

## Риски / ограничения
- Немедленный вызов меняет состояние на удалённом DVR сразу, но локальная фиксация `remote_channel_enabled` остаётся в `Save` (свитч сообщает об этом в статусе).
- Для `OFF` при отсутствии канала на DVR ответ "stream not found" трактуется как допустимый (идемпотентное выключение).

## Как проверить
1) Build:
```bash
cd /Users/mac/0009/astra
./configure.sh && make -j"$(sysctl -n hw.ncpu)"
```
2) UI syntax:
```bash
cd /Users/mac/0009/astra
node --check web/app.js
```
3) Regression:
```bash
cd /Users/mac/0009/astra
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```
4) Manual:
- открыть локальный сохранённый stream -> вкладка DVR -> mode `remote`;
- выбрать DVR server, включить `Remote DVR channel` -> увидеть немедленный success status;
- выключить свитч -> увидеть немедленный status `disabled`;
- изменить `ID` stream в форме (без Save) и попробовать свитч -> получить требование сначала сохранить stream.
