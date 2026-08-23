# Stream Hub Native HLS Playout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pace burst-delivered HLS transport streams from the MPEG-TS media clock, prevent repeated media/NULL oscillation, and stop active segments from being downloaded twice.

**Architecture:** Extract PCR-rate and prebuffer decisions into a pure-C helper tested independently, then call it from the existing `playout` module. Keep the analyzer before playout. Fix HLS queue ownership in Lua so an active sequence stays reserved until completion.

**Tech Stack:** C99, MPEG-TS PCR, Lua, POSIX shell, Stream playout and HLS input modules.

---

### Task 1: Define and test the media-clock helper

**Files:**
- Create: `modules/mpegts/playout_clock.h`
- Create: `modules/mpegts/playout_clock_test.c`
- Create: `contrib/ci/test_playout_helpers.sh`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Write tests for normal PCR rate, wrap, discontinuity, and prebuffer state**

```c
#include <assert.h>
#include <math.h>
#include "playout_clock.h"

int main(void)
{
    playout_clock_t clock = {0};
    double sample = 0.0;

    assert(!playout_clock_observe(&clock, 256, 1000, 188, &sample));
    clock.packets_since_pcr = 3990;
    assert(playout_clock_observe(&clock, 256, 27001000, 188, &sample));
    assert(sample > 5900000.0 && sample < 6100000.0);

    playout_clock_reset(&clock);
    assert(!playout_clock_observe(&clock, 256, PLAYOUT_PCR_MAX_TICKS - 1000, 188, &sample));
    clock.packets_since_pcr = 3990;
    assert(playout_clock_observe(&clock, 256, 26999000, 188, &sample));

    assert(playout_prebuffer_next(true, 1, 499, 500));
    assert(!playout_prebuffer_next(true, 1, 500, 500));
    assert(!playout_prebuffer_next(false, 1, 100, 500));
    assert(playout_prebuffer_next(false, 0, 0, 500));
    return 0;
}
```

- [ ] **Step 2: Create a runner and confirm the header is missing**

```sh
#!/bin/sh
set -eu
CC_BIN=${CC:-cc}
OUT=${TMPDIR:-/tmp}/stream-playout-clock-test
"$CC_BIN" -std=c99 -Wall -Wextra -Werror -Imodules/mpegts \
    modules/mpegts/playout_clock_test.c -o "$OUT"
"$OUT"
printf '%s\n' 'Playout helper tests: OK.'
```

Run: `sh contrib/ci/test_playout_helpers.sh`

Expected: compiler failure for missing `playout_clock.h`.

- [ ] **Step 3: Implement the pure helper**

```c
#ifndef STREAM_PLAYOUT_CLOCK_H
#define STREAM_PLAYOUT_CLOCK_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PLAYOUT_PCR_MAX_TICKS ((1ULL << 33) * 300ULL)
#define PLAYOUT_PCR_HZ 27000000ULL

typedef struct {
    double bitrate_bps_ema;
    uint16_t pcr_pid;
    bool pcr_seen;
    uint64_t last_pcr;
    uint64_t packets_since_pcr;
} playout_clock_t;

static inline void playout_clock_reset(playout_clock_t *clock)
{
    *clock = (playout_clock_t){0};
}

static inline void playout_clock_count_packet(playout_clock_t *clock)
{
    if(clock->packets_since_pcr != UINT64_MAX)
        clock->packets_since_pcr++;
}

static inline bool playout_clock_observe(playout_clock_t *clock,
      uint16_t pid, uint64_t current, size_t packet_size, double *sample_bps)
{
    if(!clock->pcr_seen || pid != clock->pcr_pid)
    {
        clock->pcr_pid = pid;
        clock->last_pcr = current;
        clock->packets_since_pcr = 0;
        clock->pcr_seen = true;
        return false;
    }
    const uint64_t delta = current >= clock->last_pcr
        ? current - clock->last_pcr
        : PLAYOUT_PCR_MAX_TICKS - clock->last_pcr + current;
    const uint64_t packets = clock->packets_since_pcr;
    clock->last_pcr = current;
    clock->packets_since_pcr = 0;
    if(delta == 0 || delta > PLAYOUT_PCR_HZ * 5ULL || packets == 0)
        return false;
    const size_t bytes = packet_size ? packet_size : 188U;
    const double instant = ((double)packets * (double)bytes * 8.0)
        / ((double)delta / (double)PLAYOUT_PCR_HZ);
    if(instant < 100000.0 || instant > 200000000.0)
        return false;
    clock->bitrate_bps_ema = clock->bitrate_bps_ema <= 0.0
        ? instant : clock->bitrate_bps_ema * 0.8 + instant * 0.2;
    if(sample_bps) *sample_bps = instant;
    return true;
}

static inline bool playout_prebuffer_next(bool current, size_t count,
      uint64_t fill_ms, uint32_t min_fill_ms)
{
    if(min_fill_ms == 0) return false;
    if(current && count > 0 && fill_ms >= min_fill_ms) return false;
    if(!current && count == 0) return true;
    return current;
}

#endif
```

