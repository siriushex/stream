# AGENT

## Scope
- Testing and final verification must run on the server in `/home/hex`.
- Connect with: `ssh -p 40242 -i ~/.ssh/root_blast root@178.212.236.2`
- The server has no DVB support; do not test adapters or any DVB-related flows there.
- Do not add secrets to the repo. Do not commit `.env` files or keys.
- Follow the strict team workflow in `docs/engineering/TEAM_WORKFLOW.md` and ownership in `.github/CODEOWNERS`.
- Performance priority: minimize CPU/RAM/IO usage. Avoid background timers and frequent polling by default; prefer on‑demand or cached workflows unless explicitly required.

## Codex environment setup (multi-agent)
- Use a separate working tree per agent to avoid file collisions:
  - `git worktree add ../astra-<agent> -b codex/<agent>/<topic>`
- Configure a unique Git identity per agent:
  - `git config user.name "<agent>"`
  - `git config user.email "<agent>@users.noreply.github.com"`
- Prefer rebasing by default:
  - `git config pull.rebase true`
- Ensure SSH access is configured for server deploys:
  - Key at `~/.ssh/root_blast` and port `40242`.
- Full checklist: `docs/engineering/CODEX_SETUP.md`.

## Strict workflow
1. Plan (when the change is not trivial).
2. Make edits locally.
3. Update `CHANGELOG.md` for every change.
4. Upload the updated repo to the server.
5. Run `./configure.sh` on the server (Linux) before building, then run smoke tests.
6. Record the result (update the CHANGELOG entry with tests/status). Re-upload if it changes.

## Multi-agent workflow (PR-first)
- Branch naming: `codex/<agent>/<topic>` (required).
- Start steps:
  - `git fetch origin`
  - `git checkout main`
  - `git pull --rebase`
  - `git checkout -b codex/<agent>/<topic>`
- Work steps:
  - Перед началом работы всегда делай `git pull --rebase`, чтобы синхронизироваться с репозиторием.
  - Commit frequently.
  - После изменений обязательно делай commit и push.
  - Push often: `git push -u origin codex/<agent>/<topic>` to prevent loss.
- Integration steps (PR required):
  - Open a PR from `codex/<agent>/<topic>` to `main`.
  - Ensure CI is green and CODEOWNERS approvals are present.
  - Rebase if required by branch protection rules.
  - Merge using fast-forward or linear history (no merge commits).
- Direct merge without PR is запрещён.
- Conflict policy:
  - Resolve conflicts only on the feature branch, вручную.
  - Never force-push to `main`.
- Merge lock rule:
  - Only one agent merges to `main` at a time.
  - Declare the merge in the shared chat before starting and after finishing.

## Ownership & Reviews
- `.github/CODEOWNERS` sets a single owner: `@siriushex`.
- Any change requires approval from `@siriushex` before merge.

## CI guardrails
- CI enforces branch naming: `codex/<agent>/<topic>`.
- CI enforces a `CHANGELOG.md` update in every PR.

## Local parallelization (worktrees)
- Use `git worktree` for separate branches on the same machine:
  - `git worktree add ../astra-<agent> -b codex/<agent>/<topic>`
  - `cd ../astra-<agent>`
  - Work and push from the worktree as usual.

## Gates (pre-push)
- Always run `contrib/ci/smoke.sh` locally or rely on CI for non-runtime changes.
- If changes affect runtime/C or core streaming behavior, run the full server smoke checklist in this file.

## Planning context
- Plan: `PLAN.md`
- Roadmap: `docs/ROADMAP.md`
- Parity matrix: `docs/PARITY.md`

## Upload
- Target directory: `/home/hex/astra`
- Use rsync (example):
```sh
rsync -az --delete --exclude '.git' --exclude 'astra' --exclude '*.o' --exclude '*.so' \
  -e "ssh -p 40242 -i ~/.ssh/root_blast" \
  ./ root@178.212.236.2:/home/hex/astra/
```

## Local sanity (optional)
- Build: `cd astra && ./configure.sh && make`
- Run UI/API server: `./astra scripts/server.lua -p 8000 --data-dir ./data --web-dir ./web`
- NOTE: local runs are not a substitute for server verification.

