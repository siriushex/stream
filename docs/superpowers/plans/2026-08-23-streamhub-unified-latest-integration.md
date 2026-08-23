# Stream Hub Unified Latest Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate the independently tested SoftCAM, HLS, and HTTP buffer work into one traceable Stream Hub 1.3.0 release candidate without importing server runtime state.

**Architecture:** Complete each subsystem plan in order on `codex/streamhub-unified-latest`, keep commits independently revertible, then run one Linux verification matrix. Record source and binary provenance in release artifacts. GitHub publication and production deployment remain separate gated actions.

**Tech Stack:** Git, C99, Lua, JavaScript, SQLite, FFmpeg/ffprobe, POSIX shell, GitHub Actions, systemd deployment conventions.

---

### Task 1: Complete the three subsystem plans in dependency order

**Files:**
- Reference: `docs/superpowers/plans/2026-08-23-streamhub-softcam-cw-sequencing.md`
- Reference: `docs/superpowers/plans/2026-08-23-streamhub-native-hls-playout.md`
- Reference: `docs/superpowers/plans/2026-08-23-streamhub-http-buffer-av-failover.md`

- [ ] **Step 1: Execute and verify the SoftCAM plan**

Expected commits include scoped Newcamd cache, per-stream key guard, pure timing
helpers, and sequence-aware decryptor integration. Confirm `newcamd.c` retains
the response-ID and generation logic from `origin/main`.

- [ ] **Step 2: Execute and verify the native HLS plan**

Expected commits include PCR media-clock pacing, stateful prebuffering, and
active-segment reservation. Confirm analyzer placement remains before playout.

- [ ] **Step 3: Execute and verify the HTTP buffer plan**

Expected commits include the health gate, C dataplane, additive persistence,
managed dashboard link, UI, and deterministic failover smoke.

- [ ] **Step 4: Verify no server snapshot was copied wholesale**

Run:

```bash
git diff --stat 8822cbb1...HEAD
git diff --name-only 8822cbb1...HEAD | sort
git log --reverse --oneline 8822cbb1..HEAD
```

Expected: only reviewed source, tests, documentation, and CI files appear. No
`config.h`, binary, database, deployed JSON, minified copy, or `pol-sport3-hls`
file appears.

### Task 2: Add source and release provenance

**Files:**
- Modify: `scripts/release/build_stream_bundle.sh`
- Create: `scripts/release/write_stream_build_info.sh`
- Create: `scripts/tests/release_build_info_unit.sh`

- [ ] **Step 1: Add a failing release metadata test**

The test invokes `write_stream_build_info.sh` in a temporary staging directory
and requires these lines:

```text
Stream-Version: 1.3.0
Git-Commit: <40 lowercase hex characters>
Built-At-UTC: <ISO-8601 timestamp>
Binary-SHA256: <64 lowercase hex characters>
```

It must also fail when the working tree is dirty unless
`STREAM_ALLOW_DIRTY_BUILD=1` is explicitly set.

- [ ] **Step 2: Implement the standalone metadata writer**

The script accepts `binary output version arch profile`, resolves the repository
root from its own location, and refuses a dirty tree by default:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BINARY=$1
OUTPUT=$2
VERSION=$3
ARCH=$4
PROFILE=$5

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no)" \
      && "${STREAM_ALLOW_DIRTY_BUILD:-0}" != "1" ]]; then
  echo "Refusing to record provenance from a dirty source tree" >&2
  exit 1
fi

SHA256_CMD=(sha256sum)
if ! command -v sha256sum >/dev/null 2>&1; then SHA256_CMD=(shasum -a 256); fi
GIT_COMMIT=$(git -C "$ROOT_DIR" rev-parse HEAD)
BINARY_SHA256=$("${SHA256_CMD[@]}" "$BINARY" | awk '{print $1}')

