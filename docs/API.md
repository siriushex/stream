# Stream API (v1)

Base URL: `http://<host>:<port>/api/v1`  
Формат: JSON (кроме случаев, где явно указано: XML/Prometheus/text).

## Общие правила
- Все пути ниже указаны относительно Base URL. Пример: `GET /health` -> `GET /api/v1/health`.
- Почти все эндпоинты требуют сессию (Bearer или cookie). Исключения:
  - `POST /auth/login`
  - `POST /auth/logout` (идемпотентный)
  - `GET /health`
  - `OPTIONS *`
- Ошибки обычно возвращаются как `{ "error": "<message>" }` с соответствующим HTTP кодом.

## Auth
### `POST /auth/login`
Body:
```json
{ "username": "admin", "password": "admin" }
```
Response:
```json
{ "token": "<token>", "user": { "id": 1, "username": "admin", "is_admin": 1 } }
```
Также устанавливает cookie `stream_session=<token>`.

### `POST /auth/logout`
Идемпотентный logout. Если сессия существует, удаляет её. Можно вызывать с Bearer или cookie.

**Способы авторизации**
- `Authorization: Bearer <token>`  
- Cookie `stream_session` (CSRF нужен для state‑change).

**CSRF**
- Для `POST/PUT/DELETE/PATCH` с cookie‑auth нужен `X-CSRF-Token: <session token>`.
- Для Bearer‑auth CSRF не требуется.

## Health
### Без auth
- `GET /health`

### Требует auth
- `GET /health/process`
- `GET /health/inputs`
- `GET /health/outputs`

## Streams
- `GET /streams`
- `POST /streams`
- `GET /streams/{id}`
- `PUT /streams/{id}`
- `DELETE /streams/{id}`
- `POST /streams/{id}/preview/start`
- `POST /streams/{id}/preview/stop`
- `POST /streams/analyze`
- `POST /streams/{id}/analyze`
- `GET /streams/analyze/{id}`

**Upsert формы (совместимость)**
- Рекомендуемый формат: `{ "id": "...", "enabled": true|false, "config": { ... } }`.
- Legacy формат: тело запроса может быть самим stream config (поля на верхнем уровне), `id` берётся из URL или body.
- `enabled-only patch`: `PUT /streams/{id}` с телом `{ "enabled": false }` (или `{ "enabled": true }`) не требует `config` и не затирает существующий config.
- Для update: если `enabled` не передан, текущее значение `enabled` сохраняется (защита от случайного re-enable).

## Adapters
- `GET /adapters`
- `POST /adapters`
- `GET /adapters/{id}`
- `PUT /adapters/{id}`
- `DELETE /adapters/{id}`

**Upsert формы (совместимость)**
- Рекомендуемый формат: `{ "id": "...", "enabled": true|false, "config": { ... } }`.
- Legacy формат: тело запроса может быть самим adapter config (поля на верхнем уровне), `id` берётся из URL или body.
- `enabled-only patch`: `PUT /adapters/{id}` с телом `{ "enabled": false }` (или `{ "enabled": true }`) не требует `config` и не затирает существующий config.
- Для update: если `enabled` не передан, текущее значение `enabled` сохраняется (защита от случайного re-enable).

## Status
- `GET /stream-status`
- `GET /stream-status/{id}`
- `GET /adapter-status`
- `GET /adapter-status/{id}`

## MPTS
- `POST /mpts/scan`

## DVB
- `GET /dvb-adapters`
- `POST /dvb-scan` (admin)
- `GET /dvb-scan/{id}` (admin)

