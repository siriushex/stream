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

## Multi-core Scaling (Stream Sharding)
Astral is largely single-threaded for the MPEG-TS hot path (inputs → processing → outputs). If one CPU core
hits 100% (often visible with SoftCAM/descrambling), you can spread load across multiple processes.

### Run multiple shards (same DB/config)
Each process will instantiate only its shard of streams:
```bash
# 4 shards on different ports
astral scripts/server.lua --config /etc/astral/prod.json -p 9060 --stream-shard 0/4
astral scripts/server.lua --config /etc/astral/prod.json -p 9061 --stream-shard 1/4
astral scripts/server.lua --config /etc/astral/prod.json -p 9062 --stream-shard 2/4
astral scripts/server.lua --config /etc/astral/prod.json -p 9063 --stream-shard 3/4
```

Notes:
- UDP/HLS outputs are independent; sharding does not change stream behavior, only which process runs which streams.
- UI/API will show only streams owned by that shard instance.

### Optional CPU pinning
You can pin each shard to its own CPU set to avoid “everything on core0”:
```bash
taskset -c 0-2 astral ... --stream-shard 0/4 -p 9060
taskset -c 3-5 astral ... --stream-shard 1/4 -p 9061
taskset -c 6-8 astral ... --stream-shard 2/4 -p 9062
taskset -c 9-11 astral ... --stream-shard 3/4 -p 9063
```

systemd alternative:
- Use `CPUAffinity=` in the service unit per shard.

### systemd example (template + env files)
Templates live in `contrib/systemd/`. For sharding you can use:
- `contrib/systemd/astral-sharded@.service` (supports optional `taskset` via `CPUS=` env)

Example envs:
```bash
# /etc/astral/prod0.env
CONFIG=/etc/astral/prod.json
PORT=9060
EXTRA_OPTS=--stream-shard 0/4
CPUS=0-2

# /etc/astral/prod1.env
CONFIG=/etc/astral/prod.json
PORT=9061
EXTRA_OPTS=--stream-shard 1/4
CPUS=3-5
```

Enable:
```bash
systemctl enable --now astral-sharded@prod0.service
systemctl enable --now astral-sharded@prod1.service
```
