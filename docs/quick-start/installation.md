# Установка

Выберите команду под вашу ОС.

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
curl -fsSL https://stream.centv.ru/install-centos.sh | sudo bash
```

!!! note "Проверка транскода"
    По умолчанию `install-centos.sh` делает проверку, что установлена **FULL**‑сборка и доступен `ffmpeg`.
    Если нужно пропустить проверку:

    ```bash
    curl -fsSL https://stream.centv.ru/install-centos.sh | sudo bash -s -- --no-verify-transcode
    ```

!!! note "Если HTTPS не работает"
    На некоторых минимальных образах CentOS/RHEL нет актуального набора CA‑сертификатов.
    Тогда `curl` может ругаться на сертификат. В этом случае используйте HTTP для запуска установщика:

    ```bash
    curl -fsSL http://stream.centv.ru/install-centos.sh | sudo bash
    ```

## macOS (для тестов/демо)

```bash
curl -fsSL https://stream.centv.ru/install-macos.sh | bash
```

!!! tip "Транскодирование"
    Если нужно транскодирование, установите `ffmpeg` в системе.

## Следующий шаг

- [Запуск](run.md)
