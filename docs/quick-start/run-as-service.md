# Запуск как сервис (systemd)

Если нужен автозапуск после перезагрузки — используйте systemd.

## Шаги

1. Быстрый способ (создание инстанса + автозапуск):

```bash
sudo /usr/local/bin/stream --init -c /usr/local/etc/prod.json -p 9060
```

Будет создано:
- `/etc/stream/prod.json`
- `/etc/stream/prod.env` с `STREAM_PORT=9060`
- включится `stream@prod`

2. Вручную (если хотите сами управлять файлами):

Зарегистрируйте шаблон сервиса:

```bash
sudo /usr/local/bin/stream --init
```

Создайте env‑файл инстанса (пример: `prod`):

```bash
sudo sh -c 'echo STREAM_PORT=9060 > /etc/stream/prod.env'
```

Создайте конфиг (если его ещё нет):

```bash
sudo sh -c 'echo {} > /etc/stream/prod.json'
```

Запустите сервис:

```bash
sudo systemctl enable --now stream@prod.service
```

## Логи сервиса

```bash
journalctl -u stream@prod.service -f
```

## Дальше

- [Руководство → Входы](../manual/inputs.md)
