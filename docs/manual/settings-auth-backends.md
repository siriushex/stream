# Settings → Auth backends (порталы)

Auth backend — это “проверка доступа” перед выдачей потока.
Stream Hub делает HTTP запрос в ваш портал/скрипт и получает ответ: **разрешить / запретить / редирект**.

Это похоже на Flussonic `auth_backend` и подходит для порталов Stalker/Ministra и подобных.

!!! tip "Если auth не включён"
    Ничего не меняется. Потоки работают как раньше.

## Где настраивается

1. **Settings → Auth backends** — общий список backend’ов (по имени).
2. **Edit stream → Auth** — включение на конкретном стриме (on_play, session_keys, token source).

## Auth backend по имени (рекомендуется)

1. Откройте **Settings → Auth backends**.
2. Нажмите **NEW BACKEND**.
3. Заполните:
   - **ID** — имя backend’а (например `main1`).
   - **Default** — что делать, если все порталы “упали”.
     `Allow` = fail‑open, `Deny` = fail‑closed.
   - **Backends** — URL(ы) портала. По одному в строке.

После этого на стриме укажите:

```text
auth://main1
```

## Несколько порталов (параллельно)

В одном backend можно указать несколько URL.
Stream Hub опрашивает их параллельно и принимает решение:

- **200** хотя бы от одного → `ALLOW`
- **403/4xx** (и нет 200) → `DENY`
- **302 + Location** → `REDIRECT`
- все **timeout/5xx** → `Default` (Allow/Deny)

## Режим опроса (parallel / sequential)

По умолчанию backend работает в режиме **parallel**.

Есть режим **sequential** (по очереди):
- если портал вернул `401/403` — Stream Hub пробует следующий URL,
- если хотя бы один вернул `200` — доступ разрешён,
- если все вернули `401/403` — доступ запрещён,
- если все “упали” (timeout/5xx) — используется `Default`.

## Правила allow/deny (до порталов)

В backend можно задать быстрые правила, чтобы:
- не дергать порталы на “явно разрешённых” токенах/IP,
- сразу отсеивать “явно запрещённые”.

Поддерживаются поля:
- `token`
- `ip` (включая CIDR, например `10.0.0.0/24`)
- `ua` (подстрока User‑Agent)
- `country` (двухбуквенный код, если прокси/edge его добавляет)

Приоритет:

1. allow token
2. deny token
3. allow ip
4. deny ip
5. allow country
6. deny country
7. allow ua
8. deny ua

## Кэширование (важно для нагрузки)

Stream Hub кэширует решение backend’а на время:
- `allow ttl` — сколько секунд хранить `ALLOW`
- `deny ttl` — сколько секунд хранить `DENY`

Пока кэш не истёк — порталы **не опрашиваются**.

### Перепроверка (update_session)

Когда TTL истёк, Stream Hub делает перепроверку:
- если backend доступен — обновляет разрешение,
- если backend недоступен, но сессия была `ALLOW` — кратко сохраняет прошлое решение и пробует снова.

Опции (в Settings → General / JSON settings):

- `auth_stale_grace_sec` (по умолчанию 30) — сколько секунд держать “протухшее” решение при проблемах с порталом.
- `auth_recheck_interval_sec` (по умолчанию 0) — таймер перепроверки активных сессий.
  Если поставить `30`, то Stream Hub будет перепроверять активные HTTP‑TS сессии примерно раз в 30 секунд.

## Session keys (стабильная “сессия”)

`session_keys` управляет тем, как считается `session_id`.
Это важно, когда портал ограничивает “сессии” или ожидает стабильный id.

По умолчанию используются ключи:

```text
ip, name, proto, token
```

Можно добавить заголовок:

```text
header.x-playback-session-id
```

Это нужно для некоторых STB/порталов.

## Что уходит в портал (параметры запроса)

Для on‑play отправляется GET с параметрами в стиле Flussonic:

- `name` (stream id)
- `proto` (play/hls/http-ts/…)
- `ip`
- `token`
- `session_id`
- `request_type` (сейчас `open_session`)
- `request_number`
- `stream_clients`, `total_clients`
- `qs`, `uri`, `host`, `user_agent`, `referer`
- `dvr` (0/1)

!!! note "Про совместимость"
    Если ваш портал ожидает другой путь/параметры — используйте прямой URL (см. ниже) или адаптируйте backend.

## Прямой URL на стриме (без имени)

В поле `On‑play backend override` можно указать URL напрямую.
Также можно указать несколько URL через запятую или новую строку.

Пример (Stalker/Ministra‑подобный скрипт):

```text
http://portal.example.com/stalker_portal/server/api/chk_flussonic_tmp_link.php
```

## Быстрая проверка

1. Включите auth на стриме:
   - **Edit stream → Auth → Mode** → `Named auth backend`
   - **Auth backend** → `main1`
   - (опционально) **Auth override (legacy)** оставить `Inherit`
2. Попробуйте открыть:

```bash
curl -i "http://SERVER:9060/play/STREAM_ID?token=TEST"
```

Ожидаемо:
- `200` → доступ есть
- `403` → доступ запрещён
- `302` + `Location` → редирект на другой URL

## Token source (query/header/cookie)

По умолчанию Stream Hub берёт token из:
- query параметра (обычно `token`)
- cookie `astra_token`

Если портал/клиент передаёт token иначе, задайте **Edit stream → Auth → Token source**:
- `Query param` (например `query:token`)
- `Header` (например `header:Authorization`, поддерживается `Bearer <token>`)
- `Cookie` (например `cookie:stb_token`)
- `Auto` (попробовать query + header + cookie)
