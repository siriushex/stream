# Установка

## Зачем этот шаг

На этом шаге вы ставите Stream Hub и получаете рабочую базу для первого канала:

- бинарник `stream`,
- базовые зависимости,
- подготовку под запуск вручную или через `systemd`.

## Что нужно заранее

- сервер Linux/macOS с доступом `sudo`,
- доступ в интернет к `stream.centv.ru`,
- свободный порт для Web UI (например `9060`).

## Что получите

- готовый запуск из CLI,
- доступ к Web UI и API,
- возможность перейти к созданию первого stream.

## Ubuntu / Debian (готовый бинарник)

```bash
curl -fsSL https://stream.centv.ru/install.sh | sudo bash -s -- --mode binary --runtime-only
```

!!! note "FULL / LITE"
    По умолчанию установщик ставит **FULL**‑сборку (с поддержкой транскода).

    Если нужен **LITE (no transcode)**, укажите артефакт явно:

    ```bash
    curl -fsSL https://stream.centv.ru/install.sh | sudo bash -s -- \
      --mode binary --runtime-only --artifact stream-linux-x86_64-lite
    ```

    Подробнее: [Build profiles (FULL/LITE)](../manual/build-profiles.md).

!!! warning "Старые системы"
    На очень старых Ubuntu (например 16.04) готовый бинарник может не запуститься из‑за старых системных библиотек.
    В этом случае используйте установку из исходников (ниже).

## CentOS / RHEL / Rocky / Alma (сборка из исходников)

```bash
curl -fsSL https://stream.centv.ru/install-centos.sh | sudo bash -s -- --mode source --ffmpeg-system --verify-transcode
```

!!! tip "Скорость и стабильность сборки"
    Установщик автоматически ограничивает `make -j` до разумного значения.
    При необходимости задайте вручную:

    ```bash
    curl -fsSL https://stream.centv.ru/install-centos.sh | sudo STREAM_MAKE_JOBS=4 bash -s -- --mode source --ffmpeg-system --verify-transcode
    ```

!!! note "Проверка транскода"
    Флаг `--verify-transcode` проверяет, что установлена **FULL**‑сборка и доступен `ffmpeg`.
    Если нужно пропустить проверку, используйте:

    ```bash
    curl -fsSL https://stream.centv.ru/install-centos.sh | sudo bash -s -- --mode source --ffmpeg-system --no-verify-transcode
    ```

!!! warning "Безопасная установка: HTTPS по умолчанию"
    Используйте `https://` как основной путь.
    `http://` допустим только как временный аварийный fallback, если на хосте действительно сломан CA-bundle.

    Перед запуском через HTTP проверьте источник:

    ```bash
    curl -fsSL http://stream.centv.ru/install-centos.sh -o /tmp/install-centos.sh
    head -n 40 /tmp/install-centos.sh
    sudo bash /tmp/install-centos.sh --mode source --ffmpeg-system --verify-transcode
    ```

!!! note "Если HTTPS недоступен из-за CA"
    На некоторых минимальных образах CentOS/RHEL нет актуального набора CA-сертификатов.
    Сначала попробуйте обновить CA, и только потом используйте HTTP fallback:

    ```bash
    sudo yum install -y ca-certificates || true
    sudo update-ca-trust || true
    curl -fsSL https://stream.centv.ru/install-centos.sh | sudo bash -s -- --mode source --ffmpeg-system --verify-transcode
    ```

    Если после этого HTTPS всё равно не работает:

    ```bash
    curl -fsSL http://stream.centv.ru/install-centos.sh | sudo bash -s -- --mode source --ffmpeg-system --verify-transcode
    ```

## Безопасная практика запуска installer

1. Проверяйте домен `stream.centv.ru` и используйте HTTPS по умолчанию.
2. Для production лучше сначала скачать скрипт, посмотреть содержимое и запускать локально.
3. HTTP fallback используйте только как временную меру на старых системах с проблемным CA-bundle.

```bash
curl -fsSL https://stream.centv.ru/install.sh -o /tmp/stream-install.sh
head -n 60 /tmp/stream-install.sh
sudo bash /tmp/stream-install.sh --mode binary --runtime-only
```

## macOS (для тестов/демо)

```bash
curl -fsSL https://stream.centv.ru/install-macos.sh | bash
```

!!! tip "Транскодирование"
    Если нужно транскодирование, установите `ffmpeg` в системе.

## После установки

Проверьте, что бинарник доступен:

```bash
/usr/local/bin/stream --help | head -n 20
```

Если нужен FULL-профиль (с транскодом), проверьте что в выводе есть `Build: FULL`.
Подробнее: [Build profiles (FULL/LITE)](../manual/build-profiles.md).

## Следующий шаг

- [Запуск](run.md)
