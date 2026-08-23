# Stream Hub SoftCAM CW Sequencing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve current Newcamd protocol fixes while isolating partial CW state per service and applying validated odd/even keys at the correct shift-buffer packet boundary.

**Architecture:** Keep `origin/main` as the protocol authority. Add small pure-C helpers for service-scoped CW caching, key validation timing, and bounded shift sizing; integrate them into the existing decryptor without replacing its immutable parallel-key context. Resolve `key_guard` at Lua stream construction time with input, CAM, then global precedence.

**Tech Stack:** C99, Stream module API, MPEG-TS/DVB-CSA, pthreads, Lua, POSIX shell, GitHub Actions on Ubuntu.

---

### Task 1: Add a repeatable SoftCAM helper test gate

**Files:**
- Create: `contrib/ci/test_softcam_helpers.sh`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the test runner with the initial CW guard test**

```sh
#!/bin/sh
set -eu

CC_BIN=${CC:-cc}
BUILD_DIR=${TMPDIR:-/tmp}/stream-softcam-helper-tests
mkdir -p "$BUILD_DIR"

run_test() {
    source_file=$1
    output_name=$2
    "$CC_BIN" -std=c99 -Wall -Wextra -Werror \
        -Imodules/softcam -Imodules/softcam/cam \
        "$source_file" -o "$BUILD_DIR/$output_name"
    "$BUILD_DIR/$output_name"
}

run_test modules/softcam/cam/newcamd_cw_guard_test.c newcamd_cw_guard_test
printf '%s\n' 'SoftCAM helper tests: OK.'
```

- [ ] **Step 2: Run the runner against the baseline**

Run: `sh contrib/ci/test_softcam_helpers.sh`

Expected: `SoftCAM helper tests: OK.`

- [ ] **Step 3: Add the runner to the Ubuntu `build-test` job before the full smoke**

```yaml
      - name: SoftCAM helper unit tests
        run: contrib/ci/test_softcam_helpers.sh
```

- [ ] **Step 4: Verify shell syntax and execute the gate**

Run: `sh -n contrib/ci/test_softcam_helpers.sh && sh contrib/ci/test_softcam_helpers.sh`

Expected: exit code 0 and `SoftCAM helper tests: OK.`

- [ ] **Step 5: Commit the test gate**

```bash
git add contrib/ci/test_softcam_helpers.sh .github/workflows/ci.yml
git commit -m "test: add SoftCAM helper gate"
```

### Task 2: Apply service-scoped partial CW caching

**Files:**
- Modify: `modules/softcam/cam/newcamd_cw_guard.h`
- Modify: `modules/softcam/cam/newcamd_cw_guard_test.c`

- [ ] **Step 1: Add the interleaved-service regression test from `c55ff297`**

Add a second decrypt identity and verify independent complementary halves:

```c
uint8_t decrypt_b;
const newcamd_cw_scope_t scope_service_b = { &decrypt_b, &arg_b, 1 };

newcamd_cw_cache_reset(&cache);
fill(full, sizeof(full), 0x11);
fill(&full[8], 8, 0x22);
assert(newcamd_cw_cache_merge(&cache, scope_a, full) == NEWCAMD_CW_ACCEPTED);

fill(full, sizeof(full), 0x55);
fill(&full[8], 8, 0x66);
assert(newcamd_cw_cache_merge(&cache, scope_service_b, full) == NEWCAMD_CW_ACCEPTED);

memset(even_only, 0, sizeof(even_only));
fill(even_only, 8, 0x33);
assert(newcamd_cw_cache_merge(&cache, scope_a, even_only) == NEWCAMD_CW_ACCEPTED);
fill(expected, 8, 0x33);
fill(&expected[8], 8, 0x22);
assert(memcmp(even_only, expected, sizeof(expected)) == 0);

memset(odd_only, 0, sizeof(odd_only));
fill(&odd_only[8], 8, 0x77);
assert(newcamd_cw_cache_merge(&cache, scope_service_b, odd_only) == NEWCAMD_CW_ACCEPTED);
fill(expected, 8, 0x55);
fill(&expected[8], 8, 0x77);
assert(memcmp(odd_only, expected, sizeof(expected)) == 0);
```

- [ ] **Step 2: Run the test and confirm the single-slot baseline fails**

Run: `sh contrib/ci/test_softcam_helpers.sh`

Expected: assertion failure when `scope_service_b` replaces `scope_a`.

- [ ] **Step 3: Introduce the bounded multi-scope cache**

Use these data structures and lookup/allocation helpers:

