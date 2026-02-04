# Operations

## Systemd Service
Templates are in `contrib/systemd/`:
- `astra.service`
- `astra.env`

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
