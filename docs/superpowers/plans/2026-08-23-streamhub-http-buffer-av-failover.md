# Stream Hub HTTP Buffer A/V Failover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fail over HTTP buffer inputs on real MPEG-TS audio/video health, recover higher-priority inputs only after a stable interval, expose diagnostics, and safely publish managed buffer outputs to the dashboard.

**Architecture:** Keep TS parsing and reader ownership in `http_buffer.c`, but isolate threshold timing in a pure-C gate. Persist additive settings in SQLite, pass them through Lua to the C module, and expose status through the existing API/UI. Dashboard linking uses an explicit ownership marker and never overwrites unrelated streams.

**Tech Stack:** C99, MPEG-TS PSI/PES utilities, POSIX sockets, pthreads, Lua, SQLite, browser JavaScript/CSS, FFmpeg test fixtures.

---

### Task 1: Define deterministic health threshold semantics

**Files:**
- Create: `modules/http_buffer/http_buffer_health_gate.h`
- Create: `modules/http_buffer/http_buffer_health_gate_test.c`
- Create: `contrib/ci/test_http_buffer_helpers.sh`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Write failure and recovery timing tests**

```c
#include <assert.h>
#include "http_buffer_health_gate.h"

int main(void)
{
    http_buffer_health_gate_t gate = {0};
    http_buffer_health_gate_reset(&gate);

    assert(http_buffer_health_gate_observe(&gate, false, 1000, 5000, 2)
           == HTTP_BUFFER_HEALTH_HOLD);
    assert(http_buffer_health_gate_observe(&gate, false, 2000, 5000, 2)
           == HTTP_BUFFER_HEALTH_HOLD);
    assert(http_buffer_health_gate_observe(&gate, false, 5999, 5000, 2)
           == HTTP_BUFFER_HEALTH_HOLD);
    assert(http_buffer_health_gate_observe(&gate, false, 6000, 5000, 2)
           == HTTP_BUFFER_HEALTH_FAIL);

    assert(http_buffer_health_gate_observe(&gate, true, 7000, 5000, 2)
           == HTTP_BUFFER_HEALTH_OK);
    assert(gate.fail_checks == 0 && gate.unhealthy_since_ms == 0);

    http_buffer_health_gate_reset(&gate);
    assert(http_buffer_health_recovery_progress(&gate, true, 10000, 8000) == 0);
    assert(http_buffer_health_recovery_progress(&gate, true, 14000, 8000) == 4);
    assert(http_buffer_health_recovery_progress(&gate, true, 18000, 8000) == 8);
    assert(http_buffer_health_recovery_progress(&gate, false, 19000, 8000) == 0);
    return 0;
}
```

- [ ] **Step 2: Create and run the helper runner**

```sh
#!/bin/sh
set -eu
CC_BIN=${CC:-cc}
OUT=${TMPDIR:-/tmp}/stream-http-buffer-health-test
"$CC_BIN" -std=c99 -Wall -Wextra -Werror -Imodules/http_buffer \
    modules/http_buffer/http_buffer_health_gate_test.c -o "$OUT"
"$OUT"
printf '%s\n' 'HTTP buffer helper tests: OK.'
```

Run: `sh contrib/ci/test_http_buffer_helpers.sh`

Expected: compiler failure because the header does not exist.

- [ ] **Step 3: Implement the timing gate**

