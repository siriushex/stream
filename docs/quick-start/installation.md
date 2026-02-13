# Установка

Выберите команду под вашу ОС.

## Ubuntu / Debian (готовый бинарник)

```bash
curl -fsSL https://stream.centv.ru/install.sh | sudo bash -s -- --mode binary --runtime-only
```

!!! warning "Старые системы"
    На очень старых Ubuntu (например 16.04) готовый бинарник может не запуститься из‑за старых системных библиотек.
    В этом случае используйте установку из исходников (ниже).

## CentOS / RHEL / Rocky / Alma (сборка из исходников)

```bash
curl -fsSL https://stream.centv.ru/install-centos.sh | sudo bash
```

## macOS (для тестов/демо)

```bash
curl -fsSL https://stream.centv.ru/install-macos.sh | bash
```

!!! tip "Транскодирование"
    Если нужно транскодирование, установите `ffmpeg` в системе.

## Следующий шаг

- [Запуск](run.md)

