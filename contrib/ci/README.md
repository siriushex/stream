# CI Smoke Scripts

Этот каталог содержит быстрые smoke-проверки для локального запуска и CI.

## Скрипты
- `smoke.sh` — базовые проверки Web/API.
- `smoke_mpts.sh` — проверка MPTS (PAT/PMT/SDT/NIT/TOT/bitrate).
- `smoke_mpts_strict_pnr.sh` — проверка режима `strict_pnr` (multi-PAT без PNR отклоняется).
- `smoke_mpts_pid_collision.sh` — проверка конфликтов PID при `disable_auto_remap`.
- `smoke_mpts_pass_tables.sh` — проверка pass-режимов (SDT/EIT/CAT).
- `smoke_bundle_transcode.sh` — проверка bundled FFmpeg и transcode.
- `smoke_audio_fix_failover.sh` — smoke для UDP output Audio Fix (failover primary/backup).
- `smoke_transcode_per_output_isolation.sh` — per-output workers: падение одного output не ломает остальные.
- `smoke_transcode_seamless_failover.sh` — per-output транскодинг + seamless cutover через UDP proxy (multicast input).

## Параметры
- `smoke.sh`:
  - `PORT`, `DATA_DIR`, `WEB_DIR`, `LOG_FILE`.
  - `MPTS_STRICT_PNR_SMOKE=1` — включить `smoke_mpts_strict_pnr.sh`.
  - `MPTS_STRICT_PNR_PORT` — порт для strict-PNR smoke (по умолчанию 9057).
  - `AUDIO_FIX_SMOKE=1` — включить `smoke_audio_fix_failover.sh`.
  - `AUDIO_FIX_PORT` — порт для audio-fix smoke (по умолчанию 9077).
  - `TRANSCODE_WORKERS_SMOKE=1` — включить `smoke_transcode_per_output_isolation.sh`.
  - `TRANSCODE_WORKERS_PORT` — порт для per-output workers smoke (по умолчанию 9083).
  - `TRANSCODE_SEAMLESS_SMOKE=1` — включить `smoke_transcode_seamless_failover.sh`.
  - `TRANSCODE_SEAMLESS_PORT` — порт для seamless smoke (по умолчанию 9084).
- `smoke_mpts.sh`:
  - `PORT`, `DATA_DIR`, `WEB_DIR`, `LOG_FILE`, `CONFIG_FILE`.
  - `GEN_DURATION`, `GEN_PPS`.
- `smoke_mpts_strict_pnr.sh`:
  - `PORT`, `DATA_DIR`, `WEB_DIR`, `LOG_FILE`, `CONFIG_FILE`.
  - `GEN_DURATION`, `GEN_PPS`.
- `smoke_mpts_pid_collision.sh`:
  - `PORT`, `DATA_DIR`, `WEB_DIR`, `LOG_FILE`, `CONFIG_FILE`.
  - `GEN_DURATION`, `GEN_PPS`.
- `smoke_mpts_pass_tables.sh`:
  - `PORT`, `DATA_DIR`, `WEB_DIR`, `LOG_FILE`, `CONFIG_FILE`.
  - `GEN_DURATION`, `GEN_PPS`.
- `smoke_bundle_transcode.sh`:
  - `PORT`, `BUNDLE_TAR`, `LOG_FILE`.
- `smoke_audio_fix_failover.sh`:
  - `PORT`, `WEB_DIR`, `STREAM_ID`, `TEMPLATE_FILE`.
- `smoke_transcode_per_output_isolation.sh`:
  - `PORT`, `WEB_DIR`, `STREAM_ID`, `TEMPLATE_FILE`.
- `smoke_transcode_seamless_failover.sh`:
  - `PORT`, `WEB_DIR`, `STREAM_ID`, `TEMPLATE_FILE`, `CHECK_OUTPUT`.

## Примеры
```bash
contrib/ci/smoke.sh
MPTS_STRICT_PNR_SMOKE=1 contrib/ci/smoke.sh
AUDIO_FIX_SMOKE=1 contrib/ci/smoke.sh
TRANSCODE_WORKERS_SMOKE=1 contrib/ci/smoke.sh
TRANSCODE_SEAMLESS_SMOKE=1 contrib/ci/smoke.sh
contrib/ci/smoke_mpts.sh
contrib/ci/smoke_mpts_strict_pnr.sh
contrib/ci/smoke_mpts_pid_collision.sh
contrib/ci/smoke_mpts_pass_tables.sh
contrib/ci/smoke_audio_fix_failover.sh
contrib/ci/smoke_transcode_per_output_isolation.sh
contrib/ci/smoke_transcode_seamless_failover.sh
```
