# Запуск

## Зачем этот шаг

На этом шаге вы запускаете Stream Hub и проверяете, что Web UI/API доступны.

## Что нужно

- установленный бинарник `stream`,
- путь к конфигу (например `/etc/stream/prod.json`),
- свободный порт (пример: `9060`).

## Что получите

- работающий процесс Stream Hub,
- доступ к Web UI и API,
- базовую точку для создания первого канала.

## Команда запуска

```bash
sudo mkdir -p /etc/stream
sudo sh -c 'echo {} > /etc/stream/prod.json'

sudo /usr/local/bin/stream -c /etc/stream/prod.json -p 9060
```

## Как проверить, что всё поднялось

Порт слушается:

```bash
ss -lntp | grep ':9060' || true
```

Проверка HTTP:

```bash
curl -I http://127.0.0.1:9060/
```

В логах при штатном старте вы увидите строку вида `web ui on 0.0.0.0:9060`.

## Если нужен другой порт

Просто поменяйте значение в `-p`, например:

```bash
sudo /usr/local/bin/stream -c /etc/stream/prod.json -p 8002
```

## Следующий шаг

- [Web UI](web-ui.md)
