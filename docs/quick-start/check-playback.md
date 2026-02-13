# Проверка проигрывания

Самое простое — проверить в VLC или `ffplay`.

## HTTP‑TS (пример)

```bash
ffplay -fflags nobuffer -flags low_delay -probesize 32 -analyzeduration 0 \
  http://SERVER:9060/live/STREAM_ID
```

## HLS (пример)

```bash
ffplay http://SERVER:9060/hls/STREAM_ID/index.m3u8
```

## UDP (пример)

```bash
ffplay -fflags nobuffer -flags low_delay udp://239.0.0.1:1234
```

!!! warning "Если не играет"
    Сначала проверьте вход. Если вход OFFLINE или битрейт 0 — выход тоже не будет играть.

## Следующий шаг

- [Запуск как сервис](run-as-service.md)