```c
#ifndef STREAM_HTTP_BUFFER_HEALTH_GATE_H
#define STREAM_HTTP_BUFFER_HEALTH_GATE_H

#include <stdbool.h>
#include <stdint.h>

typedef enum {
    HTTP_BUFFER_HEALTH_HOLD = 0,
    HTTP_BUFFER_HEALTH_OK = 1,
    HTTP_BUFFER_HEALTH_FAIL = 2,
} http_buffer_health_result_t;

typedef struct {
    uint32_t fail_checks;
    uint64_t unhealthy_since_ms;
    uint64_t healthy_since_ms;
} http_buffer_health_gate_t;

static inline void http_buffer_health_gate_reset(http_buffer_health_gate_t *gate)
{
    *gate = (http_buffer_health_gate_t){0};
}

static inline http_buffer_health_result_t http_buffer_health_gate_observe(
      http_buffer_health_gate_t *gate, bool healthy, uint64_t now_ms,
      uint32_t failover_ms, uint32_t required_checks)
{
    if(healthy)
    {
        gate->fail_checks = 0;
        gate->unhealthy_since_ms = 0;
        if(gate->healthy_since_ms == 0) gate->healthy_since_ms = now_ms;
        return HTTP_BUFFER_HEALTH_OK;
    }
    gate->healthy_since_ms = 0;
    if(gate->unhealthy_since_ms == 0) gate->unhealthy_since_ms = now_ms;
    if(gate->fail_checks != UINT32_MAX) gate->fail_checks++;
    if(gate->fail_checks >= required_checks
       && now_ms - gate->unhealthy_since_ms >= failover_ms)
        return HTTP_BUFFER_HEALTH_FAIL;
    return HTTP_BUFFER_HEALTH_HOLD;
}

static inline uint32_t http_buffer_health_recovery_progress(
      http_buffer_health_gate_t *gate, bool healthy, uint64_t now_ms,
      uint32_t return_delay_ms)
{
    if(!healthy) { gate->healthy_since_ms = 0; return 0; }
    if(gate->healthy_since_ms == 0) gate->healthy_since_ms = now_ms;
    uint64_t elapsed = now_ms - gate->healthy_since_ms;
    if(elapsed > return_delay_ms) elapsed = return_delay_ms;
    return (uint32_t)(elapsed / 1000ULL);
}

#endif
```

- [ ] **Step 4: Run the helper and add the CI step**

Run: `sh contrib/ci/test_http_buffer_helpers.sh`

Expected: `HTTP buffer helper tests: OK.`

Add to `.github/workflows/ci.yml`:

```yaml
      - name: HTTP buffer helper unit tests
        run: contrib/ci/test_http_buffer_helpers.sh
```

- [ ] **Step 5: Commit the health contract**

```bash
git add modules/http_buffer/http_buffer_health_gate.h modules/http_buffer/http_buffer_health_gate_test.c contrib/ci/test_http_buffer_helpers.sh .github/workflows/ci.yml
git commit -m "test: define HTTP buffer health timing"
```

### Task 2: Parse per-input PAT, PMT, A/V, and bitrate health

**Files:**
- Modify: `modules/http_buffer/http_buffer.c`

- [ ] **Step 1: Add health configuration and status fields**

Add to each buffer resource:

```c
bool health_require_video;
bool health_require_audio;
int health_min_bitrate_kbps;
int health_failover_sec;
int health_fail_checks;
bool health_current_ok;
uint64_t health_bitrate_kbps;
uint64_t health_last_video_ts;
uint64_t health_last_audio_ts;
uint32_t health_failures;
char health_reason[64];
int recovery_input_index;
```

Add to each input status:

```c
uint64_t last_health_ts;
uint64_t bitrate_kbps;
uint16_t video_pid;
uint16_t audio_pid;
uint32_t health_failures;
uint32_t recovery_progress_sec;
char health_reason[64];
```

- [ ] **Step 2: Add a private per-reader parser state**

```c
typedef struct {
    mpegts_psi_t *pat;
    mpegts_psi_t *pmt;
    uint16_t pmt_pid;
    uint16_t video_pid;
    uint16_t audio_pid;
    uint64_t last_pat_ms;
    uint64_t last_pmt_ms;
    uint64_t last_video_ms;
    uint64_t last_audio_ms;
    uint64_t window_started_ms;
    uint64_t bytes_window;
    uint64_t bitrate_kbps;
    uint8_t scan[TS_PACKET_SIZE * 2];
    size_t scan_size;
    http_buffer_health_gate_t gate;
} input_health_t;
```

