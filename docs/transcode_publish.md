# Transcode Ladder + Publish (Phase 3)

Этот документ описывает новый режим транскодинга **Ladder+Publish** (multi-bitrate ladder), который работает поверх существующего Phase 2 (seamless UDP proxy cutover, per-output workers) и **не ломает legacy режим**.

## Режимы

1) **Legacy transcode (Phase 2)**
- Конфиг: `stream.type = "transcode"` + `stream.transcode.outputs`.
- Astra запускает ffmpeg и пишет напрямую в `outputs[]` (UDP/RTP/HTTP и т.д. как настроено).
- Опции: `process_per_output=true`, `seamless_udp_proxy=true`.

2) **Ladder+Publish (Phase 3)**
- Конфиг: `stream.type = "transcode"` + `stream.transcode.profiles` (непустой массив).
- Astra строит 2-3 профиля (720/540/360 и т.п.), а публикации (HLS/DASH/RTMP/RTSP/UDP) работают от внутренней шины.
- Legacy `transcode.outputs` может оставаться в конфиге, но **не используется** в ladder режиме.

## Конфигурация Ladder (profiles)

Минимально: каждому профилю нужен `id`, `width`, `height`, `bitrate_kbps`.

```json
{
  "type": "transcode",
  "id": "demo",
  "name": "Demo",
  "input": ["dvb://..."],
  "transcode": {
    "engine": "cpu",
    "profiles": [
      {"id": "HDHigh",   "width": 1280, "height": 720, "fps": 25, "bitrate_kbps": 2500, "maxrate_kbps": 3000},
      {"id": "HDMedium", "width":  960, "height": 540, "fps": 25, "bitrate_kbps": 1000, "maxrate_kbps": 1500},
      {"id": "SDHigh",   "width":  640, "height": 360, "fps": 25, "bitrate_kbps":  700, "maxrate_kbps":  900}
    ]
  }
}
```

### Encode mode (экономичность vs надежность)

- `process_per_output` **не задан** (nil): ladder работает в режиме **reliable** (по умолчанию)  
  1 ffmpeg на 1 профиль (стабильнее, но дороже по CPU/GPU).
- `process_per_output: false`: ladder **economical**  
  1 ffmpeg на все профили (decode 1 раз, encode N).

## Публикации (publish)

`stream.transcode.publish` (опционально) включает авто-паблишеры:

- `hls` (in-process, memfd/disk)
- `dash` (ffmpeg packager, пишет в `data-dir/dash/<stream_id>`)
- `rtmp`, `rtsp` (ffmpeg `-c copy` push)
- `udp`, `rtp` (in-process udp_output от внутренней шины)

Пример:

```json
{
  "transcode": {
    "profiles": [
      {"id":"HDHigh","width":1280,"height":720,"fps":25,"bitrate_kbps":2500},
      {"id":"HDMedium","width":960,"height":540,"fps":25,"bitrate_kbps":1000}
    ],
    "publish": [
      {"type":"hls","enabled":true,"variants":["HDHigh","HDMedium"]},
      {"type":"dash","enabled":false,"variants":["HDHigh","HDMedium"]},
      {"type":"rtmp","enabled":false,"profile":"HDHigh","url":"rtmp://example/app/stream"},
      {"type":"rtsp","enabled":false,"profile":"HDHigh","url":"rtsp://example/stream"}
    ]
  }
}
```

## Pull endpoints (всегда доступны при ladder)

Когда ladder запущен, доступны pull URL:

- **HTTP-TS** (per-profile):
  - `/live/<stream_id>~<profile_id>.ts`
- **HLS**:
  - master: `/hls/<stream_id>/index.m3u8`
  - variant: `/hls/<stream_id>~<profile_id>/index.m3u8`
- **DASH**:
  - `/dash/<stream_id>/manifest.mpd`

## Seamless failover (warm-switch)

В ladder режиме publish читает из внутренней шины на каждый профиль (udp_switch). При failover input:
- стартует standby encoder,
- ждём readiness,
- делаем cutover (`udp_switch:set_source(new_sender)`),
- publish продолжает работать без рестартов.

## Примечание про auth и internal publishers

Для внутренних ffmpeg publisher процессов используются URL с `?internal=1` и доступ только с loopback:
- `/play/<id>?internal=1` (input для ffmpeg transcode/audio-fix)
- `/live/<id>~<profile>.ts?internal=1` (input для publish packagers/pushers)

Это позволяет использовать token auth для внешних клиентов, не ломая локальные пайплайны.

