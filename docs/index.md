# Stream Hub

Stream Hub — сервер, который принимает поток и отдаёт его дальше.

## Коротко

- Настройка через Web UI.
- Один канал (Stream) = один вход + один или несколько выходов.
- Транскодирование — опционально. Нужен `ffmpeg`.

!!! tip "Если вы запускаете впервые"
    Начните с раздела **Быстрый старт**. Там всё по шагам.

## Установка (Ubuntu/Debian)

```bash
curl -fsSL https://stream.centv.ru/install.sh | sudo bash -s -- --mode binary --runtime-only
```

## Запуск

```bash
sudo mkdir -p /etc/stream
sudo sh -c 'echo {} > /etc/stream/prod.json'

sudo /usr/local/bin/stream -c /etc/stream/prod.json -p 9060
```

Открыть Web UI:

- `http://SERVER:9060`

## Дальше

- **Быстрый старт** → установка, запуск, первый канал, проверка.
- **Руководство** → входы, выходы, логи, безопасность.