## Splitters (HLSSplitter)
- `GET /splitters`
- `POST /splitters`
- `GET /splitters/{id}`
- `PUT /splitters/{id}`
- `DELETE /splitters/{id}`
- `GET /splitters/{id}/links`
- `POST /splitters/{id}/links`
- `PUT /splitters/{id}/links/{link_id}`
- `DELETE /splitters/{id}/links/{link_id}`
- `GET /splitters/{id}/allow`
- `POST /splitters/{id}/allow`
- `DELETE /splitters/{id}/allow/{rule_id}`
- `POST /splitters/{id}/start`
- `POST /splitters/{id}/stop`
- `POST /splitters/{id}/restart`
- `POST /splitters/{id}/apply-config`
- `GET /splitters/{id}/config` (XML)
- `GET /splitter-status`
- `GET /splitter-status/{id}`

## Buffer (HTTP TS buffer)
- `GET /buffers/resources`
- `POST /buffers/resources`
- `GET /buffers/resources/{id}`
- `PUT /buffers/resources/{id}`
- `DELETE /buffers/resources/{id}`
- `GET /buffers/resources/{id}/inputs`
- `POST /buffers/resources/{id}/inputs`
- `PUT /buffers/resources/{id}/inputs/{input_id}`
- `DELETE /buffers/resources/{id}/inputs/{input_id}`
- `GET /buffers/allow`
- `POST /buffers/allow`
- `DELETE /buffers/allow/{rule_id}`
- `POST /buffers/reload`
- `POST /buffers/{id}/restart-reader`
- `GET /buffer-status`
- `GET /buffer-status/{id}`

## Users (admin)
- `GET /users`
- `POST /users`
- `PUT /users/{username}`
- `POST /users/{username}/reset`

## Sessions
- `GET /sessions`
- `DELETE /sessions/{id}`
- `GET /auth-debug/session` (admin)

## Logs / Audit
- `GET /logs`
- `GET /access-log`
- `GET /audit` (admin)

## Metrics / Alerts
- `GET /metrics` (JSON)
- `GET /metrics?format=prometheus`
- `GET /alerts`

## Transcode
- `GET /transcode-status`
- `GET /transcode-status/{id}`
- `POST /transcode/{id}/restart`

## Tools / License
- `GET /tools`
- `GET /license`

## Config / Import / Export
- `POST /reload`
- `POST /restart?mode=soft|hard`
- `POST /config/validate`
- `GET /config/revisions`
- `DELETE /config/revisions`
- `POST /config/revisions/{id}/restore`
- `DELETE /config/revisions/{id}`
- `POST /import` (merge|replace)
- `GET /export` (admin)

## Settings
- `GET /settings` (секреты маскированы)
- `PUT /settings`

## Telegram
- `POST /notifications/telegram/test`
- `POST /notifications/telegram/backup`
- `POST /notifications/telegram/summary`

## AI / Observability (admin)
- `GET /ai/logs`
- `GET /ai/metrics`
- `GET /ai/summary`
- `GET /ai/jobs`
- `POST /ai/plan`
- `POST /ai/apply`
- `POST /ai/telegram`

**AI summary параметры**
- `include_logs=1|0`
- `include_cli=stream,dvbls,analyze,femon`
- `stream_id`, `input_url`, `femon_url`

**AI plan параметры (доп. контекст)**
- `include_logs=1|0`
- `include_cli=stream,dvbls,analyze,femon`
- `stream_id`, `input_url`, `femon_url`

### Пример curl (AI summary + CLI)
```bash
curl -s "http://127.0.0.1:8000/api/v1/ai/summary?range=24h&ai=1&include_logs=1&include_cli=stream,dvbls&stream_id=abc" \
  -H "Authorization: Bearer <token>"
```

### Пример curl (AI plan + CLI)
```bash
curl -s "http://127.0.0.1:8000/api/v1/ai/plan" \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"Проверь поток abc","include_logs":true,"include_cli":["stream","dvbls"],"stream_id":"abc"}'
```

См. также CLI режимы в `docs/CLI.md`.

## Remote Servers (admin)
- `GET /servers/status`
- `POST /servers/test`
- `POST /servers/pull-streams`
- `POST /servers/import`