{
  echo "Stream-Version: $VERSION"
  echo "Git-Commit: $GIT_COMMIT"
  echo "Built-At-UTC: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "Binary-SHA256: $BINARY_SHA256"
  echo "Architecture: $ARCH"
  echo "Profile: $PROFILE"
} > "$OUTPUT"
```

- [ ] **Step 3: Write `STREAM_BUILD_INFO.txt` into the bundle root**

After copying the binary, call:

```bash
"$ROOT_DIR/scripts/release/write_stream_build_info.sh" \
  "$STAGE_DIR/bin/stream" "$STAGE_DIR/STREAM_BUILD_INFO.txt" \
  "$VERSION" "$ARCH" "$PROFILE"
```

Write only version, commit, UTC time, binary hash, architecture, and profile.
Do not write local paths, usernames, hostnames, remotes containing credentials,
or configuration values.

- [ ] **Step 4: Run the metadata test and bundle smoke**

Run:

```bash
scripts/tests/release_build_info_unit.sh
scripts/release/build_stream_bundle.sh --arch linux-x86_64 --profile lgpl
```

Expected: the generated tarball contains `STREAM_BUILD_INFO.txt`, and its
binary hash matches the packaged binary.

- [ ] **Step 5: Commit provenance support**

```bash
git add scripts/release/build_stream_bundle.sh scripts/release/write_stream_build_info.sh scripts/tests/release_build_info_unit.sh
git commit -m "feat: record Stream release provenance"
```

### Task 3: Document the unified behavior and version it

**Files:**
- Modify: `.gitignore`
- Create: `CHANGELOG.md`
- Modify: `version.h`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/USAGE.md`
- Modify: `docs/DEVOPS.md`

- [ ] **Step 1: Allow the CI-required changelog and create the 1.3.0 entry**

Add `!/CHANGELOG.md` after the current changelog ignore rule. Create:

```markdown
# Changelog

## 1.3.0 - 2026-08-23

- Isolate partial Newcamd CW state per service and connection generation.
- Align guarded odd/even CW application with the shift-buffer packet boundary.
- Pace native HLS from PCR media time and make prebuffering stateful.
- Prevent active HLS segment duplication during playlist refresh.
- Add PAT/PMT/A/V-aware HTTP buffer failover and stable recovery probing.
- Add optional ownership-safe publication of buffer outputs to the dashboard.
- Record release commit, build time, and binary SHA-256 in bundles.
```

- [ ] **Step 2: Bump the product version after all subsystem tests pass**

```c
#define STREAM_VERSION "1.3.0"
```

Do not change the upstream Astra compatibility version `4.4.187`.

- [ ] **Step 3: Update architecture boundaries**

Document these flows:

```text
Newcamd response -> service-scoped CW merge -> candidate validation
-> parity apply sequence -> synchronous/parallel descramble context

HLS segment download -> pre-playout analyzer -> playout ring
-> PCR-derived pacing -> HTTP/UDP consumers

HTTP input -> PAT/PMT/A/V health -> failure/recovery gate
-> active input selector -> client ring
```

- [ ] **Step 4: Update usage and operations guidance**

Document all five buffer health fields, per-stream `key_guard` precedence,
`media_kbps` versus `arrival_kbps`, CW timing counters, Linux Newcamd build
proof, and the requirement that CC/PES thresholds remain enabled.

- [ ] **Step 5: Run public documentation and version checks**

Run:

```bash
contrib/ci/check_public_docs.sh
scripts/ci/check_docs_seo.sh
rg -n 'STREAM_VERSION "1.3.0"' version.h
git diff --check
```

Expected: all checks pass and exactly one product version definition matches.

- [ ] **Step 6: Commit release documentation**

```bash
git add .gitignore CHANGELOG.md version.h docs/ARCHITECTURE.md docs/USAGE.md docs/DEVOPS.md
git commit -m "docs: prepare Stream Hub 1.3.0"
```

### Task 4: Run the complete Linux verification matrix

**Files:**
- Modify: only files required by demonstrated portability or test failures

- [ ] **Step 1: Start from a clean build tree**

Run:

```bash
git status --short
./configure.sh
make -j"$(nproc)"
test -f stream
test -f modules/softcam/cam/newcamd.o
```

Expected: clean source state before configure; build completes with Newcamd.