## Обязательная проверка (smoke tests)
Run from the server in `/home/hex`:
```sh
cd /home/hex

# Build (required after C/core changes)
cd /home/hex/astra
./configure.sh
make

# If make reports clock skew after rsync, normalize timestamps:
find /home/hex/astra -type f -exec touch -c {} +
cd /home/hex

# UI and assets
curl -I http://127.0.0.1:9000/index.html
curl -s http://127.0.0.1:9000/app.js | head -n 1

# Auth (use real admin credentials; do not store them in the repo)
curl -s -X POST http://127.0.0.1:9000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"<user>","password":"<pass>"}'

# API after login (replace TOKEN)
curl -s http://127.0.0.1:9000/api/v1/streams \
  -H "Cookie: astra_session=<TOKEN>"
curl -s http://127.0.0.1:9000/api/v1/settings \
  -H "Cookie: astra_session=<TOKEN>"

# Metrics (summary counters)
curl -s http://127.0.0.1:9000/api/v1/metrics \
  -H "Cookie: astra_session=<TOKEN>"
curl -s "http://127.0.0.1:9000/api/v1/metrics?format=prometheus" \
  -H "Cookie: astra_session=<TOKEN>"

# Health endpoints
curl -s http://127.0.0.1:9000/api/v1/health/process \
  -H "Cookie: astra_session=<TOKEN>"
curl -s http://127.0.0.1:9000/api/v1/health/inputs \
  -H "Cookie: astra_session=<TOKEN>"
curl -s http://127.0.0.1:9000/api/v1/health/outputs \
  -H "Cookie: astra_session=<TOKEN>"

# Config safety
curl -s -X POST http://127.0.0.1:9000/api/v1/config/validate \
  -H "Cookie: astra_session=<TOKEN>" \
  -H 'Content-Type: application/json' \
  --data-binary '{}'
curl -s http://127.0.0.1:9000/api/v1/config/revisions \
  -H "Cookie: astra_session=<TOKEN>"
curl -s -X POST http://127.0.0.1:9000/api/v1/reload \
  -H "Cookie: astra_session=<TOKEN>"

# Export (backup)
curl -s "http://127.0.0.1:9000/api/v1/export?include_users=0" \
  -H "Cookie: astra_session=<TOKEN>" | head -n 1
./astra scripts/export.lua --data-dir ./data --output ./astra-export.json
rm -f ./astra-export.json

# NOTE: do not test adapters or DVB-related endpoints on this server (no DVB).

# Optional: HTTP Play (when enabled)
curl -I http://127.0.0.1:9000/playlist.m3u8
curl -I http://127.0.0.1:9000/stream/<stream_id>

# Optional: HLS (when enabled)
curl -I http://127.0.0.1:9000/hls/<stream_id>/index.m3u8
```
NOTE: the default port in `scripts/server.lua` is `8000`, but the server may store
`http_port` in SQLite; adjust the URLs to the actual port.

## Smoke tests for config files (JSON/Lua)
Run from the server in `/home/hex/astra` (use `--data-dir` to avoid clobbering prod data):
```sh
cd /home/hex/astra

# JSON config (fixtures/ada2-10815.json)
./astra ./fixtures/ada2-10815.json -p 9001 --data-dir ./data_test --web-dir ./web &
JSON_PID=$!
sleep 2
curl -I http://127.0.0.1:9001/index.html
COOKIE_JAR=$(mktemp)
curl -s -c "$COOKIE_JAR" -X POST http://127.0.0.1:9001/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"admin","password":"admin"}'
curl -s http://127.0.0.1:9001/api/v1/settings -b "$COOKIE_JAR" | grep 'http_play_stream'
curl -s http://127.0.0.1:9001/api/v1/streams -b "$COOKIE_JAR"
rm -f "$COOKIE_JAR"
kill "$JSON_PID"

# Lua config (fixtures/sample.lua)
./astra ./fixtures/sample.lua -p 9002 --data-dir ./data_test2 --web-dir ./web &
LUA_PID=$!
sleep 2
curl -I http://127.0.0.1:9002/index.html
COOKIE_JAR=$(mktemp)
curl -s -c "$COOKIE_JAR" -X POST http://127.0.0.1:9002/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"admin","password":"admin"}'
curl -s http://127.0.0.1:9002/api/v1/settings -b "$COOKIE_JAR" | grep 'hls_duration'
curl -s http://127.0.0.1:9002/api/v1/streams -b "$COOKIE_JAR"
rm -f "$COOKIE_JAR"
kill "$LUA_PID"

# Missing config (auto-create defaults)
rm -f ./data_test_missing.json
rm -rf ./data_test_missing.data
./astra ./data_test_missing.json -p 9003 &
MISS_PID=$!
sleep 2
test -f ./data_test_missing.json
test -f ./data_test_missing.data/astra.db
curl -I http://127.0.0.1:9003/index.html
kill "$MISS_PID"
rm -f ./data_test_missing.json
rm -rf ./data_test_missing.data

# NOTE: do not test adapters or DVB-related endpoints on this server (no DVB).
```

