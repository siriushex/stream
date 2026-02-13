# Выходы (Output)

Выход — это “куда отдавать” поток.

## Шаги

1. Откройте канал (Edit stream).
2. В **OUTPUT LIST** нажмите **NEW OUTPUT** (или **+**).
3. Выберите тип и адрес.
4. Нажмите **OK**, потом **Save**.

## Что выбрать в начале

- **UDP** — просто и быстро в локальной сети.
- **HTTP‑TS** — удобно проверить по ссылке.
- **HLS** — удобно для браузера и плееров, но это плейлист и сегменты.

## Типы выходов (кратко)

### UDP / RTP

Хорошо для локальной сети.
Примеры:

```text
udp://239.0.0.1:1234
udp://enp5s0f1@239.0.0.1:1234
rtp://239.0.0.1:5004
```

### HTTP‑TS (local)

Прямая ссылка на TS по HTTP.
Обычно выглядит так:

```text
http://SERVER:9060/live/STREAM_ID
```

### HLS / DASH (local)

Плейлисты и сегменты. Удобно для браузеров и большинства плееров.

```text
http://SERVER:9060/hls/STREAM_ID/index.m3u8
http://SERVER:9060/dash/STREAM_ID/manifest.mpd
```

### Embed page

Страница‑плеер (обычно для HLS):

```text
http://SERVER:9060/embed/STREAM_ID
```

### RTMP / RTSP (push)

Отправка на внешний сервер:

```text
rtmp://example.com/live/stream
rtsp://example.com/stream
```

## Проверка

```bash
ffplay http://SERVER:9060/live/STREAM_ID
```

!!! warning "Если выход включён, но не играет"
    Сначала проверьте вход (битрейт/ONLINE). Потом — firewall и сеть.
