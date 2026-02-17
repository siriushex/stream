# Безопасность

Это Web UI и API. Обычно его не стоит открывать в публичный интернет.

## Минимум

- Поменяйте пароль администратора.
- Ограничьте доступ к порту (firewall/VPN).
- Включите HTTP Authentication, если у вас есть внешние клиенты.

## Сброс пароля

```bash
sudo /usr/local/bin/stream --reset-password
```

!!! danger "Осторожно"
    Параметр `--no-web-auth` отключает авторизацию в Web UI.
    Используйте только в закрытой сети и для тестов.

## Установка через installer

- Предпочитайте `https://stream.centv.ru/...`.
- `http://` используйте только как временный fallback на старых системах с проблемным CA-bundle.
- Для production лучше скачивать installer в файл, просматривать и запускать локально.

```bash
curl -fsSL https://stream.centv.ru/install.sh -o /tmp/stream-install.sh
head -n 60 /tmp/stream-install.sh
sudo bash /tmp/stream-install.sh --mode binary --runtime-only
```

## Практика

- В проде лучше держать UI/API за VPN или за reverse‑proxy.
- Не выдавайте наружу лишние порты (особенно если включены `/play` и `/live`).
