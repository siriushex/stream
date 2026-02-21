# Auth Backend Contract (Stream, current + target)

## 1. Цель

Дать единый контракт для интеграции Stream с внешними auth-порталами (Flussonic-like), чтобы:

- оператор в UI указывал в простом режиме только адрес портала;
- backend-проверка была предсказуемой и совместимой с Ministra/TMS;
- поведение по ошибкам/таймаутам было стабильным;
- QA имел фиксированные критерии и тест-кейсы.

---

## 2. Где это включается

### 2.1 Settings → Auth backends

Хранение: `settings.auth_backends` (объект по имени backend).

Пример структуры:

```json
{
  "main1": {
    "provider": "ministra",
    "portal_url": "https://name.com/stalker_portal",
    "mode": "parallel",
    "allow_default": false,
    "timeout_ms": 3000,
    "total_timeout_ms": 2000,
    "session_keys_default": ["ip", "name", "proto", "token", "header.x-playback-session-id"],
    "cache": {
      "default_allow_sec": 180,
      "default_deny_sec": 180
    },
    "rules": {
      "allow": { "token": [], "ip": [], "ua": [], "country": [] },
      "deny": { "token": [], "ip": [], "ua": [], "country": [] }
    },
    "backends": [
      {
        "url": "https://name.com/stalker_portal/server/api/chk_flussonic_tmp_link.php",
        "params": { "12345": "12345" }
      }
    ]
  }
}
```

### 2.2 Привязка к stream

В stream конфиге:

```json
{
  "on_play": "auth://main1"
}
```

Также поддерживается legacy direct URL(ы):

- `on_play: "http://portal1/check,http://portal2/check"`

---

## 3. Provider presets в UI (simple mode)

Текущее поведение UI:

- Ministra:
  - вход: URL портала или уже полный endpoint;
  - авто-нормализация в endpoint:
    - `/stalker_portal/server/api/chk_flussonic_tmp_link.php`.
- TMS:
  - авто-нормализация в endpoint:
    - `/api/drm/auth_token`.
- Generic:
  - endpoint используется как есть.

Поддержка suffix params в поле Portal address:

- `https://name.com/api/drm/auth_token 12345=12345;`

Это становится `backends[0].params`.

---

## 4. Request contract к portal backend

## 4.1 Play-mode (основной кейс)

HTTP метод: `GET`

Параметры query:

- `name` — stream id
- `ip` — client ip
- `proto` — `http_ts` / `hls` / др.
- `token` — токен из запроса по `token_source`
- `session_id` — детерминированный id сессии
- `request_type` — `open_session` или `update_session`
- `request_number` — номер вызова для session_id
- `stream_clients` — число клиентов по stream
- `total_clients` — число клиентов всего
- `duration` — длительность сессии в сек (для `update_session`)
- `bytes` — bytes counter (если доступен)
- `qs` — исходный query string
- `uri` — исходный URI
- `host` — host header
- `user_agent`
- `referer`
- `dvr` — `1`/`0`
- `playback_session_id` — из `x-playback-session-id` (если есть)

Плюс merge статических params из `backends[].params`.

## 4.2 Publish-mode

HTTP метод: `POST`

JSON body:

- `name`
- `ip`
- `proto`
- `token`
- `session_id`
- `request_type`
- `request_number`
- `uri`
- `user_agent`

---

## 5. Token extraction contract

Поддерживаемые `token_source`:

- `""` (legacy): query(`token_param`) → cookie `stream_token` → cookie `astra_token`
- `auto`: query(`token_param`) → header `Authorization` → cookies (`stream_token`, `astra_token`, `<token_param>`, `token`, `access_token`)
- `query:<name>`
- `header:<name>` (поддержка `Bearer ...` и `Token ...`)
- `cookie:<name>`

`token_param` по умолчанию: `token`.

---

## 6. Response contract от portal backend

## 6.1 Коды

- `200` → ALLOW
- `302` + `Location` → REDIRECT (в Stream это deny+redirect клиенту)
- `401/403/4xx` → DENY
- timeout / `0` / `5xx` → backend error (обрабатывается по fail-policy)

## 6.2 Заголовки (опционально)

- `x-authduration` или `x-auth-duration` → TTL ALLOW (сек)
- `x-userid` / `x-user-id`
- `x-max-sessions`
- `x-unique` (`1|true|yes`)

---

## 7. Decision model

## 7.1 Rules priority (до обращения к backend)

Порядок:

1. allow token
2. deny token
3. allow ip
4. deny ip
5. allow country
6. deny country
7. allow ua
8. deny ua

Если rule-match сработал, backend не вызывается.

## 7.2 Backend mode

- `parallel`:
  - allow/redirect могут завершить проверку раньше;
  - deny не имеет раннего short-circuit до завершения группы.
- `sequential`:
  - пробуем backend'ы по очереди;
  - `4xx` не останавливает цепочку (ищем allow/redirect дальше);
  - timeout/`5xx` → следующий backend.

## 7.3 Fail-policy

Если все backend'ы недоступны:

- `allow_default=true` (`fail-open`) → `ALLOW_DEFAULT`;
- `allow_default=false` (`fail-close`) → `DENY_DEFAULT`.

Если был stale ALLOW и backend временно down:

- grace allow (`backend_grace_allow`) на короткий TTL.

---

## 8. Session lifecycle (current behavior)

Что есть сейчас:

- `open_session` при первом check;
- `update_session` при recheck/stale refresh;
- recheck timer (опционально) для активных ALLOW-сессий.

Что пока отсутствует:

- явный dispatch `close_session` при disconnect.

Практический вывод для порталов:

- backend должен считать сессию завершённой по TTL/heartbeat timeout, а не ждать обязательного close callback.

---

## 9. HLS specifics

- Для HLS при включённом rewrite:
  - token/session_id добавляются в playlist URI.
- Для клиента выставляются cookies:
  - `stream_token`
  - `stream_sid`

Это нужно для порталов/плееров, где часть запросов идёт без query token.

---

## 10. Минимальный UX-контракт (как у Flussonic-like)

Simple mode (обязательный продуктовый путь):

1. Ввод только `Portal address`.
2. Авто-детект provider.
3. Авто-построение endpoint.
4. Скрытый advanced (rules/cache/multi-backend/mode/timeouts).
5. Кнопка `Test` и человекочитаемый диагноз.

---

## 11. Full target (для “полноценной реализации”)

Для полной совместимости с крупными порталами:

1. Добавить optional `close_session` callback на disconnect.
2. Добавить per-backend retry policy (attempts/backoff/jitter).
3. Добавить schema-validation ответа backend (строгий parse headers).
4. Добавить portal profile packs (Ministra/TMS версии API).
5. Добавить диагностику в UI: request/response trace (masked), last deny reason.

Эти пункты не ломают текущий контракт и могут вводиться по feature-flag.

---

## 12. Ограничения и гарантии

- Stream не должен модифицировать remote portal payload “наугад”.
- При ошибках auth backend Stream не должен падать; только deny/redirect/fallback согласно policy.
- Все секреты (token/password) в логах должны быть mask/redacted.