Initialize PAT with `mpegts_psi_init(MPEGTS_PACKET_PAT, 0)` and destroy both PSI
objects in every reader exit path.

- [ ] **Step 3: Parse PAT and PMT using existing MPEG-TS macros**

PAT callback selects the first non-zero program, recreates the PMT PSI object
when its PID changes, and clears the old A/V PIDs. PMT parsing chooses the first
supported video and audio elementary streams. Use the same stream-type constants
already recognized by Stream's analyzer; do not identify audio/video solely from
PID activity.

The packet feed must first restore 188-byte alignment, then call PSI muxers and
update `last_video_ms`/`last_audio_ms` only for packets with payload on the
selected PIDs.

- [ ] **Step 4: Evaluate a health sample**

```c
const bool bitrate_ok = health->bitrate_kbps
    >= (uint64_t)res->health_min_bitrate_kbps;
const bool pat_ok = health->last_pat_ms != 0;
const bool pmt_ok = health->last_pmt_ms != 0;
const uint64_t recent_ms = (uint64_t)res->health_failover_sec * 1000ULL;
const bool video_ok = !res->health_require_video
    || (health->video_pid && health->last_video_ms && now >= health->last_video_ms
        && now - health->last_video_ms <= recent_ms);
const bool audio_ok = !res->health_require_audio
    || (health->audio_pid && health->last_audio_ms && now >= health->last_audio_ms
        && now - health->last_audio_ms <= recent_ms);
const bool healthy = bitrate_ok && pat_ok && pmt_ok && video_ok && audio_ok;
```

Set one stable reason in this order: `no_bitrate`, `no_pat`, `no_pmt`,
`no_video`, `no_audio`. Feed `healthy` into `http_buffer_health_gate_observe()`.

- [ ] **Step 5: Fail active input only after both gates**

The reader may request a lower-priority input only when the gate returns
`HTTP_BUFFER_HEALTH_FAIL`. A healthy sample resets failure counters. Preserve
the existing no-data timeout as an independent hard failure.

- [ ] **Step 6: Probe recovery without replacing the active reader**

Each higher-priority probe owns its own `input_health_t`. Publish recovery
progress with `http_buffer_health_recovery_progress()` and switch only when the
result reaches `backup_return_delay_sec`. Clear `recovery_input_index` when the
probe stops, fails, or becomes active.

- [ ] **Step 7: Parse defaults and expose complete status**

Lua configuration defaults:

```c
res->health_require_video = lua_isnil(L, -1) ? true : lua_toboolean(L, -1);
res->health_require_audio = lua_isnil(L, -1) ? true : lua_toboolean(L, -1);
if(res->health_min_bitrate_kbps <= 0) res->health_min_bitrate_kbps = 128;
if(res->health_failover_sec <= 0) res->health_failover_sec = 5;
if(res->health_fail_checks <= 0) res->health_fail_checks = 2;
```

Expose resource health plus per-input `bitrate_kbps`, `video_pid`, `audio_pid`,
`health_failures`, `recovery_progress_sec`, and `health_reason`.

- [ ] **Step 8: Add bounded client socket behavior**

For accepted client sockets, set `SO_SNDTIMEO` and `SO_KEEPALIVE`. Under
`#ifdef TCP_USER_TIMEOUT`, set a timeout matching the send timeout. Log failures
at debug level; unsupported socket options must not abort the listener.

- [ ] **Step 9: Build and run helper checks**

Run: `sh contrib/ci/test_http_buffer_helpers.sh && ./configure.sh && make -j4 && git diff --check`

Expected: pass with no new warnings attributable to `http_buffer.c`.

- [ ] **Step 10: Commit the C dataplane change**

```bash
git add modules/http_buffer/http_buffer.c
git commit -m "feat: fail over buffers on MPEG-TS A/V health"
```

### Task 3: Persist and pass A/V health settings

**Files:**
- Modify: `scripts/config.lua`
- Modify: `scripts/buffer.lua`
- Modify: `scripts/api.lua`
- Create: `scripts/tests/buffer_av_failover_config_unit.lua`
- Create: `scripts/tests/config_migration_duplicate_column_unit.lua`