## Smoke tests for input failover (passive/active)
Run from the server in `/home/hex/astra`:
```sh
cd /home/hex/astra

# Start two local MPEG-TS generators (primary + backup).
ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:12000?pkt_size=1316" &
PRIMARY_FF=$!
ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=800 -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:12001?pkt_size=1316" &
BACKUP_FF=$!

./astra ./fixtures/failover.json -p 9004 --data-dir ./data_failover --web-dir ./web &
FO_PID=$!
sleep 2

COOKIE_JAR=$(mktemp)
curl -s -c "$COOKIE_JAR" -X POST http://127.0.0.1:9004/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"admin","password":"admin"}'

# Passive: should switch to backup (index 1) when primary missing.
# Both sources up: primary should be active.
curl -s http://127.0.0.1:9004/api/v1/stream-status/failover_passive -b "$COOKIE_JAR" \
  | grep '"active_input_index":0'
# Wait beyond probe_interval_sec and ensure passive does not switch while active is OK.
sleep 6
curl -s http://127.0.0.1:9004/api/v1/stream-status/failover_passive -b "$COOKIE_JAR" \
  | grep '"active_input_index":0'

# Stop primary and expect passive switch to backup (index 1).
kill "$PRIMARY_FF" 2>/dev/null || true
sleep 4
curl -s http://127.0.0.1:9004/api/v1/stream-status/failover_passive -b "$COOKIE_JAR" \
  | grep '"active_input_index":1'

# Restore primary and expect passive to stay on backup (index 1).
ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:12000?pkt_size=1316" &
PRIMARY_FF=$!
sleep 4
curl -s http://127.0.0.1:9004/api/v1/stream-status/failover_passive -b "$COOKIE_JAR" \
  | grep '"active_input_index":1'

# Active mode: stop primary and expect fast switch to backup.
kill "$PRIMARY_FF"
sleep 2
curl -s http://127.0.0.1:9004/api/v1/stream-status/failover_active -b "$COOKIE_JAR" \
  | grep '"active_input_index":1'

# Restore primary and expect return.
ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:12000?pkt_size=1316" &
PRIMARY_FF=$!
sleep 4
curl -s http://127.0.0.1:9004/api/v1/stream-status/failover_active -b "$COOKIE_JAR" \
  | grep '"active_input_index":0'

# Active + stop: stop all inputs and expect INACTIVE.
kill "$PRIMARY_FF" 2>/dev/null || true
kill "$BACKUP_FF" 2>/dev/null || true
sleep 10
curl -s http://127.0.0.1:9004/api/v1/stream-status/failover_active_stop -b "$COOKIE_JAR" \
  | grep '"global_state":"INACTIVE"'

# Restore primary and expect RUNNING + active index 0.
ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:12000?pkt_size=1316" &
PRIMARY_FF=$!
sleep 4
curl -s http://127.0.0.1:9004/api/v1/stream-status/failover_active_stop -b "$COOKIE_JAR" \
  | grep '"global_state":"RUNNING"'
curl -s http://127.0.0.1:9004/api/v1/stream-status/failover_active_stop -b "$COOKIE_JAR" \
  | grep '"active_input_index":0'

# Disabled: no automatic switch.
ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=800 -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:12001?pkt_size=1316" &
BACKUP_FF=$!
sleep 2
curl -s http://127.0.0.1:9004/api/v1/stream-status/failover_disabled -b "$COOKIE_JAR" \
  | grep '"active_input_index":0'
kill "$PRIMARY_FF" 2>/dev/null || true
sleep 4
curl -s http://127.0.0.1:9004/api/v1/stream-status/failover_disabled -b "$COOKIE_JAR" \
  | grep '"active_input_index":0'

kill "$FO_PID"
kill "$PRIMARY_FF"
kill "$BACKUP_FF"
rm -f "$COOKIE_JAR"
rm -rf ./data_failover

# NOTE: do not test adapters or DVB-related endpoints on this server (no DVB).
```

## Smoke tests for HLS failover (discontinuity)
Run from the server in `/home/hex/astra`:
```sh
cd /home/hex/astra

# Start two local MPEG-TS generators (primary + backup).
ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:12000?pkt_size=1316" &
PRIMARY_FF=$!
ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=800 -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:12001?pkt_size=1316" &
BACKUP_FF=$!

./astra ./fixtures/failover_hls.json -p 9052 --data-dir ./data_failover_hls --web-dir ./web &
PID=$!
sleep 6

# Ensure playlist is available.
curl -s http://127.0.0.1:9052/hls/failover_hls/index.m3u8 | head -n 5

# Force switch to backup and expect discontinuity.
kill "$PRIMARY_FF" 2>/dev/null || true

attempts=10
while [ "$attempts" -gt 0 ]; do
  if curl -s http://127.0.0.1:9052/hls/failover_hls/index.m3u8 | grep -q '#EXT-X-DISCONTINUITY'; then
    break
  fi
  attempts=$((attempts - 1))
  sleep 2
done
test "$attempts" -gt 0

# Fetch the newest segment to ensure it is readable.
segment=$(curl -s http://127.0.0.1:9052/hls/failover_hls/index.m3u8 | grep -v '^#' | tail -n 1)
curl -I "http://127.0.0.1:9052/hls/failover_hls/${segment}" | head -n 1

kill "$PID"
kill "$BACKUP_FF"
rm -rf ./data_failover_hls

# NOTE: do not test adapters or DVB-related endpoints on this server (no DVB).
```

