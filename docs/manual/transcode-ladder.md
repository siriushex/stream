# Multi‑bitrate (ladder) и Publish outputs

Эта страница про режим, когда у транскода **несколько профилей** (например 720p + 540p + 360p).

Зачем это нужно:

- HLS/DASH с несколькими вариантами качества,
- разные выходы на разных профилях,
- стабильнее для клиентов с “плавающим” интернетом.

## Как это устроено (простыми словами)

- Вы создаёте **Profiles** (на вкладке Transcode).
- Если профилей 2+ — Stream Hub работает как “ladder”.
- Выходы (HLS/DASH/HTTP‑TS/UDP/RTMP/RTSP/Embed) включаются в **OUTPUT LIST** на вкладке General.
- Для каждого выхода можно выбрать профиль (если UI показывает selector).

## Pull URL (что можно открыть в плеере)

Когда ladder запущен, обычно доступны:

- per‑profile HTTP‑TS:
  - `/live/<stream_id>~<profile_id>`
- HLS:
  - `/hls/<stream_id>/index.m3u8`
- DASH:
  - `/dash/<stream_id>/manifest.mpd`
- Embed page:
  - `/embed/<stream_id>`

## Если publish/push “отваливается”

Для push‑выходов (RTMP/RTSP/DASH packager) обычно есть retry‑логика.
Если выход периодически падает:

1. Сначала проверьте сеть (доступ к удалённому серверу).
2. Посмотрите логи ffmpeg/publisher.
3. Увеличьте задержку рестарта (cooldown/backoff), чтобы не было “restart storm”.

