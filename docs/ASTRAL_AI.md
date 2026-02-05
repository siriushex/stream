# AstralAI (draft)

Цель: безопасные массовые изменения конфигурации, AI‑мониторинг и команды через Telegram.

## Принципы безопасности
- Всегда: backup → validate → diff → apply → verify → rollback при ошибке.
- Нет “тихих” изменений: любой apply только через инструментальный слой.
- AI‑модуль по умолчанию **выключен**.
- OpenAI ключ не хранится в репозитории и не логируется.

## Этапы внедрения
### Phase 0 — Scaffolding (готово)
- Каркас модулей: `ai_runtime.lua`, `ai_tools.lua`, `ai_prompt.lua`, `ai_telegram.lua`.
- OpenAI клиент вынесен в `ai_openai_client.lua`.
- Генератор графиков вынесен в `ai_charts.lua`.
- Настройки `ai_*` в settings, apply разрешён только при `ai_allow_apply=true`.
- API endpoints:
  - `POST /api/v1/ai/plan`
  - `POST /api/v1/ai/apply`
  - `GET /api/v1/ai/jobs`
  - `POST /api/v1/ai/telegram` (заглушка)

### Phase 1 — Safe planning
- Структурированный план изменений (JSON schema).
- Валидатор до apply.
- Доступен diff и audit‑лог.

Статус: выполнено.
- Локальный режим: `/api/v1/ai/plan` принимает `proposed_config` и возвращает diff.
- AI режим: `/api/v1/ai/plan` принимает `prompt` и возвращает job с `plan` (без apply).

Пример (локальный diff):
```json
{
  "proposed_config": { "settings": { "http_play_stream": true } }
}
```

Пример (AI план):
```json
{
  "prompt": "Переименуй все стримы с префиксом test_ на prod_."
}
```

## Валидация входа
- Разрешено только одно из полей: `prompt` **или** `proposed_config`.
- `prompt` должен быть непустой строкой.
- `proposed_config` должен быть объектом (валидируется через `config.validate_payload`).

### Phase 2 — Controlled apply (частично)
- `/api/v1/ai/apply` принимает `proposed_config` (и optional `mode`/`comment`).
- Делает backup → validate → diff → apply → runtime reload.
- При ошибке: rollback на LKG snapshot.
- Apply доступен при `ai_enabled=true` и `ai_allow_apply=true` (без ключа).

Пример (apply):
```json
{
  "proposed_config": { "settings": { "http_play_stream": true } },
  "mode": "merge",
  "comment": "ai apply test"
}
```

### Phase 3 — Monitoring & Telegram
- AI‑alerts.
- Команды через Telegram.
- Политики доступа и guardrails.

## Observability (logs + metrics rollup)
Встроенный сбор лог‑событий и агрегированных метрик для отчётов и AI‑summary.

### Настройки
- `ai_logs_retention_days` — хранение лог‑событий (дни, 0 = выключено).
- `ai_metrics_retention_days` — хранение метрик (дни, 0 = выключено).
- `ai_rollup_interval_sec` — период агрегации (сек, минимум 30).
- `ai_metrics_on_demand` — метрики считаются по запросу (логи + runtime snapshot), без фонового rollup.
- `ai_metrics_cache_sec` — TTL кэша on‑demand метрик (сек), по умолчанию 30.

### Минимальная нагрузка (по умолчанию)
- При `ai_metrics_on_demand=true` фоновый rollup **не запускается**.
- В этом режиме `ai_metrics_retention_days` принудительно считается как `0` (метрики не сохраняются).
- Метрики рассчитываются только по запросу `/api/v1/ai/metrics` и кэшируются на короткое время.

## AI Context (logs + CLI snapshots)
AI‑запросы могут включать контекст из логов и CLI‑инструментов **по запросу**:
- `--stream` (runtime snapshot)
- `--analyze` (MPEG‑TS анализ)
- `--dvbls` (список DVB‑адаптеров)
- `--femon` (сигнал DVB)

Примечание: `stream` и `dvbls` берутся из текущего runtime/модуля (эквивалентно CLI),
чтобы не запускать отдельный процесс и не увеличивать нагрузку.

Контекст включается параметрами `include_logs` и `include_cli` в `/api/v1/ai/summary` и `/api/v1/ai/plan`.

### Авто‑выбор контекста (минимальная нагрузка)
- Если `include_logs`/`include_cli` не переданы, AstralAI **сам** решает, что добавить,
  исходя из текста запроса:
  - диагностические запросы → добавляются логи;
  - запросы про DVB/scan/lock → добавляются `dvbls`/`femon`;
  - запросы про PIDs/TS → добавляется `analyze`.

См. также: `docs/CLI.md`.

### Пример: AI summary с CLI‑контекстом
```bash
curl -s "http://127.0.0.1:8000/api/v1/ai/summary?range=24h&ai=1&include_logs=1&include_cli=stream,dvbls&stream_id=abc" \
  -H "Authorization: Bearer <token>"
```