## Smoke tests for HLS + HTTP Play settings
Run from the server in `/home/hex/astra`:
```sh
cd /home/hex/astra

cat > ./tmp_hls_http_play.json <<'JSON'
{
  "settings": {
    "http_play_hls": true,
    "http_play_allow": false,
    "http_play_playlist_name": "playlist_test.m3u8",
    "hls_duration": 2,
    "hls_quantity": 3,
    "hls_m3u_headers": true,
    "hls_ts_headers": true
  },
  "make_stream": [
    {
      "id": "hls_demo",
      "name": "HLS Demo",
      "type": "udp",
      "enable": true,
      "input": ["udp://127.0.0.1:13000"],
      "output": []
    }
  ]
}
JSON

ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:13000?pkt_size=1316" &
FF_PID=$!

./astra ./tmp_hls_http_play.json -p 9026 --data-dir ./data_hls_9026 --web-dir ./web &
PID=$!
sleep 5

curl -I http://127.0.0.1:9026/playlist_test.m3u8
curl -s http://127.0.0.1:9026/playlist_test.m3u8 | head -n 5
curl -I http://127.0.0.1:9026/hls/hls_demo/index.m3u8 | grep -i 'cache-control: no-cache'
segment=$(curl -s http://127.0.0.1:9026/hls/hls_demo/index.m3u8 | grep -v '^#' | head -n 1)
if [ "${segment#'/'}" != "$segment" ]; then
  segment_url="http://127.0.0.1:9026${segment}"
else
  segment_url="http://127.0.0.1:9026/hls/hls_demo/${segment}"
fi
curl -I "$segment_url" | grep -i 'cache-control: public, max-age=6'

kill "$PID"
kill "$FF_PID"
rm -f ./tmp_hls_http_play.json
rm -rf ./data_hls_9026

# NOTE: do not test adapters or DVB-related endpoints on this server (no DVB).
```

## Smoke tests for user management
Run from the server in `/home/hex/astra`:
```sh
cd /home/hex/astra

COOKIE_JAR=$(mktemp)
curl -s -c "$COOKIE_JAR" -X POST http://127.0.0.1:9000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"admin","password":"admin"}'

# List users
curl -s http://127.0.0.1:9000/api/v1/users -b "$COOKIE_JAR"

# Create user
curl -s -X POST http://127.0.0.1:9000/api/v1/users -b "$COOKIE_JAR" \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"demo_user","password":"demo1234","is_admin":false,"enabled":true}'

# Disable user
curl -s -X PUT http://127.0.0.1:9000/api/v1/users/demo_user -b "$COOKIE_JAR" \
  -H 'Content-Type: application/json' \
  --data-binary '{"enabled":false}'

# Reset password
curl -s -X POST http://127.0.0.1:9000/api/v1/users/demo_user/reset -b "$COOKIE_JAR" \
  -H 'Content-Type: application/json' \
  --data-binary '{"password":"demo5678"}'

rm -f "$COOKIE_JAR"

# NOTE: there is no delete endpoint; leave demo_user disabled for testing only.
```

## Smoke tests for HTTP auth (allow/deny/tokens/basic)
Run from the server in `/home/hex/astra`:
```sh
cd /home/hex/astra

cat > ./tmp_http_auth.json <<'JSON'
{
  "settings": {
    "http_auth_enabled": true,
    "http_auth_users": true,
    "http_auth_tokens": "token123",
    "http_play_allow": true,
    "http_play_hls": false,
    "http_play_playlist_name": "playlist_auth.m3u8"
  },
  "make_stream": [
    {
      "id": "auth_demo",
      "name": "Auth Demo",
      "type": "udp",
      "enable": true,
      "input": ["udp://127.0.0.1:13100"],
      "output": []
    }
  ]
}
JSON

ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:13100?pkt_size=1316" &
FF_PID=$!

./astra ./tmp_http_auth.json -p 9028 --data-dir ./data_http_auth_9028 --web-dir ./web &
PID=$!
sleep 5

curl -I http://127.0.0.1:9028/playlist_auth.m3u8 | head -n 1
curl -I "http://127.0.0.1:9028/playlist_auth.m3u8?token=token123" | head -n 1
curl -I -u admin:admin http://127.0.0.1:9028/playlist_auth.m3u8 | head -n 1

kill "$PID"
kill "$FF_PID"
rm -f ./tmp_http_auth.json
rm -rf ./data_http_auth_9028

# NOTE: do not test adapters or DVB-related endpoints on this server (no DVB).
```

