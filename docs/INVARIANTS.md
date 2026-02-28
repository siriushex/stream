# INVARIANTS

Инварианты обязательны для всех изменений в коде и документации.

## 1. Dataplane и стабильность
1. Стабильность вещания всегда выше удобства UI/аналитики.
2. Изменения control-plane не должны менять dataplane-поведение без явного требования и тестов.
3. Любой degrade режим должен деградировать в пользу сохранения вещания (допустима потеря метрик, недопустима остановка потока).

## 2. API и совместимость
1. `/api/v1/*` контракты изменяются только с обратной совместимостью или явной миграцией.
2. Ошибки API должны возвращаться JSON-ответом с корректным HTTP-кодом, без скрытых redirect/auth loops.
3. Любые изменения форматов status/series требуют обновления UI и unit-тестов.

## 3. Конфиг и миграции
1. Изменения schema проходят через `config.lua` migrations; ручные ad-hoc SQL в рантайме запрещены.
2. Миграции должны быть идемпотентны и безопасны для повторного запуска.
3. Для remote Astra/legacy недопустимо записывать поля, которые целевой API не поддерживает.

## 4. Auth и безопасность
1. В production нельзя оставлять bootstrap credentials (`admin/admin`) без смены пароля.
2. Secrets/tokens/private keys/diagnostic dumps не попадают в git; контроль через `scripts/ci/check_sensitive_data.sh`.
3. Любой auth bypass допускается только через явный setting и документирован как исключение.
4. Логи и UI не должны раскрывать токены/пароли в открытом виде.

## 5. Observability
1. Master switch `observability_enabled` — единственный флаг, разрешающий сбор.
2. При `observability_enabled=false` сбор не выполняется, чтение истории разрешено (read-only mode).
3. Observability не должна создавать lock-storm и блокировать runtime event loop.
4. High-res/collector очереди обязаны иметь bounded limits и защиту от перегруза.

## 6. DVB auto-search/full-scan
1. Одновременно выполняется максимум один autoswitch task глобально.
2. Переключение выполняется только на free FE; захват busy FE запрещен.
3. При массовой деградации используется очередь с anti-stampede и circuit breaker.
4. Type-flip recovery не должен запускаться бесконечным циклом; после цикла счетчики/окна должны корректно сбрасываться.
5. Full scan не должен автоматически создавать все каналы без явного выбора оператора.

## 7. UI/runtime truthfulness
1. UI должен показывать runtime-статус и counters без долгого stale состояния.
2. Dashboard polling должен быть dedup/in-flight safe, с pause на hidden tab.
3. Статусы ошибок на потоках должны отражать реальный тип/счетчик (`CC`/`PES`), без расплывчатых меток.

## 8. DVR archive/backup (distributed)
1. `dvr.segment_sec` фиксирован: `3600` секунд для всех новых сегментов.
2. Внутри одного backup-cycle сегмент не может быть проигран повторно (anti-repeat).
3. `ingest-state` идемпотентен по `state_seq`: seq `<= last_state_seq` игнорируется.
4. В режиме `DVR_ACTIVE` запись канала на DVR должна быть `recording_paused=true`, в `LIVE` — `false`.
5. Недоступность DVR не должна останавливать вещание origin: допускается только деградация DVR-синка (outbox retry).
6. В локальном режиме `/dvr/play/<stream_id>` обязан брать источник из `dvr_segments` (cycle/cursor), а не из live `/play`.
7. В локальном режиме прогресс проигрывания сегмента должен фиксироваться при disconnect и использоваться для cursor-resume.
8. Origin `dvr_remote_outbox` должен быть bounded и не копить дубликаты `ingest_state` при недоступном DVR.
9. Для `dvr_v1` health distributed sync должен быть наблюдаем через `/api/v1/servers/status` (`dvr_sync` в ответе).
10. Origin remote backup maintenance (`/api/v1/servers/dvr/backup/*`) выполняется только admin-only и только по явному списку `stream_ids` (без скрытого "apply all").
11. Local DVR backup maintenance bulk (`/api/v1/dvr/backup/*-bulk`) выполняется только admin-only и только по явному списку `stream_ids`.
12. На DVR-ноде запись из `dvr_streams` должна работать по `source_url` даже при пустом `runtime.streams`; pause/resume writer-а управляется только `record_enabled`/`recording_paused`.
13. На DVR-ноде импортированный `dvr_streams` без локального `config.streams` ряда обязан быть видимым через `/api/v1/streams` и `/api/v1/streams/:id` (`dvr_only=true`), иначе Dashboard теряет управляемость удалённых DVR-каналов.
14. Для distributed DVR import (`/api/v1/servers/dvr/import-streams`) source URL должен поддерживать auth fallback: при отсутствии play-token использовать валидные basic creds, чтобы удалённый DVR мог читать origin `/play/{id}` без ручной правки URL.
15. DVR backup start policy:
    - `sequential` всегда начинает с первого `pending` сегмента текущего цикла;
    - `time_offset` применяется только при инициализации нового цикла (выбор сегмента по времени);
    - при `cycle exhausted` rebuild стартует с oldest сегмента независимо от `time_offset`.
16. Distributed DVR import не должен допускать self-origin loop:
    - `origin_url` не может указывать на тот же host:port, что и целевой `dvr_v1` сервер, если явно не разрешено оператором.
17. Remote DVR writer при постоянных source open-fail обязан использовать retry backoff, чтобы не создавать retry/log storm.
18. `Type=DVR` input в stream editor должен сериализоваться как HTTP endpoint с `input_type=dvr` metadata; backend обязан использовать эти metadata для авто-инициализации remote DVR binding только на валидный `dvr_v1` server.
19. Если `config.dvr.remote_stream_id` задан, remote DVR import/record/link операции должны использовать именно его (а не локальный `stream_id`), сохраняя `source_url` от origin stream.
20. DVR playback state isolation:
    - internal failover playback (`/dvr/internal/play/*` или legacy `/dvr/play/*?internal=1`) может двигать backup cursor/cycle,
    - пользовательский просмотр архива (`/dvr/archive/play/*`) не должен менять backup cursor/cycle.

## 9. Тестируемость и DoD
1. Для каждого изменения обязателен воспроизводимый набор проверок (build/lint/tests).
2. Рискованные изменения должны иметь таргетные unit/integration тесты.
3. `AI_NOTES.md` обновляется на каждом этапе: что сделано, почему, риски, как проверить.
