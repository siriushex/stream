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
- `embed` (включает удобную страницу `/embed/<stream_id>`; для воспроизведения требуется `hls`)

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

### Retry policy (publish)

Для push/packager процессов (`dash`, `rtmp`, `rtsp`) можно задать retry‑политику.
Поддерживается как глобально на `transcode.publish_retry`, так и на каждом publish target через `publish[].retry`
(локальный override сильнее).

Поддерживаемые поля:
- `restart_delay_sec`
- `restart_jitter_sec`
- `restart_backoff_base_sec`
- `restart_backoff_factor`
- `restart_backoff_max_sec`
- `restart_cooldown_sec`
- `max_restarts_per_10min`
- `no_progress_timeout_sec`
- `max_error_lines_per_min`
- `retry_on_network_error` (bool, default `true`)

Пример (per‑target override):

```json
{
  "transcode": {
    "publish": [
      {
        "type": "rtmp",
        "enabled": true,
        "profile": "HDHigh",
        "url": "rtmp://example/app/stream",
        "retry": {
          "restart_delay_sec": 2,
          "restart_backoff_base_sec": 2,
          "restart_backoff_max_sec": 30,
          "restart_jitter_sec": 1,
          "max_restarts_per_10min": 20,
          "retry_on_network_error": true
        }
      }
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
- **EMBED** (страница-плеер):
  - `/embed/<stream_id>`

## Seamless failover (warm-switch)

В ladder режиме publish читает из внутренней шины на каждый профиль (udp_switch). При failover input:
- стартует standby encoder,
- ждём readiness,
- делаем cutover (`udp_switch:set_source(new_sender)`),
- publish продолжает работать без рестартов.

## TR-101290-lite (расширение сигналов)

Для базовой DVB-диагностики можно включить дополнительные проверки:

Watchdog ключи (per-output):
- `pcr_jitter_limit_ms` и `pcr_jitter_hold_sec`  
  Если max PCR jitter превышает лимит дольше hold — срабатывает `PCR_JITTER`.
- `pcr_missing_hold_sec`  
  Если PCR не обнаружен дольше hold — срабатывает `PCR_MISSING`.
- `buffer_target_kbps`  
  Целевой muxrate/CBR, используется для грубой оценки наполнения буфера.
- `buffer_fullness_min_pct` / `buffer_fullness_max_pct` / `buffer_fullness_hold_sec`  
  Если оценка наполнения ниже/выше лимитов дольше hold — `BUFFER_UNDERFLOW` / `BUFFER_OVERFLOW`.

Пример:

```json
{
  "transcode": {
    "watchdog": {
      "pcr_jitter_limit_ms": 40,
      "pcr_jitter_hold_sec": 30,
      "pcr_missing_hold_sec": 10,
      "buffer_target_kbps": 3500,
      "buffer_fullness_min_pct": 85,
      "buffer_fullness_max_pct": 115,
      "buffer_fullness_hold_sec": 60
    }
  }
}
```

В `transcode.get_status` будут поля:
- `pcr_jitter_max_ms`, `pcr_jitter_avg_ms`, `pcr_missing_active`
- `buffer_fullness_pct`, `buffer_underflow_active`, `buffer_overflow_active`

## Примечание про auth и internal publishers

Для внутренних ffmpeg publisher процессов используются URL с `?internal=1` и доступ только с loopback:
- `/play/<id>?internal=1` (input для ffmpeg transcode/audio-fix)
- `/live/<id>~<profile>.ts?internal=1` (input для publish packagers/pushers)

Это позволяет использовать token auth для внешних клиентов, не ломая локальные пайплайны.
