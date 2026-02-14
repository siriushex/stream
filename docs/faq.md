# FAQ

## Где лежат конфиги и данные?

По умолчанию:

- конфиги: `/etc/stream/*.json`
- env для systemd-инстансов: `/etc/stream/*.env`
- data-dir: рядом с конфигом или в отдельной папке (зависит от запуска)

Если вы запускаете вручную:

```bash
/usr/local/bin/stream -c /etc/stream/prod.json -p 9060
```

## Нужен ли ffmpeg?

`ffmpeg` нужен только для функций, которые запускают внешние процессы:

- транскодирование,
- PNG to Stream,
- Create radio.

Для обычного relay (UDP/HTTP-TS), backup, softcam, remap, MPTS он не обязателен.

## Почему нет вкладки Transcode?

Скорее всего у вас сборка **LITE (no transcode)**.
В ней Transcode отключен, чтобы бинарник не тянул зависимости FFmpeg.

Проверьте:

```bash
/usr/local/bin/stream --version
```

## Как поставить как сервис (systemd)?

Быстрый способ (создает файлы и включает сервис):

```bash
sudo /usr/local/bin/stream --init -c /usr/local/etc/prod.json -p 9060
```

После этого:

```bash
sudo systemctl status stream@prod
```

## Как поменять порт у сервиса?

Порт задается в `/etc/stream/<name>.env`:

```bash
echo 'STREAM_PORT=9061' | sudo tee /etc/stream/prod.env
sudo systemctl restart stream@prod
```

## Как сбросить пароль администратора?

```bash
sudo /usr/local/bin/stream --reset-password
```

## Как отключить пароль в Web UI?

Есть флаг запуска:

```bash
/usr/local/bin/stream -c /etc/stream/prod.json -p 9060 --no-web-auth
```

Если запускаете через systemd, добавьте это в unit (или в отдельный override).

## Как понять, почему "не играет"?

Минимальная проверка:

1. В UI откройте stream и посмотрите статус входа (ONLINE/OFFLINE, bitrate).
2. Откройте страницу **Log** и найдите ошибки по id канала.
3. Проверьте, что порт слушается:

```bash
ss -lntp | grep 9060
```

## Как обновить Stream?

Если вы ставили через installer:

```bash
curl -fsSL https://stream.centv.ru/install.sh | sudo bash -s -- --mode binary
```

Потом перезапустите сервис:

```bash
sudo systemctl restart stream@prod
```

## Как сделать резервную "заставку" из PNG?

См. страницу: [PNG to Stream](manual/png-to-stream.md).

## Как сделать радио-канал (аудио + PNG -> UDP)?

См. страницу: [Create radio](manual/create-radio.md).

## Как запустить несколько инстансов?

Вариант 1 (быстро, через `--init -c -p`):

```bash
sudo /usr/local/bin/stream --init -c /usr/local/etc/a.json -p 9060
sudo /usr/local/bin/stream --init -c /usr/local/etc/b.json -p 9061
```

Вариант 2 (вручную):

```bash
sudo /usr/local/bin/stream --init

echo 'STREAM_PORT=9060' | sudo tee /etc/stream/a.env
echo '{}' | sudo tee /etc/stream/a.json
sudo systemctl enable --now stream@a

echo 'STREAM_PORT=9061' | sudo tee /etc/stream/b.env
echo '{}' | sudo tee /etc/stream/b.json
sudo systemctl enable --now stream@b
```
