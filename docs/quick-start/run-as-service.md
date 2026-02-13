# Запуск как сервис (systemd)

Если нужен автозапуск после перезагрузки — используйте systemd.

## Шаги

1. Зарегистрируйте шаблон сервиса:

```bash
sudo /usr/local/bin/stream --init
```

2. Создайте env‑файл инстанса (пример: `prod`):

```bash
sudo sh -c 'echo STREAM_PORT=9060 > /etc/stream/prod.env'
```

3. Создайте конфиг (если его ещё нет):

```bash
sudo sh -c 'echo {} > /etc/stream/prod.json'
```

4. Запустите сервис:

```bash
sudo systemctl enable --now stream@prod.service
```

## Логи сервиса

```bash
journalctl -u stream@prod.service -f
```

## Дальше

- [Руководство → Входы](../manual/inputs.md)

