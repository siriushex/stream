# Operations

## Systemd Service
Templates are in `contrib/systemd/`:
- `astra.service`
- `astra.env`
- `astral-watchdog.service`
- `astral-watchdog.timer`
- `astral-watchdog.env`

Example locations (adjust as needed):
- Binary: `/opt/astra/astra`
- Web UI: `/opt/astra/web`
- Config: `/etc/astra/astra.json`
- Data dir: `/var/lib/astra`

Service command (from template):
```
ExecStart=/opt/astra/astra scripts/server.lua --config ${ASTRA_CONFIG} \
  -p ${ASTRA_HTTP_PORT} --data-dir ${ASTRA_DATA_DIR} --web-dir ${ASTRA_WEB_DIR}
```

### Restart storms / config errors
Astral exits with code `78` (`EX_CONFIG`) for startup config errors (bad port, missing web dir,
failed import). Recommended systemd guardrails to avoid restart storms:
```
Restart=on-failure
RestartPreventExitStatus=78
StartLimitIntervalSec=60
StartLimitBurst=3
```

Optional preflight (prevent a start with empty envs):
```
ExecStartPre=/bin/sh -lc 'test -n "$ASTRA_HTTP_PORT" && echo "$ASTRA_HTTP_PORT" | grep -Eq "^[0-9]+$"'
ExecStartPre=/bin/sh -lc 'test -r "$ASTRA_CONFIG"'
```

## Runtime Dependencies (Ubuntu/Debian)
If you deploy a prebuilt binary to a clean server, you may be missing runtime
libraries or external tools (for example `ffmpeg`).

Installer (idempotent):
```
sudo ./install.sh --bin /opt/astra/astra
```

Notes:
- The script checks missing shared libraries via `ldd` and installs matching `apt` packages.
- If the binary requires legacy `libssl.so.1.1` on Ubuntu 22.04+, it will download and
  install `libssl1.1` from official Ubuntu archives (fallback).
- You can skip `ffmpeg` installation with `--no-ffmpeg`.

## Watchdog (CPU/RAM)
The watchdog restarts the process if it exceeds CPU or RSS thresholds for
several consecutive checks.

Install:
```
sudo scripts/ops/install_watchdog.sh
```

Configuration:
- `/etc/astral-watchdog.env`
- Defaults: `CPU_LIMIT=300`, `RSS_LIMIT_MB=1500`, `HITS_THRESHOLD=2`
- You can also set `ASTRA_CMD` or `ASTRA_PGREP` for custom run patterns.

Status:
```
systemctl status astral-watchdog.timer
journalctl -u astral-watchdog.service -n 50
```

## Upgrade Flow
1. Stop service.
2. Backup config and data dir.
3. Deploy new binary and web assets.
4. Run `./configure.sh` and `make` on target if building from source.
5. Start service.
6. Run smoke checks (see `docs/TESTING.md`).

## Backups
- SQLite DB: `data/astra.db` (default).
- Config revisions: `data/backups/config/`.
- Export: `GET /api/v1/export` or `./astra scripts/export.lua`.

## Restore
- Restore `astra.db` and config revisions.
- Or re-import from JSON via `POST /api/v1/import` (merge/replace).

## Logs
- Runtime logs go to stdout or file via `--log`.
- Log retention for UI buffers is controlled by settings.

## Security Notes
- Do not commit secrets (tokens, passwords).
- Use `http_ip_allow` and `http_ip_deny` where possible.