### Пример: AI plan с CLI‑контекстом
```bash
curl -s "http://127.0.0.1:8000/api/v1/ai/plan" \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Проверь поток abc","include_logs":true,"include_cli":["stream","dvbls"],"stream_id":"abc"}'
```

### Настройки CLI (low‑load)
- `ai_cli_timeout_sec` — таймаут CLI команд (сек), по умолчанию 3.
- `ai_cli_max_concurrency` — максимум CLI задач одновременно (по умолчанию 1).
- `ai_cli_cache_sec` — TTL кэша CLI результатов (по умолчанию 60).
- `ai_cli_output_limit` — лимит вывода (байт), по умолчанию 8000.
- `ai_cli_bin_path` — путь к бинарю `astral` (опционально).
- `ai_cli_allow_no_timeout` — разрешить запуск без `timeout` (false по умолчанию).

## Модель OpenAI по умолчанию и fallback
- Если `ai_model` пустой, используется **`gpt-5.2`** по умолчанию.
- При ошибке `model_not_found` выполняется **одна** попытка с fallback:
  1. `gpt-5-mini`
  2. `gpt-4.1`
- Для UI это означает, что можно оставить поле модели пустым, и система выберет безопасный дефолт.

## Диаграммы и графики (AI)
- Если запрос требует графики/диаграммы, AI может вернуть поле `charts` (line/bar + series).
- Рендеринг **детерминированный**: UI рисует графики локально (spec), либо делает PNG (image).
- Используется та же модель, что в `ai_model` (отдельной модели не требуется).

### API
- `GET /api/v1/ai/logs?range=24h&level=ERROR&stream_id=...&limit=500`
- `GET /api/v1/ai/metrics?range=24h&scope=global|stream&id=<stream_id>&metric=bitrate_kbps`
- `GET /api/v1/ai/summary?range=24h` — возвращает последнюю агрегированную “сводку” (без AI).

### Telegram summary
- Планировщик отправляет ежедневную/еженедельную/ежемесячную сводку.
- Основано на rollup‑метриках Observability.
- Доп. настройка: `telegram_summary_include_charts` (PNG‑график).
- Если включён AI (`ai_enabled` + ключ + модель), отправляется дополнительный AI‑summary.

#### Telegram команды (AI)
- `/ai summary [24h|7d|30d]` — краткая сводка.
- `/ai report stream=<id> [range=24h]` — отчёт по потоку.
- `/ai suggest` — безопасный план улучшений (без apply).
- `/ai apply plan_id=<id>` — apply для любого плана (prompt или proposed_config), если разрешён и plan готов.
- `/ai confirm <token>` — подтверждение apply (token выдаётся при `/ai apply`).
- При `ai_metrics_on_demand=true` команды используют on‑demand метрики (без фонового rollup).

Примечание: `GET /api/v1/ai/summary?ai=1` возвращает AI‑summary при включённом AI (иначе — rollup snapshot).

## Настройки (через Settings API)
- `ai_enabled` — включить AI слой (bool).
- `ai_model` — модель (string).
- `ai_max_tokens` — лимит токенов.
- `ai_temperature` — температура.
- `ai_store` — хранение на стороне провайдера (по умолчанию false).
- `ai_allow_apply` — разрешить apply (по умолчанию false).
- `ai_telegram_allowed_chat_ids` — белый список чатов (список или строка).
- `ai_api_key` / `ai_api_key_masked` / `ai_api_key_set` — ключ (маска + флаг).
- `ai_api_base` — базовый URL API.

AI‑эндпоинты отвечают только когда `ai_enabled=true`.

## AstralAI Chat (UI)
Вкладка **Help → AstralAI Chat**:
- Чат‑интерфейс в стиле ChatGPT.
- Вложения (изображения) отправляются как input_image (max 2 файла).
- Чекбоксы:
  - **Include logs** — подтянуть ошибки из логов (по запросу).
  - **CLI tools**: `--stream`, `--dvbls`, `--analyze`, `--femon` (только при запросе).
- Apply доступен только если `ai_allow_apply=true`.
 - Для чата включён `preview_diff=true`, чтобы показывать предварительный diff.
- Команда `help` или `/help` возвращает встроенный список подсказок (без вызова OpenAI).

## Audit log
Для каждого AI‑плана пишется запись в `audit_log`:
- `action`: `ai_plan`
- `meta`: режим (`diff` или `prompt`), summary/diff.

## Валидация AI‑ответа
- Сервер валидирует `plan` (summary/ops/warnings) до применения.

## Переменные окружения
- `ASTRAL_OPENAI_API_KEY` или `OPENAI_API_KEY`.
- `LLM_PROXY_PRIMARY` / `LLM_PROXY_SECONDARY` — HTTP‑прокси для OpenAI запросов (опционально).
  - Пример: `http://user:pass@host:port`
  - Если задано, AstralAI отправляет запросы через `curl` с proxy (без логирования секретов).

## Важно
Apply доступен только при `ai_allow_apply=true` и использует backup + rollback.
