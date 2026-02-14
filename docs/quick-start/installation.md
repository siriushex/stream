# Установка

Выберите команду под вашу ОС.

## Ubuntu / Debian (готовый бинарник)

```bash
curl -fsSL https://stream.centv.ru/install.sh | sudo bash -s -- --mode binary --runtime-only
```

!!! note "LITE (без транскода)"
    Готовый бинарник **stream-latest** сейчас собирается в LITE‑режиме.
    В нём нет транскодирования и функций, которые зависят от `ffmpeg`.
    Если нужен транскод, соберите из исходников (см. ниже) или используйте FULL‑сборку.
    Подробнее: [Build profiles (FULL/LITE)](../manual/build-profiles.md).

!!! warning "Старые системы"
    На очень старых Ubuntu (например 16.04) готовый бинарник может не запуститься из‑за старых системных библиотек.
    В этом случае используйте установку из исходников (ниже).

## CentOS / RHEL / Rocky / Alma (сборка из исходников)

```bash
curl -fsSL https://stream.centv.ru/install-centos.sh | sudo bash
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
