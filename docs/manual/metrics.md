# Метрики (Metrics / Prometheus)

Stream Hub отдаёт базовые метрики по HTTP.
Это удобно для мониторинга (Grafana/Prometheus) и для быстрых проверок.

## JSON метрики

```bash
curl -sS "http://SERVER:9060/api/v1/metrics" -H "Authorization: Bearer TOKEN"
```

## Prometheus формат

```bash
curl -sS "http://SERVER:9060/api/v1/metrics?format=prometheus" -H "Authorization: Bearer TOKEN"
```

## Что полезно смотреть

- память Lua,
- тайминги refresh/status (если включены),
- общие счётчики ошибок/алертов.

!!! tip "Если вы не используете Prometheus"
    Всё равно полезно знать, что endpoint есть. Он помогает при разборе производительности.

