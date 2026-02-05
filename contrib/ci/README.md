# CI Smoke Scripts

Этот каталог содержит быстрые smoke-проверки для локального запуска и CI.

## Скрипты
- `smoke.sh` — базовые проверки Web/API.
- `smoke_mpts.sh` — проверка MPTS (PAT/PMT/SDT/NIT/TOT/bitrate).
- `smoke_mpts_strict_pnr.sh` — проверка режима `strict_pnr` (multi-PAT без PNR отклоняется).
- `smoke_mpts_pid_collision.sh` — проверка конфликтов PID при `disable_auto_remap`.
- `smoke_mpts_pass_tables.sh` — проверка pass-режимов (SDT/EIT/CAT).
- `smoke_bundle_transcode.sh` — проверка bundled FFmpeg и transcode.

## Параметры
- `smoke.sh`:
  - `PORT`, `DATA_DIR`, `WEB_DIR`, `LOG_FILE`.
  - `MPTS_STRICT_PNR_SMOKE=1` — включить `smoke_mpts_strict_pnr.sh`.
  - `MPTS_STRICT_PNR_PORT` — порт для strict-PNR smoke (по умолчанию 9057).
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

## Примеры
```bash
contrib/ci/smoke.sh
MPTS_STRICT_PNR_SMOKE=1 contrib/ci/smoke.sh
contrib/ci/smoke_mpts.sh
contrib/ci/smoke_mpts_strict_pnr.sh
contrib/ci/smoke_mpts_pid_collision.sh
contrib/ci/smoke_mpts_pass_tables.sh
```
