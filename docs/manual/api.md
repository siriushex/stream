# API (интеграция)

Stream Hub имеет HTTP API. Оно удобно, если вы хотите:

- создавать/обновлять каналы скриптом,
- собирать статусы,
- выгружать конфиг или алерты.

## База

Обычно API доступно по адресу:

```text
http://SERVER:9060/api/v1
```

## Авторизация (логин)

```bash
curl -sS -X POST "http://SERVER:9060/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin"}'
```

В ответе будет `token`. Дальше его можно передавать так:

```bash
curl -sS "http://SERVER:9060/api/v1/streams" \
  -H "Authorization: Bearer TOKEN"
```

## Частые запросы

Список каналов:

```bash
curl -sS "http://SERVER:9060/api/v1/streams" -H "Authorization: Bearer TOKEN"
```

Статусы каналов:

```bash
curl -sS "http://SERVER:9060/api/v1/stream-status" -H "Authorization: Bearer TOKEN"
```

Алерты:

```bash
curl -sS "http://SERVER:9060/api/v1/alerts" -H "Authorization: Bearer TOKEN"
```

## Важно про безопасность

- Не отдавайте API наружу без защиты.
- Если используете cookie‑авторизацию, некоторые запросы требуют CSRF‑заголовок.
- Проще всего для автоматизации использовать `Authorization: Bearer ...`.

