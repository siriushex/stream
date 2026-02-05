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

### API
- `GET /api/v1/ai/logs?range=24h&level=ERROR&stream_id=...&limit=500`
- `GET /api/v1/ai/metrics?range=24h&scope=global|stream&id=<stream_id>&metric=bitrate_kbps`
- `GET /api/v1/ai/summary?range=24h` — возвращает последнюю агрегированную “сводку” (без AI).

Примечание: AI‑summary пока не подключён, эндпоинт отдаёт последний rollup snapshot.

## Настройки (через Settings API)
- `ai_enabled` — включить AI слой (bool).
- `ai_model` — модель (string).
- `ai_max_tokens` — лимит токенов.
- `ai_temperature` — температура.
- `ai_store` — хранение на стороне провайдера (по умолчанию false).
- `ai_allow_apply` — разрешить apply (по умолчанию false).
- `ai_telegram_allowed_chat_ids` — белый список чатов (список или строка).

AI‑эндпоинты отвечают только когда `ai_enabled=true`.

## Audit log
Для каждого AI‑плана пишется запись в `audit_log`:
- `action`: `ai_plan`
- `meta`: режим (`diff` или `prompt`), summary/diff.

## Валидация AI‑ответа
- Сервер валидирует `plan` (summary/ops/warnings) до применения.

## Переменные окружения
- `ASTRAL_OPENAI_API_KEY` или `OPENAI_API_KEY`.

## Важно
Apply доступен только при `ai_allow_apply=true` и использует backup + rollback.
