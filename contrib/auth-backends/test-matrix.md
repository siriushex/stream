# Auth Backends Test Matrix

## 1. Unit tests (Lua)

Базовый файл:

- `/Users/mac/0009/astra/scripts/tests/auth_backend_unit.lua`

## 1.1 Уже покрыто

- Rule allow token bypass.
- Parallel mode: deny + allow => allow.
- Sequential mode: 403 then 200 => allow.
- All backends down + allow_default=true => allow_default.
- Redirect 302 + Location.
- `session_keys_default` влияет на session_id.
- `token_source` query/header/cookie + Bearer parsing.

## 1.2 Добавить (обязательно)

1. `all backends down + allow_default=false` => `DENY_DEFAULT`.
2. `parallel`: redirect vs allow race (должен побеждать redirect или строго задокументированный приоритет).
3. `total_timeout_ms` budget enforcement.
4. `auth_backend_max_concurrency` overload path (`backend_overload`).
5. `x-max-sessions` + `auth_overlimit_policy=deny_new`.
6. `x-max-sessions` + `auth_overlimit_policy=kick_oldest`.
7. `x-unique` multi-session kick behavior.
8. stale entry + backend down => grace allow.
9. `auth_allow_no_token=false` + no token => deny `no_token`.
10. `rules` priority exact order regression test.

---

## 2. API/UI integration tests

## 2.1 Settings → Auth backends

1. Create backend in simple mode:
   - Portal URL Ministra -> endpoint resolves correctly.
   - Portal URL TMS -> endpoint resolves correctly.
2. Save + reload page:
   - backend сохраняется без потери полей.
3. Edit backend:
   - advanced fields не сбрасываются.
4. Delete backend:
   - stream с `on_play=auth://id` показывает понятную ошибку `backend_missing`.

## 2.2 Stream Auth tab

1. Named backend selected -> stream save -> config contains `on_play=auth://...`.
2. Token source variants:
   - `query:token`
   - `header:authorization`
   - `cookie:stream_token`
3. Session keys override roundtrip.

## 2.3 Playback flow

1. `/play/<id>` with valid token -> 200 stream.
2. invalid token -> 403.
3. backend 302 -> client receives redirect.
4. HLS playlist:
   - token rewrite present.
   - cookies `stream_token`/`stream_sid` set.

---

## 3. Portal compatibility tests

## 3.1 Ministra middleware

Mock endpoint: `/stalker_portal/server/api/chk_flussonic_tmp_link.php`.

Scenarios:

- allow 200.
- deny 403.
- redirect 302.
- timeout.
- malformed headers.

Check:

- required params arrive (`name, ip, proto, token, session_id, request_type`).
- static params from portal expression merged.

## 3.2 TMS IPTV

Mock endpoint: `/api/drm/auth_token`.

Scenarios and checks identical to Ministra.

---

## 4. Soak tests

1. 30 min, 100+ concurrent HLS clients, auth enabled:
   - no crashes.
   - no memory leak trend.
2. 30 min with backend intermittent 5xx/timeouts:
   - decision matches fail policy.
   - no request storm.
3. recheck timer enabled:
   - update_session cadence stable.
   - no client mass-drop on short backend outage (grace works).

---

## 5. Negative/security tests

1. Backend URL invalid scheme (`ftp://`) -> config error.
2. HTTPS backend without SSL support -> explicit error.
3. Header injection attempt in static headers -> sanitized.
4. Token masking in logs and API diagnostics.
5. No silent redirect loops for API/XHR.

---

## 6. Runbook (команды)

Unit:

```bash
cd /Users/mac/0009/astra
./stream scripts/tests/auth_backend_unit.lua
```

Focused greps:

```bash
rg -n "auth_backend|backend_default_allow|backend_deny|no_token" /var/log/stream/*.log
```
