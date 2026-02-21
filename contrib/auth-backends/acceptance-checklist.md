# Auth Backends Acceptance Checklist

## 1. Functional PASS criteria

- [ ] В UI можно создать backend, указав только `Portal address`.
- [ ] Для Ministra endpoint строится как `/stalker_portal/server/api/chk_flussonic_tmp_link.php`.
- [ ] Для TMS endpoint строится как `/api/drm/auth_token`.
- [ ] Stream с `on_play=auth://<id>` реально использует named backend.
- [ ] `/play` и `/live` авторизуются через одинаковый auth контур.
- [ ] HLS playlist rewrite/cookie логика работает без регрессий.
- [ ] `parallel` и `sequential` дают ожидаемые решения.

---

## 2. Decision semantics

- [ ] `200` => allow.
- [ ] `302 + Location` => redirect to client.
- [ ] `4xx` => deny.
- [ ] timeout/`5xx` => fail-policy (`allow_default` true/false).
- [ ] rules allow/deny имеют приоритет до backend call.

---

## 3. Stability

- [ ] При backend timeout Stream не падает.
- [ ] Нет шторма auth запросов при множестве HLS сегментов.
- [ ] Concurrency limit (`auth_backend_max_concurrency`) защищает от overload.
- [ ] Recheck не вызывает массовых ложных disconnect.

---

## 4. Security

- [ ] Секреты не пишутся в clear-text логи.
- [ ] Только `http/https` backend URLs.
- [ ] Header values sanitization проверена.
- [ ] Admin bypass работает только для валидной admin session.

---

## 5. UX readiness

- [ ] Ошибки в Test backend человекочитаемы (401/403/timeout/SSL).
- [ ] Advanced параметры скрыты по умолчанию.
- [ ] Обязательные поля в simple mode минимальны (адрес портала).
- [ ] В stream editor явно видно, какой backend выбран.

---

## 6. Compatibility

- [ ] Legacy direct URL backend продолжает работать.
- [ ] Старые stream config без `auth_backends` не ломаются.
- [ ] Token source legacy behavior сохранён при пустом `token_source`.

---

## 7. Gaps to close before “full production”

- [ ] Добавлен optional `close_session` callback.
- [ ] Введён единый trace-id для auth transaction в diagnostics.
- [ ] Реализована расширенная portal diagnostics карточка в UI.
