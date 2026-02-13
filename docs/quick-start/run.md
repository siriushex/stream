# Запуск

## Шаги

1. Создайте папку для конфигов.
2. Создайте пустой конфиг.
3. Запустите Stream Hub.

```bash
sudo mkdir -p /etc/stream
sudo sh -c 'echo {} > /etc/stream/prod.json'

sudo /usr/local/bin/stream -c /etc/stream/prod.json -p 9060
```

## Как проверить

Порт слушается:

```bash
ss -lntp | grep ':9060' || true
```

## Следующий шаг

- [Web UI](web-ui.md)