```c
#define NEWCAMD_CW_CACHE_SLOTS 16

typedef struct {
    uint8_t half[2][NEWCAMD_CW_HALF_SIZE];
    bool valid[2];
    bool scope_valid;
    newcamd_cw_scope_t scope;
} newcamd_cw_cache_slot_t;

typedef struct {
    newcamd_cw_cache_slot_t slot[NEWCAMD_CW_CACHE_SLOTS];
    size_t next_slot;
} newcamd_cw_cache_t;

static inline newcamd_cw_cache_slot_t *newcamd_cw_cache_find(
      newcamd_cw_cache_t *cache, newcamd_cw_scope_t scope)
{
    size_t i;
    for(i = 0; i < NEWCAMD_CW_CACHE_SLOTS; ++i)
        if(cache->slot[i].scope_valid
           && newcamd_cw_scope_matches(cache->slot[i].scope, scope))
            return &cache->slot[i];
    return NULL;
}

static inline newcamd_cw_cache_slot_t *newcamd_cw_cache_allocate(
      newcamd_cw_cache_t *cache)
{
    size_t i;
    for(i = 0; i < NEWCAMD_CW_CACHE_SLOTS; ++i)
        if(!cache->slot[i].scope_valid)
            return &cache->slot[i];
    i = cache->next_slot % NEWCAMD_CW_CACHE_SLOTS;
    cache->next_slot = (i + 1) % NEWCAMD_CW_CACHE_SLOTS;
    memset(&cache->slot[i], 0, sizeof(cache->slot[i]));
    return &cache->slot[i];
}
```

Update `newcamd_cw_cache_merge()` to read and write only the selected slot. If
no slot matches a partial response, return `NEWCAMD_CW_REJECTED_SCOPE` when any
other valid scope exists, otherwise return `NEWCAMD_CW_REJECTED_NO_CACHE`.

- [ ] **Step 4: Run the helper test and inspect the protocol diff**

Run: `sh contrib/ci/test_softcam_helpers.sh && git diff -- modules/softcam/cam/newcamd.c modules/softcam/cam/newcamd_cw_guard.h`

Expected: tests pass and `newcamd.c` remains unchanged.

- [ ] **Step 5: Commit the scoped cache**

```bash
git add modules/softcam/cam/newcamd_cw_guard.h modules/softcam/cam/newcamd_cw_guard_test.c
git commit -m "fix: isolate newcamd CW cache per service scope"
```

### Task 3: Add key-guard precedence without channel-specific canaries

**Files:**
- Modify: `scripts/base.lua`
- Create: `scripts/tests/softcam_key_guard_scope_unit.lua`

- [ ] **Step 1: Write the failing Lua precedence test**

```lua
log.set({ debug = true })
dofile("scripts/base.lua")

local function eq(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
    end
end

local global_value = false
config = { get_setting = function(key)
    if key == "softcam_key_guard" then return global_value end
end }

eq(stream_softcam_key_guard_resolve({}, {}), false, "global false")
global_value = true
eq(stream_softcam_key_guard_resolve({}, {}), true, "global true")
eq(stream_softcam_key_guard_resolve({ key_guard = "0" }, {}), false, "CAM override")
eq(stream_softcam_key_guard_resolve({ key_guard = "0" }, { key_guard = "1" }), true, "input override")
eq(stream_softcam_key_guard_resolve({ key_guard = "1" }, { key_guard = "invalid" }), false, "invalid explicit value")

print("softcam_key_guard_scope_unit: ok")
astra.exit()
```

- [ ] **Step 2: Run the test and confirm the resolver is absent**

Run: `./stream scripts/tests/softcam_key_guard_scope_unit.lua`

Expected: FAIL with `stream_softcam_key_guard_resolve` missing.

- [ ] **Step 3: Add the resolver next to `net_bool()`**

```lua
function stream_softcam_key_guard_resolve(cam_config, input_config)
    if type(input_config) == "table" and input_config.key_guard ~= nil then
        return net_bool(input_config.key_guard) == true
    end
    if type(cam_config) == "table" and cam_config.key_guard ~= nil then
        return net_bool(cam_config.key_guard) == true
    end
    if type(config) == "table" and type(config.get_setting) == "function" then
        return net_bool(config.get_setting("softcam_key_guard")) == true
    end
    return false
end
```

Replace the global-only block with:

```lua
local key_guard = stream_softcam_key_guard_resolve(
    opts and opts.raw_cfg or {},
    conf
)
```

- [ ] **Step 4: Run the Lua regression and syntax checks**

Run: `./stream scripts/tests/softcam_key_guard_scope_unit.lua && node --check web/app.js`

Expected: `softcam_key_guard_scope_unit: ok` and exit code 0.

