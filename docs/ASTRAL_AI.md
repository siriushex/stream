# AstralAI (draft)

Цель: безопасные массовые изменения конфигурации, AI‑мониторинг и команды через Telegram.

## Принципы безопасности
- Всегда: backup → validate → diff → apply → verify → rollback при ошибке.
- Нет “тихих” изменений: любой apply только через инструментальный слой.
- AI‑модуль по умолчанию **выключен**.
- OpenAI ключ не хранится в репозитории и не логируется.

## Этапы внедрения
### Phase 0 — Scaffolding (текущий этап)
- Каркас модулей: `ai_runtime.lua`, `ai_tools.lua`, `ai_prompt.lua`, `ai_telegram.lua`.
- Настройки `ai_*` в settings, apply‑операций нет.
- API endpoints:
  - `POST /api/v1/ai/plan` (заглушка)
  - `POST /api/v1/ai/apply` (заглушка)
  - `GET /api/v1/ai/jobs`
  - `POST /api/v1/ai/telegram` (заглушка)

### Phase 1 — Safe planning
- Структурированный план изменений (JSON schema).
- Валидатор до apply.
- Доступен diff и audit‑лог.

Статус: выполняется.
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

### Phase 2 — Controlled apply
- Apply + rollback.
- UI панель для предпросмотра.

### Phase 3 — Monitoring & Telegram
- AI‑alerts.
- Команды через Telegram.
- Политики доступа и guardrails.

## Настройки (через Settings API)
- `ai_enabled` — включить AI слой (bool).
- `ai_model` — модель (string).
- `ai_max_tokens` — лимит токенов.
- `ai_temperature` — температура.
- `ai_store` — хранение на стороне провайдера (по умолчанию false).
- `ai_allow_apply` — разрешить apply (по умолчанию false).
- `ai_telegram_allowed_chat_ids` — белый список чатов (список или строка).

AI‑эндпоинты отвечают только когда `ai_enabled=true`.

## Переменные окружения
- `ASTRAL_OPENAI_API_KEY` или `OPENAI_API_KEY`.

## Важно
Этот модуль не делает прямых write‑операций. Применение изменений будет доступно только после реализации Phase 2.