## Smoke tests for token auth backend (on_play/on_publish)
Run from the server in `/home/hex/astra`:
```sh
cd /home/hex/astra

python3 ./fixtures/auth_backend.py &
AUTH_BACKEND_PID=$!

ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:13200?pkt_size=1316" &
SRC_FF=$!

./astra ./fixtures/auth_play.json -p 9032 --data-dir ./data_auth_9032 --web-dir ./web &
PID=$!
sleep 6

# No token -> 403.
curl -I http://127.0.0.1:9032/playlist.m3u8 | head -n 1

# Token allow + playlist URLs include token.
curl -s "http://127.0.0.1:9032/playlist.m3u8?token=token1" | grep 'token=token1'

# HLS rewrite + cookie propagation.
curl -s "http://127.0.0.1:9032/hls/auth_demo/index.m3u8?token=token1" | grep 'token=token1'
curl -s -D - -o /dev/null "http://127.0.0.1:9032/hls/auth_demo/index.m3u8?token=token1" \
  | grep -i 'set-cookie: astra_token'

COOKIE_JAR=$(mktemp)
curl -s -c "$COOKIE_JAR" -X POST http://127.0.0.1:9032/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"admin","password":"admin"}'
curl -s http://127.0.0.1:9032/api/v1/sessions?type=auth -b "$COOKIE_JAR" | head -n 1
rm -f "$COOKIE_JAR"

kill "$PID"
kill "$SRC_FF"
kill "$AUTH_BACKEND_PID"
rm -rf ./data_auth_9032

# NOTE: do not test adapters or DVB-related endpoints on this server (no DVB).
```

## Smoke tests for token auth limits (max sessions / unique)
Run from the server in `/home/hex/astra`:
```sh
cd /home/hex/astra

python3 ./fixtures/auth_backend.py &
AUTH_BACKEND_PID=$!

ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:13200?pkt_size=1316" &
SRC_FF=$!

# Overlimit policy (deny_new) with max_sessions=3:
./astra ./fixtures/auth_limits.json -p 9033 --data-dir ./data_auth_limits_9033 --web-dir ./web &
PID=$!
sleep 6
curl -s "http://127.0.0.1:9033/playlist.m3u8?token=token1" | head -n 1
curl -s "http://127.0.0.1:9033/hls/auth_demo/index.m3u8?token=token1" | grep "token=token1"
curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:9033/playlist.m3u8?token=token2" | grep 403
kill "$PID"
rm -rf ./data_auth_limits_9033

# Unique sessions (kicks previous):
./astra ./fixtures/auth_unique.json -p 9034 --data-dir ./data_auth_unique_9034 --web-dir ./web &
PID=$!
sleep 4
curl -s "http://127.0.0.1:9034/playlist.m3u8?token=token1" | head -n 1
curl -s "http://127.0.0.1:9034/playlist.m3u8?token=token2" | head -n 1

COOKIE_JAR=$(mktemp)
curl -s -c "$COOKIE_JAR" -X POST http://127.0.0.1:9034/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"admin","password":"admin"}'
curl -s http://127.0.0.1:9034/api/v1/sessions?type=auth -b "$COOKIE_JAR" | python3 - <<'PY'
import json, sys
data = json.load(sys.stdin)
deny = sum(1 for item in data if item.get("status") == "DENY")
allow = sum(1 for item in data if item.get("status") == "ALLOW")
print("deny=", deny, "allow=", allow)
assert deny >= 1 and allow >= 1
PY
rm -f "$COOKIE_JAR"

kill "$PID"
kill "$SRC_FF"
kill "$AUTH_BACKEND_PID"
rm -rf ./data_auth_unique_9034

# NOTE: do not test adapters or DVB-related endpoints on this server (no DVB).
```

## Smoke tests for HLSSplitter (managed service)
Run from the server in `/home/hex/astra`:
```sh
cd /home/hex/astra

# Ensure hlssplitter binary exists (build externally if missing).
test -x ./hlssplitter/hlssplitter || test -x ./hlssplitter/source/hlssplitter/hlssplitter

# Create a small MPEG-TS file and serve it over HTTP.
ffmpeg -loglevel error -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=1000 -t 5 -c:v mpeg2video -c:a mp2 -f mpegts \
  ./tmp_splitter.ts
python3 -m http.server 18080 --directory . &
HTTP_PID=$!

./astra scripts/server.lua -p 9041 --data-dir ./data_splitter_9041 --web-dir ./web &
PID=$!
sleep 3

TOKEN=$(curl -s -X POST http://127.0.0.1:9041/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"admin","password":"admin"}' | \
  python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
AUTH=(-H "Authorization: Bearer $TOKEN")

# Create splitter instance.
curl -s -X POST http://127.0.0.1:9041/api/v1/splitters "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  --data-binary '{"id":"splitter_demo","name":"Splitter Demo","enable":true,"port":8089}'

# Allow all (optional; default is allow 0.0.0.0 if no rules exist).
curl -s -X POST http://127.0.0.1:9041/api/v1/splitters/splitter_demo/allow "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  --data-binary '{"kind":"allow","value":"0.0.0.0"}'

# Add link (HTTP only).
curl -s -X POST http://127.0.0.1:9041/api/v1/splitters/splitter_demo/links "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  --data-binary '{"id":"link_demo","enable":true,"url":"http://127.0.0.1:18080/tmp_splitter.ts","bandwidth":1800000,"buffering":10}'

# Start instance and check status.
curl -s -X POST http://127.0.0.1:9041/api/v1/splitters/splitter_demo/start "${AUTH[@]}"
curl -s http://127.0.0.1:9041/api/v1/splitter-status/splitter_demo "${AUTH[@]}" | head -n 1
curl -s http://127.0.0.1:9041/api/v1/splitters/splitter_demo/config "${AUTH[@]}" | head -n 5

# Validate output TS sync bytes.
python3 - <<'PY'
import urllib.request
url = "http://127.0.0.1:8089/tmp_splitter.ts"
data = urllib.request.urlopen(url, timeout=3).read(1880)
ok = all(data[i] == 0x47 for i in range(0, len(data), 188))
print("sync_ok", ok)
PY

curl -s -X POST http://127.0.0.1:9041/api/v1/splitters/splitter_demo/stop "${AUTH[@]}"

kill "$PID"
kill "$HTTP_PID"
rm -f ./tmp_splitter.ts
rm -rf ./data_splitter_9041

# NOTE: do not test adapters or DVB-related endpoints on this server (no DVB).
```

