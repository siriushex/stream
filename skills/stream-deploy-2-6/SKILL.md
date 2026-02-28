# stream-deploy-2-6

## Purpose
Single safe playbook for building and deploying Stream on:
- `.2` test host
- `.6` production host

## Hard rules
1. `.6` is production: do not deploy there without explicit user request for `.6`.
2. Never copy local macOS-built `stream` binary to Linux servers.
3. Build on target Linux server from source (`./configure.sh && make`) to avoid `glibc`/format mismatch.
4. Before restart, always keep binary backup on server.
5. After deploy, verify service state and HTTP availability.

## Access
- Use preconfigured secure SSH aliases from your private ops vault.
- Do not store IP addresses, usernames, key paths, or raw SSH commands in the repository.
- Required mapping for ops team:
  - alias `stream-test` -> node `.2`
  - alias `stream-prod` -> node `.6`

## Standard deploy flow

### 1) Prepare source revision
From local repo:
```bash
cd /Users/mac/0009/astra
git fetch origin
git checkout main
git pull --ff-only origin main
```

### 2) Build on target host (clean clone)
Run on target host (`.2` or `.6`):
```bash
set -e
BUILD_DIR=/root/stream-build-$(date +%Y%m%d-%H%M%S)
git clone --depth 1 --branch main https://github.com/siriushex/stream.git "$BUILD_DIR"
cd "$BUILD_DIR"
./configure.sh
make -j"$(nproc)"
```

### 3) Install with backup
Run on target host:
```bash
set -e
cp -a /usr/local/bin/stream /usr/local/bin/stream.bak.$(date +%s)
install -m 0755 ./stream /usr/local/bin/stream
```

### 3b) Sync runtime `scripts/web` when override directories exist
If target host has `/etc/stream/scripts` and/or `/etc/stream/web`, sync them from the same source revision.
Otherwise Lua/UI changes from `main` may not apply even after binary update.

Run on target host:
```bash
set -e
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p /etc/stream/backup.$TS
[ -d /etc/stream/scripts ] && cp -a /etc/stream/scripts /etc/stream/backup.$TS/scripts || true
[ -d /etc/stream/web ] && cp -a /etc/stream/web /etc/stream/backup.$TS/web || true
rsync -a --delete ./scripts/ /etc/stream/scripts/
rsync -a --delete ./web/ /etc/stream/web/
```

### 4) Restart service(s)
Discover and restart only required units:
```bash
systemctl list-units --type=service --all 'stream*' --no-pager
```

Typical restart examples:
```bash
systemctl restart stream@prod.service
systemctl restart stream@test9061.service
```

### 5) Verify
```bash
systemctl is-active stream@prod.service
systemctl status --no-pager --lines=40 stream@prod.service
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9060/
```

If specific instance exists, verify port accordingly (example `:8800`, `:9070`).

## Rollback
If service fails after deploy:
```bash
set -e
ls -1t /usr/local/bin/stream.bak.* | head -n 1
install -m 0755 "$(ls -1t /usr/local/bin/stream.bak.* | head -n 1)" /usr/local/bin/stream
systemctl restart stream@prod.service
systemctl status --no-pager --lines=40 stream@prod.service
```

## Diagnostics checklist
1. `systemctl status stream@...` and `journalctl -u stream@... -n 200 --no-pager`
2. `file /usr/local/bin/stream`
3. `/usr/local/bin/stream -v`
4. HTTP health check for instance port (`curl -I http://127.0.0.1:<port>/`)
5. UI/API sanity check (`/api/v1/status` or `/api/v1/streams`)

## Known failure pattern
If logs show `Exec format error`:
- wrong binary format (often macOS binary on Linux) or incompatible binary.
- fix: rebuild on target server and reinstall.
