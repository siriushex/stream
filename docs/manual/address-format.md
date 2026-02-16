# Форматы адресов

Эта страница про “как выглядит адрес”.

## UDP с интерфейсом

Иногда важно, через какой сетевой интерфейс принимать multicast.

```text
udp://enp5s0f1@239.0.0.1:1234
```

То же правило часто работает и для выходов (UDP/RTP), когда нужно выбрать интерфейс отправки.

## Параметры в конце адреса

Иногда в адрес добавляют параметры после символа `#`.

```text
http://host/live/stream#sync
udp://239.0.0.1:1234#pnr=100
```

Если параметров несколько, они могут быть через `&`:

```text
udp://239.0.0.1:1234#pnr=100&cc_limit=1
```

!!! tip "Правило"
    Если вы копируете адрес — копируйте его целиком, вместе с частью после `#`.

## Параметры после `?`

Иногда параметры бывают и в “обычной” части URL, после `?` (как у HTTP).
Пример:

```text
udp://239.0.0.1:1234?pkt_size=1316
```

Если и `?`, и `#` присутствуют — `#` всегда в конце.

## DASH (MPD) адрес

Канонический формат для DASH input:

```text
https://host/path/manifest.mpd#input_type=dash
```

Важные параметры DASH:

```text
https://host/path/manifest.mpd#input_type=dash&dash_strategy=auto_max&dash_representation_id=<video_id>&dash_audio_id=<audio_id>&dash_max_height=720&dash_rw_timeout_ms=15000&dash_startup_grace_sec=60&dash_max_no_data_sec=90
```

Для кастомных заголовков используйте `dash_headers` (разделитель строк `\r\n`).