- [ ] **Step 5: Commit the configuration behavior**

```bash
git add scripts/base.lua scripts/tests/softcam_key_guard_scope_unit.lua
git commit -m "feat: scope SoftCAM key guard per stream"
```

### Task 4: Add pure-C timing and shift-size helpers

**Files:**
- Create: `modules/softcam/decrypt_key_guard_timing.h`
- Create: `modules/softcam/decrypt_key_guard_timing_test.c`
- Create: `modules/softcam/decrypt_shift_size.h`
- Create: `modules/softcam/decrypt_shift_size_test.c`
- Modify: `contrib/ci/test_softcam_helpers.sh`

- [ ] **Step 1: Add timing tests for accept, reject, egress, and parity boundary**

Create `decrypt_key_guard_timing_test.c` with assertions that two valid samples
accept at the first valid sequence, four invalid samples reject, sequence 99
does not apply boundary 100, and a queued parity transition 80 is selected over
validated sequence 140 only while egress is below 80.

Core assertions:

```c
assert(decrypt_key_guard_timing_observe(&timing, true, 100, &apply_seq)
       == DECRYPT_KEY_GUARD_WAIT);
assert(decrypt_key_guard_timing_observe(&timing, true, 140, &apply_seq)
       == DECRYPT_KEY_GUARD_ACCEPT);
assert(apply_seq == 100);
assert(!decrypt_key_guard_timing_should_apply(99, apply_seq));
assert(decrypt_key_guard_timing_should_apply(100, apply_seq));
assert(decrypt_key_guard_timing_apply_boundary(80, 140, 60) == 80);
assert(decrypt_key_guard_timing_apply_boundary(80, 140, 90) == 140);
```

- [ ] **Step 2: Add shift-size tests**

```c
assert(decrypt_shift_size_bytes(0) == 0U);
assert(decrypt_shift_size_bytes(50) >= 6250000U);
assert(decrypt_shift_size_bytes(8000) >= 10000000U);
assert(decrypt_shift_size_bytes(60000) % 188U == 0U);
assert(decrypt_shift_size_bytes(60000) <= 16U * 1024U * 1024U);
```

- [ ] **Step 3: Run the expanded runner and confirm missing-header failures**

Add both test names to `test_softcam_helpers.sh`, then run it.

Expected: compiler failure because the two helper headers do not exist.

- [ ] **Step 4: Add the timing state machine**

```c
#define DECRYPT_KEY_GUARD_REQUIRED_OK 2
#define DECRYPT_KEY_GUARD_MAX_FAIL 4

typedef enum {
    DECRYPT_KEY_GUARD_WAIT = 0,
    DECRYPT_KEY_GUARD_ACCEPT = 1,
    DECRYPT_KEY_GUARD_REJECT = 2,
} decrypt_key_guard_result_t;

typedef struct {
    uint8_t ok_count;
    uint8_t fail_count;
    uint64_t first_ok_seq;
} decrypt_key_guard_timing_t;
```

Implement `reset`, `observe`, `should_apply`, and `apply_boundary` exactly as
specified by the assertions. Saturate counters at `UINT8_MAX`.

- [ ] **Step 5: Add bounded packet-aligned shift sizing**

```c
#define DECRYPT_SHIFT_PACKET_SIZE 188U
#define DECRYPT_SHIFT_ASSUME_MBIT 10U
#define DECRYPT_SHIFT_MAX_BYTES (16U * 1024U * 1024U)
#define DECRYPT_SHIFT_MAX_ALIGNED_BYTES \
    (DECRYPT_SHIFT_MAX_BYTES - (DECRYPT_SHIFT_MAX_BYTES % DECRYPT_SHIFT_PACKET_SIZE))
```

Convert legacy values below 100 to `value * 100 ms`, calculate bytes at 10
Mbit/s using `uint64_t`, round upward to 188-byte packets, and cap at
`DECRYPT_SHIFT_MAX_ALIGNED_BYTES`.

- [ ] **Step 6: Run the pure helper suite**

Run: `sh contrib/ci/test_softcam_helpers.sh`

Expected: all three binaries exit 0 and the runner prints its OK line.

- [ ] **Step 7: Commit the helpers**

```bash
git add modules/softcam/decrypt_key_guard_timing.h modules/softcam/decrypt_key_guard_timing_test.c modules/softcam/decrypt_shift_size.h modules/softcam/decrypt_shift_size_test.c contrib/ci/test_softcam_helpers.sh
git commit -m "test: define SoftCAM key timing boundaries"
```

### Task 5: Integrate sequence-aware candidate application