## Smoke tests for Buffer mode (HTTP TS buffer)
Run from the server in `/home/hex/astra`:
```sh
cd /home/hex/astra

# Start two HTTP TS sources (primary + backup).
ffmpeg -loglevel error -re -f lavfi -i testsrc=size=160x90:rate=25 \
  -f lavfi -i sine=frequency=1000 -c:v libx264 -preset veryfast -tune zerolatency \
  -g 50 -keyint_min 50 -sc_threshold 0 -c:a mp2 -f mpegts \
  -listen 1 http://127.0.0.1:18080/primary.ts &
PRIMARY_FF=$!
ffmpeg -loglevel error -re -f lavfi -i testsrc=size=160x90:rate=25 \
  -f lavfi -i sine=frequency=800 -c:v libx264 -preset veryfast -tune zerolatency \
  -g 50 -keyint_min 50 -sc_threshold 0 -c:a mp2 -f mpegts \
  -listen 1 http://127.0.0.1:18081/backup.ts &
BACKUP_FF=$!

./astra scripts/server.lua -p 9047 --data-dir ./data_buffer_9047 --web-dir ./web &
PID=$!
sleep 4

TOKEN=$(curl -s -X POST http://127.0.0.1:9047/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"admin","password":"admin"}' | \
  python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
AUTH=(-H "Authorization: Bearer $TOKEN")

# Quick buffer API sanity (no streaming).
curl -sS -X POST http://127.0.0.1:9047/api/v1/buffers/resources "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  --data-binary '{"id":"buffer_test","enable":true,"name":"Test","path":"/play/test","buffering_sec":8,"bandwidth_kbps":4000}'
curl -sS http://127.0.0.1:9047/api/v1/buffers/resources "${AUTH[@]}"
curl -sS -X POST http://127.0.0.1:9047/api/v1/buffers/resources/buffer_test/inputs "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  --data-binary '{"id":"in1","enable":true,"url":"http://1.2.3.4:8100/play/test","priority":0}'

# Enable buffer server.
curl -s -X PUT http://127.0.0.1:9047/api/v1/settings "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  --data-binary '{"buffer_enabled":true,"buffer_listen_port":8090}'

# Create buffer resource.
curl -s -X POST http://127.0.0.1:9047/api/v1/buffers/resources "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  --data-binary '{"id":"buffer_test","name":"Buffer Test","path":"/play/test","enable":true,"buffering_sec":8,"bandwidth_kbps":4000,"smart_start_enabled":true,"start_debug_enabled":true}'

# Add inputs (HTTP only).
curl -s -X POST http://127.0.0.1:9047/api/v1/buffers/resources/buffer_test/inputs "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  --data-binary '{"id":"input0","enable":true,"url":"http://127.0.0.1:18080/primary.ts","priority":0}'
curl -s -X POST http://127.0.0.1:9047/api/v1/buffers/resources/buffer_test/inputs "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  --data-binary '{"id":"input1","enable":true,"url":"http://127.0.0.1:18081/backup.ts","priority":1}'

curl -s -X POST http://127.0.0.1:9047/api/v1/buffers/reload "${AUTH[@]}"

sleep 2

# Validate TS sync bytes.
python3 - <<'PY'
import urllib.request
url = "http://127.0.0.1:8090/play/test"
data = urllib.request.urlopen(url, timeout=5).read(1880)
ok = all(data[i] == 0x47 for i in range(0, len(data), 188))
print("sync_ok", ok)
PY

# Smart start should produce checkpoints (debug enabled).
attempts=5
while [ "$attempts" -gt 0 ]; do
  if curl -s http://127.0.0.1:9047/api/v1/buffer-status/buffer_test "${AUTH[@]}" | grep -q 'smart_checkpoint'; then
    break
  fi
  attempts=$((attempts - 1))
  sleep 1
done
test "$attempts" -gt 0

# Failover: stop primary and expect switch to backup.
kill "$PRIMARY_FF"
sleep 4
curl -s http://127.0.0.1:9047/api/v1/buffer-status/buffer_test "${AUTH[@]}" | grep '"active_input_index":1'

# Force IDR parser mode.
curl -s -X PUT http://127.0.0.1:9047/api/v1/buffers/resources/buffer_test "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  --data-binary '{"path":"/play/test","enable":true,"start_debug_enabled":true,"keyframe_detect_mode":"idr_parse"}'
curl -s -X POST http://127.0.0.1:9047/api/v1/buffers/reload "${AUTH[@]}"

kill "$PID"
kill "$BACKUP_FF"
rm -rf ./data_buffer_9047

# NOTE: do not test adapters or DVB-related endpoints on this server (no DVB).
```

