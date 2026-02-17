# FAQ

## Быстрый ответ за 1 минуту

- Новый пользователь: начните с [Быстрого старта](quick-start/index.md).
- Нужен один рабочий канал: пройдите [Установка](quick-start/installation.md) → [Запуск](quick-start/run.md) → [Первый канал](quick-start/first-stream.md).
- Поток не играет: откройте [Если не работает](manual/troubleshooting.md).

## Если не играет: короткий чек-лист

1. В карточке stream проверьте `Input` (`ONLINE`) и `bitrate` (не `0`).
2. Убедитесь, что входной URL доступен с сервера.
3. Проверьте правильность протокола: `udp://`, `http://`, `https://`, `hls://`/`http(s)://...m3u8`, `...mpd` для DASH.
4. Проверьте output URL и сетевую доступность порта.
5. Откройте вкладку **Log** и найдите ошибки по id канала.
6. Проверьте, что Web UI порт слушается (`ss -lntp | grep 9060`).
7. Если есть auth, проверьте логин/пароль и заголовки клиента.
8. Для детального разбора откройте [руководство по диагностике](manual/troubleshooting.md).

## Частые вопросы

??? question "Где лежат конфиги и данные?"
    По умолчанию:

    - конфиги: `/etc/stream/*.json`
    - env для systemd-инстансов: `/etc/stream/*.env`
    - data-dir: рядом с конфигом или в отдельной папке (зависит от запуска)

    Пример ручного запуска:

    ```bash
    /usr/local/bin/stream -c /etc/stream/prod.json -p 9060
    ```

??? question "Нужен ли ffmpeg?"
    `ffmpeg` нужен только для функций, которые запускают внешние процессы:

    - транскодирование,
    - PNG to Stream,
    - Create radio.

    Для relay (UDP/HTTP-TS), backup, remap, MPTS и базового вещания он не обязателен.

??? question "Почему нет вкладки Transcode?"
    Скорее всего у вас сборка **LITE (no transcode)**.
    В ней Transcode отключен, чтобы бинарник не тянул зависимости FFmpeg.
    Подробнее: [Build profiles (FULL/LITE)](manual/build-profiles.md).

    Проверка:

    ```bash
    /usr/local/bin/stream --version
    ```

??? question "Как поставить как сервис (systemd)?"
    Быстрый способ (создаёт файлы и включает сервис):

    ```bash
    sudo /usr/local/bin/stream --init -c /usr/local/etc/prod.json -p 9060
    sudo systemctl status stream@prod
    ```

??? question "Как поменять порт у сервиса?"
    Порт задаётся в `/etc/stream/<name>.env`:

    ```bash
    echo 'STREAM_PORT=9061' | sudo tee /etc/stream/prod.env
    sudo systemctl restart stream@prod
    ```

??? question "Как сбросить пароль администратора?"
    ```bash
    sudo /usr/local/bin/stream --reset-password
    ```

??? question "Как отключить пароль в Web UI?"
    Есть флаг запуска:

    ```bash
    /usr/local/bin/stream -c /etc/stream/prod.json -p 9060 --no-web-auth
    ```

    Используйте `--no-web-auth` только в закрытой сети и для тестов.

??? question "Как обновить Stream?"
    Если установка была через installer:

    ```bash
    curl -fsSL https://stream.centv.ru/install.sh | sudo bash -s -- --mode binary
    sudo systemctl restart stream@prod
    ```

??? question "Как сделать резервную заставку или радио-канал?"
    - [PNG to Stream](manual/png-to-stream.md)
    - [Create radio](manual/create-radio.md)

??? question "Как запустить несколько инстансов?"
    Быстро, через `--init -c -p`:

    ```bash
    sudo /usr/local/bin/stream --init -c /usr/local/etc/a.json -p 9060
    sudo /usr/local/bin/stream --init -c /usr/local/etc/b.json -p 9061
    ```

    Вручную:

    ```bash
    sudo /usr/local/bin/stream --init

    echo 'STREAM_PORT=9060' | sudo tee /etc/stream/a.env
    echo '{}' | sudo tee /etc/stream/a.json
    sudo systemctl enable --now stream@a

    echo 'STREAM_PORT=9061' | sudo tee /etc/stream/b.env
    echo '{}' | sudo tee /etc/stream/b.json
    sudo systemctl enable --now stream@b
    ```
