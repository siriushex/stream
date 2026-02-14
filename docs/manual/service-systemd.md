# Сервис (systemd)

Коротко: Stream может ставить шаблон сервиса `stream@.service` и запускаться как инстанс с именем.

## Быстрый способ (через `--init`)

Если задать `-c` и `-p`, Stream сам создаст нужные файлы в `/etc/stream/` и **сразу включит сервис**.

```bash
sudo /usr/local/bin/stream --init -c /usr/local/etc/prod.json -p 9060
```

Что будет создано:
- `/etc/stream/prod.json` — копия конфига
- `/etc/stream/prod.env` — `STREAM_PORT=9060`
- шаблон `/etc/systemd/system/stream@.service`
Сервис будет включён как `stream@prod`.

## Вариант 2 (вручную)

1) Установить шаблон:
```bash
sudo /usr/local/bin/stream --init
```

2) Создать конфиг:
```bash
sudo tee /etc/stream/prod.json >/dev/null <<'JSON'
{}
JSON
```

3) Указать порт:
```bash
echo "STREAM_PORT=9060" | sudo tee /etc/stream/prod.env
```

4) Запустить сервис:
```bash
sudo systemctl enable --now stream@prod
```

## Как менять конфиг или порт

Конфиг:
```bash
sudo nano /etc/stream/prod.json
sudo systemctl restart stream@prod
```

Порт:
```bash
echo "STREAM_PORT=9061" | sudo tee /etc/stream/prod.env
sudo systemctl restart stream@prod
```

## Несколько инстансов

```bash
sudo /usr/local/bin/stream --init

# inst A
echo 'STREAM_PORT=9060' | sudo tee /etc/stream/a.env
echo '{}' | sudo tee /etc/stream/a.json
sudo systemctl enable --now stream@a

# inst B
echo 'STREAM_PORT=9061' | sudo tee /etc/stream/b.env
echo '{}' | sudo tee /etc/stream/b.json
sudo systemctl enable --now stream@b
```

## Проверка

```bash
systemctl status stream@prod
ss -lntp | grep 9060
```

## Удаление шаблона

```bash
sudo /usr/local/bin/stream --remove
```