**Files:**
- Modify: `modules/softcam/decrypt.c`

- [ ] **Step 1: Include helpers and replace candidate counters with timing state**

```c
#include "decrypt_key_guard_timing.h"
#include "decrypt_shift_size.h"
```

Add to `ca_stream_t`:

```c
decrypt_key_guard_timing_t cand_timing;
uint8_t ingress_parity_mask;
uint64_t parity_start_seq[2];
uint64_t parity_start_us[2];
bool guarded_key_pending;
uint8_t guarded_key_mask;
uint8_t guarded_key[16];
bool guarded_key_from_backup;
uint64_t guarded_key_apply_seq;
```

Add `uint64_t ingress_seq` and `uint64_t egress_seq` to `mod->shift`. Reset both
in `stream_reload()` and reset `cand_timing` wherever candidate state is cleared
or initialized.

- [ ] **Step 2: Add the candidate accept/reject helpers**

`ca_stream_guard_accept()` copies the candidate into the accepted-key fields,
stores the apply sequence, and clears candidate validation state.
`ca_stream_guard_reject()` increments the correct primary/backup reject counter,
marks a bad backup, clears candidate state, clears `last_ecm_ok`, and increments
`ecm_fail_count` with saturation.

- [ ] **Step 3: Add ingress observation with odd/even parity tracking**

`ca_stream_guard_observe_ingress(mod, ts, pid, ingress_seq)` must:

```c
const uint8_t sc = TS_IS_SCRAMBLED(ts);
const uint8_t parity_mask = sc == 0x80 ? 1 : (sc == 0xC0 ? 2 : 0);
const int parity_index = parity_mask == 1 ? 0 : (parity_mask == 2 ? 1 : -1);
```

Record the first transition for the parity epoch, validate only matching
payload-start packets, expire candidates after 10 seconds, call
`decrypt_key_guard_timing_observe()`, and calculate the accepted boundary with
`decrypt_key_guard_timing_apply_boundary()`.

- [ ] **Step 4: Add egress application without disturbing packet order**

`ca_stream_guard_apply_due(mod, egress_seq, parallel)` first detects whether any
accepted key is due. For synchronous descrambling, flush the old-key batch,
stage every due key, then restart batching. For parallel descrambling, publish
the new immutable key context before queueing the boundary packet.

- [ ] **Step 5: Replace both duplicated post-shift validation blocks**

At ingress in `on_ts_parallel()` and `on_ts()`:

```c
const uint64_t ingress_seq = ++mod->shift.ingress_seq;
uint64_t egress_seq = ingress_seq;
ca_stream_guard_observe_ingress(mod, ts, pid, ingress_seq);
```

After a packet exits `mod->shift.buffer`, increment `egress_seq`; without a
shift buffer assign `mod->shift.egress_seq = ingress_seq`. Call
`ca_stream_guard_apply_due()` before queueing/copying the egress packet.

- [ ] **Step 6: Use the bounded shift helper and expose timing statistics**

Replace the inline shift calculation with `decrypt_shift_size_bytes(shift)`.
Add `ingress_seq` and `egress_seq` under `stats().shift`, use
`cand_timing.ok_count/fail_count`, and add an `accepted_key` table containing
`pending`, `mask`, and `apply_seq`.

- [ ] **Step 7: Run targeted and full build checks**

Run:

```bash
sh contrib/ci/test_softcam_helpers.sh
./configure.sh
make -j4
git diff --check
```

Expected: helper tests pass and the local build completes. On macOS, record the
expected warning that Newcamd itself is disabled; do not treat it as Linux
SoftCAM proof.

- [ ] **Step 8: Commit the decryptor integration**

```bash
git add modules/softcam/decrypt.c
git commit -m "fix: align guarded CW changes with packet parity"
```

### Task 6: Prove the Linux Newcamd build

**Files:**
- Modify: `contrib/ci/test_softcam_helpers.sh` only if the Linux compiler reveals portability errors

- [ ] **Step 1: Build in a clean Ubuntu-compatible environment**

Run:

```bash
./configure.sh
make -j"$(nproc)"
test -f modules/softcam/cam/newcamd.o
sh contrib/ci/test_softcam_helpers.sh
```

Expected: `newcamd.o` exists and every helper test passes.

- [ ] **Step 2: Run the repository smoke and safety gates**

Run:

```bash
contrib/ci/smoke.sh
scripts/ci/check_sensitive_data.sh --all
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 3: Commit only real portability fixes, if any**

```bash
git add contrib/ci/test_softcam_helpers.sh
git commit -m "fix: keep SoftCAM helper tests portable"
```

Skip this commit when the tree is unchanged.