- [ ] **Step 4: Run the helper and add it to CI**

Run: `sh contrib/ci/test_playout_helpers.sh`

Expected: `Playout helper tests: OK.`

Add to `.github/workflows/ci.yml`:

```yaml
      - name: Playout helper unit tests
        run: contrib/ci/test_playout_helpers.sh
```

- [ ] **Step 5: Commit the helper contract**

```bash
git add modules/mpegts/playout_clock.h modules/mpegts/playout_clock_test.c contrib/ci/test_playout_helpers.sh .github/workflows/ci.yml
git commit -m "test: define HLS playout clock behavior"
```

### Task 2: Use PCR rate and stateful prebuffering in playout

**Files:**
- Modify: `modules/mpegts/playout.c`

- [ ] **Step 1: Add the clock and prebuffer state**

```c
#include "playout_clock.h"

playout_clock_t media_clock;
bool prebuffering;
```

Remove duplicated PCR state from `module_data_t`; the helper owns it.

- [ ] **Step 2: Feed every input packet into the media clock**

```c
playout_clock_count_packet(&mod->media_clock);
if(TS_IS_PCR(ts))
    playout_clock_observe(&mod->media_clock, TS_GET_PID(ts), TS_GET_PCR(ts),
                          TS_PACKET_SIZE, NULL);
```

Call this before the packet is stored in the ring buffer.

- [ ] **Step 3: Prefer media-clock bitrate in auto mode**

```c
if(mod->media_clock.bitrate_bps_ema > 0.0)
    bps = (uint64_t)mod->media_clock.bitrate_bps_ema;
else if(mod->in_bitrate_bps_ema > 0.0)
    bps = (uint64_t)mod->in_bitrate_bps_ema;
else
    bps = mod->config.assumed_bitrate_bps;
```

CBR mode remains unchanged.

- [ ] **Step 4: Replace the permanent low-water gate**

```c
mod->prebuffering = playout_prebuffer_next(
    mod->prebuffering, mod->count, fill_ms, mod->config.min_fill_ms);
const bool prebuffer = mod->prebuffering;
```

Initialize `prebuffering` from `min_fill_ms > 0`. Do not re-enter prebuffering
merely because fill drops below the threshold; only an empty buffer resets it.

- [ ] **Step 5: Expose distinct diagnostic rates**

Add to `method_stats()`:

```c
lua_pushnumber(lua, (lua_Number)(mod->media_clock.bitrate_bps_ema / 1000.0));
lua_setfield(lua, -2, "media_kbps");
lua_pushnumber(lua, (lua_Number)(mod->in_bitrate_bps_ema / 1000.0));
lua_setfield(lua, -2, "arrival_kbps");
lua_pushboolean(lua, mod->prebuffering);
lua_setfield(lua, -2, "prebuffering");
```

- [ ] **Step 6: Run helper, build, and diff checks**

Run: `sh contrib/ci/test_playout_helpers.sh && ./configure.sh && make -j4 && git diff --check`

Expected: test and build pass.

- [ ] **Step 7: Commit playout integration**

