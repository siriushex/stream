# CLI и запуск как сервис

Ниже — практичные команды, которые обычно нужны в проде.

## Запуск вручную

Минимальный старт:

```bash
sudo /usr/local/bin/stream -c /etc/stream/prod.json -p 9060
```

Если вы передали `-c prod.json` (без пути), Stream Hub будет искать конфиг в `/etc/stream/prod.json`.

## Полезные команды

Показать справку:

```bash
/usr/local/bin/stream --help
```

Сбросить пароль админа на `admin/admin`:

```bash
sudo /usr/local/bin/stream --reset-password
```

Отключить авторизацию в Web UI (только для закрытой сети и теста):

```bash
sudo /usr/local/bin/stream --no-web-auth -c /etc/stream/prod.json -p 9060
```

!!! danger "Опасно"
    `--no-web-auth` делает Web UI открытым. Не используйте это в интернете.

## systemd (запуск как сервис)

### 1) Установить шаблон сервиса

```bash
sudo /usr/local/bin/stream --init
```

Это создаёт unit: `/etc/systemd/system/stream@.service`.

### 2) Создать конфиг и env

Пример для инстанса `prod`:

- `/etc/stream/prod.json`
- `/etc/stream/prod.env`

В `prod.env` обычно достаточно задать порт:

```bash
sudo sh -c 'cat > /etc/stream/prod.env <<EOF
STREAM_PORT=9060
EOF'
```

### 3) Включить и запустить

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now stream@prod.service
```

Логи:

```bash
journalctl -u stream@prod.service -f
```

### Удалить шаблон сервиса

```bash
sudo /usr/local/bin/stream --remove
```