## Smoke tests for password policy + audit log
Run from the server in `/home/hex/astra`:
```sh
cd /home/hex/astra

cat > ./tmp_password_policy.json <<'JSON'
{
  "settings": {
    "password_min_length": 8,
    "password_require_letter": true,
    "password_require_number": true,
    "password_require_symbol": false,
    "password_require_mixed_case": false,
    "password_disallow_username": true
  }
}
JSON

./astra ./tmp_password_policy.json -p 9031 --data-dir ./data_policy_9031 --web-dir ./web &
PID=$!
sleep 3

COOKIE_JAR=$(mktemp)
curl -s -c "$COOKIE_JAR" -X POST http://127.0.0.1:9031/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"admin","password":"admin"}'

# Weak password should be rejected
curl -s -X POST http://127.0.0.1:9031/api/v1/users -b "$COOKIE_JAR" \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"weak_user","password":"short"}'

# Strong password should be accepted
curl -s -X POST http://127.0.0.1:9031/api/v1/users -b "$COOKIE_JAR" \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"strong_user","password":"Strong123"}'

curl -s http://127.0.0.1:9031/api/v1/audit -b "$COOKIE_JAR" | head -n 1

rm -f "$COOKIE_JAR"
kill "$PID"
rm -f ./tmp_password_policy.json
rm -rf ./data_policy_9031
```

## Smoke tests for transcode (ffmpeg)
Run from the server in `/home/hex/astra`:
```sh
cd /home/hex/astra

# Ensure no stale ffmpeg processes are holding the ports.
pids=$(pgrep -f "udp://127.0.0.1:12100" || true)
if [ -n "$pids" ]; then kill $pids; fi
pids=$(pgrep -f "udp://127.0.0.1:12110" || true)
if [ -n "$pids" ]; then kill $pids; fi

# Input generator (UDP MPEG-TS)
ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=1000 -c:v libx264 -preset veryfast -tune zerolatency \
  -g 50 -keyint_min 50 -sc_threshold 0 -c:a aac -b:a 128k -f mpegts \
  "udp://127.0.0.1:12100?pkt_size=1316" &
SRC_FF=$!

./astra ./fixtures/transcode_cpu.json -p 9005 --data-dir ./data_transcode --web-dir ./web &
TC_PID=$!
# Allow ffmpeg progress/bitrate to populate before checks.
sleep 30

COOKIE_JAR=$(mktemp)
curl -s -c "$COOKIE_JAR" -X POST http://127.0.0.1:9005/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  --data-binary '{"username":"admin","password":"admin"}'

# Transcode status should be RUNNING with progress/out_time_ms.
curl -s http://127.0.0.1:9005/api/v1/transcode-status/transcode_cpu_test -b "$COOKIE_JAR" \
  | grep '"state":"RUNNING"'
curl -s http://127.0.0.1:9005/api/v1/transcode-status/transcode_cpu_test -b "$COOKIE_JAR" \
  | grep 'out_time_ms'
curl -s http://127.0.0.1:9005/api/v1/transcode-status/transcode_cpu_test -b "$COOKIE_JAR" \
  | python3 - <<'PY'
import json, sys
data = json.load(sys.stdin)
out_rate = data.get("output_bitrate_kbps")
print("output_bitrate_kbps", out_rate)
assert out_rate is not None
print("input_bitrate_kbps", data.get("input_bitrate_kbps"))
print("active_input_url", data.get("active_input_url"))
print("ffmpeg_input_url", data.get("ffmpeg_input_url"))
assert data.get("ffmpeg_input_url") is not None
assert data.get("ffmpeg_input_url") == data.get("active_input_url")
assert "udp://127.0.0.1:12100" in data.get("ffmpeg_input_url", "")
PY

# Note: for UDP input bitrate probes, set transcode.input_probe_udp=true and
# an output watchdog probe_interval_sec > 0, then re-check input_bitrate_kbps.

# Trigger stall: stop input generator and expect alert + restart.
kill "$SRC_FF"
sleep 20
curl -s "http://127.0.0.1:9005/api/v1/alerts?limit=5&stream_id=transcode_cpu_test" -b "$COOKIE_JAR" \
  | grep 'TRANSCODE_STALL'

kill "$TC_PID"
ffmpeg_pids=$(pgrep -f "ffmpeg -hide_banner -progress" || true)
if [ -n "$ffmpeg_pids" ]; then kill $ffmpeg_pids; fi
rm -f "$COOKIE_JAR"
rm -rf ./data_transcode

# NOTE: do not test adapters or DVB-related endpoints on this server (no DVB).
```