- [ ] **Step 1: Add a failing additive-migration and round-trip test**

Create an isolated database, save a resource with all five settings, reload it,
and assert:

```lua
assert_true(row.health_require_video == 1)
assert_true(row.health_require_audio == 1)
assert_true(row.health_min_bitrate_kbps == 256)
assert_true(row.health_failover_sec == 7)
assert_true(row.health_fail_checks == 3)
```

Re-open the same database a second time to prove the versioned migration is
idempotent. In the duplicate-column test, construct a database where the first
new health column exists but `schema_version` is one step behind, then require
startup to advance the version without aborting.

- [ ] **Step 2: Run the test and confirm the columns are absent**

Run: `./stream scripts/tests/buffer_av_failover_config_unit.lua`

Expected: FAIL for a missing health column or field; the partial-schema fixture
also exposes the current duplicate-column abort.

- [ ] **Step 3: Make single-column migrations recoverable**

Add the normalized SQLite error helper:

```lua
local function sqlite_error_text(err)
    if type(err) == "table" then
        if type(err.message) == "string" and err.message ~= "" then return err.message end
        if type(err.error) == "string" and err.error ~= "" then return err.error end
        if type(err.msg) == "string" and err.msg ~= "" then return err.msg end
    end
    return tostring(err or "")
end
```

If one migration containing exactly one `ALTER TABLE ... ADD COLUMN` rolls back
with `duplicate column name`, advance `schema_version` for that step in a new
transaction. All other migration errors remain fatal.

- [ ] **Step 4: Append one migration entry per column**

```sql
ALTER TABLE buffer_resources ADD COLUMN health_require_video INTEGER NOT NULL DEFAULT 1;
```

```sql
ALTER TABLE buffer_resources ADD COLUMN health_require_audio INTEGER NOT NULL DEFAULT 1;
```

```sql
ALTER TABLE buffer_resources ADD COLUMN health_min_bitrate_kbps INTEGER NOT NULL DEFAULT 128;
```

```sql
ALTER TABLE buffer_resources ADD COLUMN health_failover_sec INTEGER NOT NULL DEFAULT 5;
```

```sql
ALTER TABLE buffer_resources ADD COLUMN health_fail_checks INTEGER NOT NULL DEFAULT 2;
```

Do not combine the statements and do not edit a released migration entry.

- [ ] **Step 5: Extend read/write normalization**

Add the five columns to numeric conversion, `fields`, UPDATE, INSERT column,
and INSERT value lists. Clamp `health_min_bitrate_kbps`,
`health_failover_sec`, and `health_fail_checks` to at least 1 in the API
validation path.

- [ ] **Step 6: Pass settings to `http_buffer` and return them from the API**

In `scripts/buffer.lua`:

```lua
health_require_video = row.health_require_video ~= 0,
health_require_audio = row.health_require_audio ~= 0,
health_min_bitrate_kbps = row.health_min_bitrate_kbps,
health_failover_sec = row.health_failover_sec,
health_fail_checks = row.health_fail_checks,
```

Mirror the same fields in `buffer_resource_payload()`.

- [ ] **Step 7: Run configuration and API regressions**

Run:

```bash
./stream scripts/tests/buffer_av_failover_config_unit.lua
./stream scripts/tests/config_migration_duplicate_column_unit.lua
```

Expected: both pass.

- [ ] **Step 8: Commit persistence and API fields**

```bash
git add scripts/config.lua scripts/buffer.lua scripts/api.lua scripts/tests/buffer_av_failover_config_unit.lua scripts/tests/config_migration_duplicate_column_unit.lua
git commit -m "feat: configure HTTP buffer A/V health"
```

### Task 4: Add safe managed dashboard publication

**Files:**
- Modify: `scripts/config.lua`
- Modify: `scripts/api.lua`
- Create: `scripts/tests/buffer_dashboard_link_unit.lua`