- [ ] **Step 2: Run all new targeted tests**

Run:

```bash
contrib/ci/test_softcam_helpers.sh
contrib/ci/test_playout_helpers.sh
contrib/ci/test_http_buffer_helpers.sh
./stream scripts/tests/softcam_key_guard_scope_unit.lua
./stream scripts/tests/hls_active_segment_dedup_unit.lua
./stream scripts/tests/buffer_av_failover_config_unit.lua
./stream scripts/tests/buffer_dashboard_link_unit.lua
contrib/ci/smoke_native_hls_playout.sh
contrib/ci/smoke_http_buffer_av_failover.sh
```

Expected: every command exits 0.

- [ ] **Step 3: Run existing repository regressions**

Run:

```bash
contrib/ci/smoke.sh
tools/hls_memfd_smoke.sh
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
./stream scripts/tests/telegram_unit.lua
./stream scripts/tests/auth_backend_unit.lua
```

Expected: all pass.

- [ ] **Step 4: Run source-publication gates**

Run:

```bash
scripts/ci/check_sensitive_data.sh --all
contrib/ci/check_public_docs.sh
node --check web/app.js
git diff --check
GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=main GITHUB_HEAD_REF=codex/streamhub-unified-latest scripts/ci/check_branch_name.sh
GITHUB_EVENT_NAME=pull_request GITHUB_BASE_REF=main scripts/ci/check_changelog.sh
```

Expected: all pass.

- [ ] **Step 5: Record the verification result without committing generated files**

Run:

```bash
git status --short
scripts/ci/check_sensitive_data.sh --range 8822cbb1...HEAD
```

Expected: only intended source changes are tracked and the range scan passes.

### Task 5: Prepare a canary deployment manifest without deploying

**Files:**
- Create: `docs/superpowers/plans/2026-08-23-streamhub-1.3.0-canary-runbook.md`

- [ ] **Step 1: Record exact canary scope and exclusions**

The runbook must name one canary unit/port, the candidate artifact SHA-256, the
current production binary SHA-256, and the channels selected for validation.
It must explicitly exclude production configuration edits, database migration
outside the canary data directory, firewall changes, and production restart.

- [ ] **Step 2: Define the backup set**

Use a timestamped `/root/back/streamhub-1.3.0-canary-<UTC>/` directory containing
the current candidate target binary, scripts, web assets, unit definition,
configuration, `systemctl show` output, file hashes, and a rollback script.

- [ ] **Step 3: Define real playback evidence**

For each Newcamd canary channel, capture a 10-minute interval with:

```text
on_air=true
stable bitrate
CC delta = 0
PES delta = 0
cw_applied increases across odd/even transitions
FFmpeg decodes video frames and audio frames
no PPS/MMCO/AC-3 decode errors
```

For the buffer canary, record primary loss time, backup activation time, primary
healthy time, return time, and configured gate values.

- [ ] **Step 4: Define rollback commands but do not execute them**

Rollback stops only the canary unit, restores the recorded artifact set,
reloads systemd only when the unit file changed, starts the canary, and repeats
the same status and FFmpeg probes.

- [ ] **Step 5: Commit the reviewed runbook**

Before committing, run `scripts/ci/check_sensitive_data.sh --staged`. Replace
private host data with operator-supplied variables if the public repository
guard rejects it.

```bash
git add docs/superpowers/plans/2026-08-23-streamhub-1.3.0-canary-runbook.md
git commit -m "docs: define Stream Hub 1.3.0 canary gate"
```

### Task 6: Stop at the publication and deployment gates

**Files:**
- None

- [ ] **Step 1: Present the final branch evidence**

Report branch name, base and head commits, complete test matrix, source diff
summary, bundle SHA-256, and remaining limitations.

- [ ] **Step 2: Request separate GitHub publication approval**

Do not push or merge to `main` until the user approves the exact commit range.

- [ ] **Step 3: Request separate remote canary approval**

State the exact target unit/port, `/root/back/` backup directory, exclusions,
rollback, and FFmpeg verification commands. Do not write to or restart any
remote unit before that confirmation.