## Smoke tests for UDP audio fix (optional)
Run from the server in `/home/hex/astra`:
```sh
cd /home/hex/astra

# Input generator with non-AAC audio (MP2).
ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:15000?pkt_size=1316" &
SRC_FF=$!

cat > ./tmp_audio_fix.json <<'JSON'
{
  "make_stream": [
    {
      "id": "audio_fix_demo",
      "name": "Audio Fix Demo",
      "enable": true,
      "input": ["udp://127.0.0.1:15000"],
      "output": [
        {
          "format": "udp",
          "addr": "127.0.0.1",
          "port": 15010,
          "audio_fix": {
            "enabled": true,
            "probe_interval_sec": 5,
            "probe_duration_sec": 2,
            "mismatch_hold_sec": 5,
            "restart_cooldown_sec": 60
          }
        }
      ]
    }
  ]
}
JSON

./astra ./tmp_audio_fix.json -p 9050 --data-dir ./data_audio_fix --web-dir ./web &
PID=$!
sleep 8

# Output should report AUDIO type 0x0F (AAC) after fix starts.
./astra scripts/analyze.lua -n 3 udp://127.0.0.1:15010 | grep 'AUDIO'

kill "$PID"
kill "$SRC_FF"
rm -f ./tmp_audio_fix.json
rm -rf ./data_audio_fix

# NOTE: do not test adapters or DVB-related endpoints on this server (no DVB).
```

## Smoke tests for SRT/RTSP bridge (optional, requires ffmpeg with srt/rtsp)
Run from the server in `/home/hex/astra`:
```sh
cd /home/hex/astra

# Ensure ffmpeg supports protocols (skip if missing).
ffmpeg -protocols | grep -E 'srt|rtsp' || true

# SRT output (ffmpeg forwards local UDP to SRT listener).
ffmpeg -loglevel error -re -f lavfi -i testsrc=size=128x128:rate=25 \
  -f lavfi -i sine=frequency=1000 -c:v mpeg2video -c:a mp2 -f mpegts \
  "udp://127.0.0.1:14100?pkt_size=1316" &
SRC_FF=$!

cat > ./tmp_srt_out.json <<'JSON'
{
  "make_stream": [
    {
      "id": "srt_out_demo",
      "name": "SRT Out Demo",
      "enable": true,
      "input": ["udp://127.0.0.1:14100"],
      "output": [
        { "format": "srt", "url": "srt://127.0.0.1:15100?mode=caller", "bridge_port": 14110 }
      ]
    }
  ]
}
JSON

./astra ./tmp_srt_out.json -p 9036 --data-dir ./data_srt_9036 --web-dir ./web &
PID=$!
sleep 4
ffmpeg -loglevel error -i "srt://127.0.0.1:15100?mode=listener" -t 2 -f null - || true

kill "$PID"
kill "$SRC_FF"
rm -f ./tmp_srt_out.json
rm -rf ./data_srt_9036

# NOTE: do not test adapters or DVB-related endpoints on this server (no DVB).
```

## Шаблон/контракт для новых модулей/скриптов
### Назначение
- Коротко: что делает модуль/скрипт и где используется (UI/API/stream/runtime).

### Входы/выходы
- Входы: CLI-опции, JSON-поля API, Lua-конфиги, ожидаемые типы.
- Выходы: HTTP ответы/коды, события, форматы данных, side-effects (файлы/сессии).

### Ошибки и поведение
- Ошибки: коды, текст, когда `astra.abort()`/`astra.exit()` допустимы.
- Идемпотентность: какие операции безопасны для повторов.

### Логирование
- Уровни: `error|warning|notice|info|debug` (см. `scripts/base.lua`).
- Что логируем: ключевые события, отказоустойчивость, источники ошибок.

### Конфигурация
- Где хранится: SQLite `settings`, JSON-импорт, CLI-флаги.
- Дефолты: откуда берутся (обычно `scripts/server.lua` / `scripts/stream.lua`).

### Naming/расположение файлов
- Lua-скрипты: `scripts/*.lua`.
- C-модули: `modules/<name>/` + `module.mk`.
- UI: `web/` (HTML/CSS/JS).

### Минимальная реализация (пример)
```lua
-- scripts/example.lua
dofile("scripts/base.lua")

options_usage = [[
    --flag VALUE      example option
]]

options = {
    ["--flag"] = function(idx)
        example_flag = argv[idx + 1]
        return 1
    end,
}

function main()
    log.info("example started")
end
```

### PR чеклист
- Обновлен `CHANGELOG.md` (дата/изменения/тесты).
- Для каждой фичи описаны acceptance criteria, а smoke tests расширены на новые
  публичные точки (адаптеры/DVB на сервере не проверяем).
- Smoke tests запущены на сервере и результат записан.
- README/AGENT/SKILL обновлены, если изменился публичный API/CLI/конфиги.
- Нет новых секретов в репозитории.
