# Operations

## Systemd Service
Templates are in `contrib/systemd/`:
- `stream.service`
- `stream.env`
- `stream-watchdog.service`
- `stream-watchdog.timer`
- `stream-watchdog.env`

Example locations (adjust as needed):
- Binary: `/usr/local/bin/stream`
- Web UI: `/usr/local/share/stream/web` (optional; otherwise embedded bundle)
- Config: `/etc/stream/stream.json`
- Data dir: `/etc/stream`

Service command (from template):
```
ExecStart=/usr/local/bin/stream -c ${STREAM_CONFIG} -p ${STREAM_HTTP_PORT} \
  --data-dir ${STREAM_DATA_DIR} --web-dir ${STREAM_WEB_DIR} ${STREAM_EXTRA_ARGS}
```

### Restart storms / config errors
Stream exits with code `78` (`EX_CONFIG`) for startup config errors (bad port, missing web dir,
failed import). Recommended systemd guardrails to avoid restart storms:
```
Restart=on-failure
RestartPreventExitStatus=78
StartLimitIntervalSec=60
StartLimitBurst=3
```

Optional preflight (prevent a start with empty envs):
```
ExecStartPre=/bin/sh -lc 'test -n "$STREAM_HTTP_PORT" && echo "$STREAM_HTTP_PORT" | grep -Eq "^[0-9]+$"'
ExecStartPre=/bin/sh -lc 'test -r "$STREAM_CONFIG"'
```

## Runtime Dependencies (Ubuntu/Debian)
If you deploy a prebuilt binary to a clean server, you may be missing runtime
libraries or external tools (for example `ffmpeg`).

Installer (idempotent):
```
sudo ./install.sh --bin /usr/local/bin/stream
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
- `/etc/stream-watchdog.env`
- Defaults: `CPU_LIMIT=300`, `RSS_LIMIT_MB=1500`, `HITS_THRESHOLD=2`
- You can also set `STREAM_CMD` or `STREAM_PGREP` for custom run patterns.

Status:
```
systemctl status stream-watchdog.timer
journalctl -u stream-watchdog.service -n 50
```

## Upgrade Flow
1. Stop service.
2. Backup config and data dir.
3. Deploy new binary and web assets.
4. Run `./configure.sh` and `make` on target if building from source.
5. Start service.
6. Run smoke checks (see `docs/TESTING.md`).

## Backups
- SQLite DB: `data/stream.db` (default).
- Config revisions: `data/backups/config/`.
- Export: `GET /api/v1/export` or `./stream scripts/export.lua`.

## Restore
- Restore `stream.db` and config revisions.
- Or re-import from JSON via `POST /api/v1/import` (merge/replace).

## Logs
- Runtime logs go to stdout or file via `--log`.
- Log retention for UI buffers is controlled by settings.

## Security Notes
- Do not commit secrets (tokens, passwords).
- Use `http_ip_allow` and `http_ip_deny` where possible.

## Multi-core Scaling (Stream Sharding)
Stream is largely single-threaded for the MPEG-TS hot path (inputs → processing → outputs). If one CPU core
hits 100% (often visible with SoftCAM/descrambling), you can spread load across multiple processes.

### Run multiple shards (same DB/config)
Each process will instantiate only its shard of streams:
```bash
# 4 shards on different ports
stream scripts/server.lua --config /etc/stream/prod.json -p 9060 --stream-shard 0/4
stream scripts/server.lua --config /etc/stream/prod.json -p 9061 --stream-shard 1/4
stream scripts/server.lua --config /etc/stream/prod.json -p 9062 --stream-shard 2/4
stream scripts/server.lua --config /etc/stream/prod.json -p 9063 --stream-shard 3/4
```

Notes:
- UDP/HLS outputs are independent; sharding does not change stream behavior, only which process runs which streams.
- UI/API will show only streams owned by that shard instance.

### Optional CPU pinning
You can pin each shard to its own CPU set to avoid “everything on core0”:
```bash
taskset -c 0-2 stream ... --stream-shard 0/4 -p 9060
taskset -c 3-5 stream ... --stream-shard 1/4 -p 9061
taskset -c 6-8 stream ... --stream-shard 2/4 -p 9062
taskset -c 9-11 stream ... --stream-shard 3/4 -p 9063
```

systemd alternative:
- Use `CPUAffinity=` in the service unit per shard.

### systemd example (template + env files)
Templates live in `contrib/systemd/`. For sharding you can use:
- `contrib/systemd/stream-sharded@.service` (supports optional `taskset` via `CPUS=` env)

Example envs:
```bash
# /etc/stream/prod0.env
CONFIG=/etc/stream/prod.json
PORT=9060
EXTRA_OPTS=--stream-shard 0/4
CPUS=0-2

# /etc/stream/prod1.env
CONFIG=/etc/stream/prod.json
PORT=9061
EXTRA_OPTS=--stream-shard 1/4
CPUS=3-5
```

Enable:
```bash
systemctl enable --now stream-sharded@prod0.service
systemctl enable --now stream-sharded@prod1.service
```