- [ ] **Step 1: Write ownership and collision tests**

Cover these cases:

```lua
-- Missing target: create a stream containing buffer_managed_resource_id.
-- Compatible manual target: link with managed=false and do not rewrite it.
-- Occupied incompatible ID: return an error containing "conflict".
-- Delete: remove only the stream carrying the matching ownership marker.
```

Use local URLs such as `http://127.0.0.1:8089/channel`; do not put deployed
addresses in fixtures.

- [ ] **Step 2: Add ownership columns and link table as three migrations**

```sql
ALTER TABLE buffer_resources ADD COLUMN publish_to_dashboard INTEGER NOT NULL DEFAULT 0;
```

```sql
ALTER TABLE buffer_resources ADD COLUMN dashboard_stream_id TEXT NOT NULL DEFAULT '';
```

```sql
CREATE TABLE IF NOT EXISTS buffer_stream_links (
    resource_id TEXT PRIMARY KEY,
    stream_id TEXT NOT NULL,
    managed INTEGER NOT NULL DEFAULT 0,
    created INTEGER NOT NULL,
    updated INTEGER NOT NULL
);
```

Default publication to `0` for existing and new installations; users opt in.

- [ ] **Step 3: Implement normalized local output identity**

```lua
local function buffer_stream_id(row)
    local id = tostring(row.dashboard_stream_id or "")
    if id == "" then id = tostring(row.id or "buffer_stream") end
    return id
end

local function buffer_local_url(row)
    local port = tonumber(config.get_setting("buffer_listen_port")) or 8089
    return "http://127.0.0.1:" .. tostring(port) .. normalize_buffer_path(row.path)
end
```

- [ ] **Step 4: Implement create, link, conflict, and delete rules**

`config.sync_buffer_dashboard_stream(resource_id)` may update a stream only
when `stream.config.buffer_managed_resource_id == resource_id`. If an existing
stream already points to the exact local URL without the marker, save a
non-managed link. Otherwise return `dashboard stream id conflict: <id>`.

Created streams contain:

```lua
{
    id = stream_id,
    name = row.name,
    enable = row.enable ~= 0,
    input = { url },
    buffer_managed_resource_id = resource_id,
}
```

- [ ] **Step 5: Call synchronization after a successful resource save**

In the existing `apply_config_change()` apply callback, save the resource, call
the sync function, and raise the returned conflict so the revision fails
atomically. On deletion, remove the link and only a matching managed stream.

- [ ] **Step 6: Run ownership tests**

Run: `./stream scripts/tests/buffer_dashboard_link_unit.lua`

Expected: creation, manual link, collision protection, and safe deletion pass.

- [ ] **Step 7: Commit managed publication**

```bash
git add scripts/config.lua scripts/api.lua scripts/tests/buffer_dashboard_link_unit.lua
git commit -m "feat: publish managed buffer streams safely"
```

### Task 5: Expose health controls and diagnostics in the existing UI

**Files:**
- Modify: `web/index.html`
- Modify: `web/app.js`
- Modify: `web/styles.css`

- [ ] **Step 1: Add five health controls and optional dashboard fields**

Use these exact IDs in the buffer editor:

```html
<input type="checkbox" id="buffer-health-require-video" checked />
<input type="checkbox" id="buffer-health-require-audio" checked />
<input type="number" id="buffer-health-min-bitrate" min="1" value="128" />
<input type="number" id="buffer-health-failover-sec" min="1" value="5" />
<input type="number" id="buffer-health-fail-checks" min="1" value="2" />
<input type="checkbox" id="buffer-publish-dashboard" />
<input type="text" id="buffer-dashboard-stream-id" placeholder="From buffer ID" />
<div id="buffer-dashboard-status" class="buffer-link-status muted">Not published</div>
```

- [ ] **Step 2: Bind load, preset, and save paths**

The save payload includes:

```js
health_require_video: elements.bufferHealthRequireVideo.checked,
health_require_audio: elements.bufferHealthRequireAudio.checked,
health_min_bitrate_kbps: toNumber(elements.bufferHealthMinBitrate.value) ?? 128,
health_failover_sec: toNumber(elements.bufferHealthFailoverSec.value) ?? 5,
health_fail_checks: toNumber(elements.bufferHealthFailChecks.value) ?? 2,
publish_to_dashboard: elements.bufferPublishDashboard.checked,
dashboard_stream_id: elements.bufferDashboardStreamId.value.trim(),
```

- [ ] **Step 3: Render input health without hiding CC/PES state**

For every input render bitrate, `V:<pid>`, `A:<pid>`, failure reason, and
`RECOVERING current/target s`. Keep existing transport-error badges and do not
alter CC/PES thresholds.

- [ ] **Step 4: Add minimal state styling**

```css
.buffer-link-status[data-state="managed"],
.buffer-link-status[data-state="linked"] { color: var(--success); }
.buffer-link-status[data-state="conflict"] { color: var(--danger); }
.buffer-health-detail { font-variant-numeric: tabular-nums; }
```

- [ ] **Step 5: Run browser-surface static checks**

Run:

```bash
node --check web/app.js
rg -n "buffer-health-(require-video|require-audio|min-bitrate|failover-sec|fail-checks)" web/index.html web/app.js
git diff --check
```

Expected: syntax passes and every ID appears in both HTML and JavaScript.

- [ ] **Step 6: Commit the UI**

```bash
git add web/index.html web/app.js web/styles.css
git commit -m "feat: show HTTP buffer A/V recovery health"
```

### Task 6: Build a deterministic A/V failover smoke

**Files:**
- Create: `tools/loop_ts_http.py`
- Create: `contrib/ci/smoke_http_buffer_av_failover.sh`
- Create: `scripts/tests/buffer_av_health_canary.lua`

- [ ] **Step 1: Generalize the loop source without deployed configuration**

`loop_ts_http.py` accepts `--file`, `--host`, `--port`, and optional
`--drop-video-after`/`--drop-audio-after`. It reads 188-byte packets, discovers
PIDs from `ffprobe` supplied by the shell smoke, and filters only the requested
payload PID after the trigger. It never embeds a server address or channel ID.

- [ ] **Step 2: Generate independent primary and backup fixtures**

```bash
ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc=size=320x180:rate=25 \
  -f lavfi -i sine=frequency=700 -t 60 -c:v mpeg2video -c:a mp2 \
  -f mpegts "$TMP_ROOT/primary.ts"
ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=blue:size=320x180:rate=25 \
  -f lavfi -i sine=frequency=1200 -t 60 -c:v mpeg2video -c:a mp2 \
  -f mpegts "$TMP_ROOT/backup.ts"
```

- [ ] **Step 3: Configure a local active buffer canary**

Use defaults `health_require_video=true`, `health_require_audio=true`,
`health_min_bitrate_kbps=128`, `health_failover_sec=5`, `health_fail_checks=2`,
and `backup_return_delay_sec=8` on two localhost inputs.

- [ ] **Step 4: Assert failure and recovery surfaces**

The smoke must prove:

- primary becomes active and reports non-zero video/audio PIDs;
- dropping primary audio produces `health_reason=no_audio`;
- active input changes to backup no sooner than the configured gates;
- primary recovery is probed without interrupting backup;
- return occurs only after eight healthy seconds;
- FFmpeg decodes both audio and video throughout the output capture;
- CC/PES thresholds and counters are not disabled or reset by health logic.

- [ ] **Step 5: Run twice and inspect logs**

Run: `contrib/ci/smoke_http_buffer_av_failover.sh && contrib/ci/smoke_http_buffer_av_failover.sh`

Expected: both runs exit 0 with bounded failover and recovery times.

- [ ] **Step 6: Commit the smoke tools**

```bash
git add tools/loop_ts_http.py contrib/ci/smoke_http_buffer_av_failover.sh scripts/tests/buffer_av_health_canary.lua
git commit -m "test: prove HTTP buffer A/V failover"
```