```bash
git add modules/mpegts/playout.c
git commit -m "fix: pace native HLS from the media clock"
```

### Task 3: Prevent active HLS segment duplication

**Files:**
- Create: `scripts/tests/hls_active_segment_dedup_unit.lua`
- Modify: `scripts/base.lua`

- [ ] **Step 1: Add the active-segment regression test**

Use a stubbed `timer` and `http_request`, initialize one HLS input, return a
playlist containing sequence 100 twice, and assert:

```lua
assert_true(instance.active_seq == 100, "segment 100 must be active")
assert_true(instance.queued[100] == true, "active segment must remain reserved")
assert_true(#instance.queue == 0, "active segment must not remain queued")

instance.request_playlist()
requests[3].opts.callback(requests[3], { code = 200, content = playlist })
assert_true(instance.active_seq == 100, "refresh must not replace active segment")
assert_true(#instance.queue == 0, "refresh must not enqueue active segment")
```

Complete the active request and assert `last_seq == 100`, `active_seq == nil`,
and `queued[100] == nil`.

- [ ] **Step 2: Run the regression against the current queue behavior**

Run: `./stream scripts/tests/hls_active_segment_dedup_unit.lua`

Expected: FAIL because `hls_start_next_segment()` clears the reservation when
the item becomes active.

- [ ] **Step 3: Keep active ownership until completion**

In `hls_start_next_segment()`, remove:

```lua
instance.queued[item.seq] = nil
```

On successful completion, permanent retry exhaustion, invalid URL, unsupported
HTTPS, and request-construction failure, clear the active reservation with:

```lua
if instance.active_seq ~= nil then
    instance.queued[instance.active_seq] = nil
end
instance.active_seq = nil
```

On explicit retry, retain `queued[item.seq] = true`.

- [ ] **Step 4: Exclude the active sequence during playlist import and rollback reset**

```lua
if instance.active_seq ~= nil then
    instance.queued[instance.active_seq] = true
end

if item.seq ~= instance.active_seq
    and (not instance.last_seq or item.seq > instance.last_seq)
    and not instance.queued[item.seq]
then
    table.insert(instance.queue, item)
    instance.queued[item.seq] = true
end
```

- [ ] **Step 5: Run HLS and existing Lua tests**

Run:

```bash
./stream scripts/tests/hls_active_segment_dedup_unit.lua
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
```

Expected: both pass.

- [ ] **Step 6: Commit queue ownership**

```bash
git add scripts/base.lua scripts/tests/hls_active_segment_dedup_unit.lua
git commit -m "fix: reserve active HLS segments until completion"
```

### Task 4: Add a deterministic burst-HLS smoke

**Files:**
- Create: `contrib/ci/smoke_native_hls_playout.sh`

- [ ] **Step 1: Build a short PCR-bearing fixture and burst HTTP source**

The smoke must generate a 25-second MPEG-TS fixture with FFmpeg, segment it as
HLS, serve files from localhost, and request the Stream output with playout
enabled. Use only generated color bars and sine audio.

```bash
ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc=size=320x180:rate=25 \
  -f lavfi -i sine=frequency=1000 -t 25 -c:v mpeg2video -c:a mp2 \
  -f hls -hls_time 2 -hls_list_size 0 "$TMP_ROOT/live.m3u8"
```

- [ ] **Step 2: Assert media pacing and decode output**

Collect module stats twice after startup and require:

- `media_kbps > 100`;
- `arrival_kbps >= media_kbps` for the local burst source;
- `prebuffering` changes from true to false;
- `null_packets_total` does not alternate upward on every media packet;
- FFmpeg decodes at least one video and one audio frame.

- [ ] **Step 3: Run the smoke twice**

Run: `contrib/ci/smoke_native_hls_playout.sh && contrib/ci/smoke_native_hls_playout.sh`

Expected: both runs exit 0 without duplicate segment requests.

- [ ] **Step 4: Commit the smoke**

```bash
git add contrib/ci/smoke_native_hls_playout.sh
git commit -m "test: cover burst HLS playout recovery"
```
