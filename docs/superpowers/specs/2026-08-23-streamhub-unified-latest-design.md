# Stream Hub Unified Latest Design

**Date:** 2026-08-23

**Status:** Approved for implementation planning

## 1. Goal

Create one reviewable Stream Hub source line from the current public `main`
branch and the unique, still-useful behavior found in the server-side development
trees. The result must improve Newcamd control-word handling, descrambler timing,
native HLS playout, and HTTP buffer failover without importing deployed state,
credentials, private channel configuration, or obsolete source wholesale.

The unified source is not considered release-ready until it builds on Linux,
passes targeted regression tests, and proves real audio/video decoding on a
canary deployment. HTTP success, byte flow, `on_air`, and CAM readiness alone
are not sufficient playback proof.

## 2. Baseline and provenance

The integration branch starts from public commit `8822cbb1` on `origin/main`.
The server development trees all report the older base commit `b26ea66b`, but
their useful work exists as modified tracked files and untracked helper files,
not as mergeable commits. Integration therefore uses semantic forward-porting:
each behavior is re-applied to the current architecture and covered by tests.

The audited development lineages are:

| Lineage | Unique or relevant behavior | Decision |
| --- | --- | --- |
| Initial Newcamd build | Partial CW cache and EOF reconnect experiments | Do not copy; current `main` supersedes it |
| Native HLS build | PCR/media-clock bitrate, startup/recovery prebuffering, active-segment de-duplication | Forward-port selected behavior |
| Per-stream key-guard build | Per-input/CAM/global key-guard precedence and bounded shift sizing | Forward-port without channel allowlists |
| Key-guard timing build | Candidate validation before key application | Superseded by the later CAS sequence lineage |
| CAS sequence canary | Ingress/egress sequence alignment and parity-boundary CW application | Forward-port selected behavior |
| Buffer client build | MPEG-TS A/V health, failover/recovery, client socket resilience, managed dashboard link | Forward-port selected behavior |

The local commit `c55ff297` is also included because it isolates partial CW
caches by service scope and already has a focused unit test.

## 3. Integration strategy

Each subsystem lands as a separate commit series and remains independently
testable:

1. Newcamd CW scope isolation and key-guard configuration.
2. CAS parity sequencing and shift-buffer timing.
3. Native HLS media-clock playout and active-segment de-duplication.
4. HTTP buffer A/V health, recovery, and dashboard exposure.
5. Integration gates, provenance notes, and release documentation.

Whole-file replacement from a server snapshot is forbidden. The server copies
contain older implementations of unrelated features and, in some cases,
generated or minified files. Only the reviewed behavior described below may be
ported.

## 4. Newcamd and SoftCAM design

### 4.1 Preserve the current Newcamd protocol implementation

The current `main` implementation remains authoritative for:

- ECM request/response identifier correlation;
- connection-generation scoping;
- stale response rejection and state reset;
- partial-CW rejection counters;
- reconnect-on-EOF behavior;
- current retry, keepalive, and runtime statistics.

The older server copies of `newcamd.c`, `module_cam.h`, `newcamd_reconnect.h`,
and `newcamd_keys.h` must not overwrite those behaviors.

### 4.2 Isolate partial CW caches by service scope

Apply the behavior from `c55ff297` to `newcamd_cw_guard.h`:

- retain up to 16 independent `{decrypt, arg, generation}` cache slots;
- merge a partial even or odd CW only with the previous complementary half from
  the same slot;
- reject an unknown scope rather than borrowing a half from another service;
- reset all slots on Newcamd connection reset;
- use bounded round-robin replacement when all slots are occupied.

Regression tests must interleave at least two services on the same Newcamd
socket and verify that neither service receives the other's CW half.

### 4.3 Resolve key-guard configuration explicitly

The effective `key_guard` value is resolved in this order:

1. stream/input configuration;
2. referenced CAM configuration;
3. global `softcam_key_guard` setting;
4. disabled when no valid value is present.

An invalid explicit value disables the guard for that scope. No hard-coded
channel names or server-side canary allowlists enter the repository.

## 5. CAS parity sequencing design

The current key-guard validates candidate CWs against PES starts, but without a
sequence-aware shift buffer it can apply a validated key to packets that belong
to a different odd/even epoch. The unified design keeps the current immutable,
reference-counted parallel descramble key context and adds only the missing
timing layer.

For each CA stream:

- assign a monotonically increasing sequence number at ingress;
- track the most recent odd and even scrambling-parity transition;
- validate a candidate on matching scrambled payload-start packets;
- accept after two valid observations;
- reject after four invalid observations;
- choose the queued parity transition as the apply boundary when it is still in
  the shift buffer, otherwise use the first validated packet sequence;
- apply the staged CW only when the matching sequence reaches egress;
- keep one accepted-but-not-yet-applied candidate per CA stream;
- expose ingress sequence, egress sequence, pending state, apply sequence, and
  primary/backup applied/rejected counters in runtime statistics.

The shift buffer uses a packet-aligned size, interprets legacy values below 100
as 100 ms units, and caps allocation at 16 MiB. Zero keeps shifting disabled.

## 6. Native HLS playout design

### 6.1 Media-clock bitrate

Burst download speed is not a valid pacing rate for HLS segments. The playout
module therefore derives an exponential moving average from valid PCR deltas.
It ignores duplicate PCR values and implausible discontinuities, handles PCR
wrap, and falls back to the existing arrival-rate estimate until a media-clock
estimate exists.

Statistics expose both `media_kbps` and `arrival_kbps` so pacing decisions can
be diagnosed without confusing transport arrival speed with encoded bitrate.

### 6.2 Startup and recovery prebuffering

`playout_min_fill_ms` is a startup/recovery threshold, not a permanent
low-water mark. Playout waits for the threshold only while `prebuffering=true`.
After release it continues sending media until the buffer becomes empty; only
then does it re-enter prebuffering. This prevents repeated media/NULL
oscillation around the threshold.

The current architecture intentionally analyzes the source before playout so
NULL stuffing cannot create a false `on_air=true`. The server experiment that
moves analysis after playout is therefore not imported.

### 6.3 Active HLS segment reservation

An active segment remains present in the `queued` reservation set until its
request completes or is abandoned. Playlist refreshes must not enqueue the same
active sequence again. The reservation is cleared on completion and retained
when the item is explicitly requeued for retry.

## 7. HTTP buffer health and failover design

### 7.1 Per-input transport health

Each enabled input maintains an incremental MPEG-TS health state:

- packet synchronization;
- PAT reception;
- PMT discovery and parsing;
- first supported video PID;
- first supported audio PID;
- recent payload timestamps for selected A/V PIDs;
- measured bitrate over a bounded window;
- consecutive failed checks and recovery duration.

Supported stream types follow the existing MPEG-TS type definitions. Health
evaluation uses the resource settings:

- `health_require_video` (default `true`);
- `health_require_audio` (default `true`);
- `health_min_bitrate_kbps` (default `128`);
- `health_failover_sec` (default `5`);
- `health_fail_checks` (default `2`).

A threshold failure changes the input's health state; it does not rewrite TS
continuity counters and does not suppress existing CC/PES diagnostics.

### 7.2 Failover and return

The active input fails over only after both the configured failure count and
failure duration are satisfied. A higher-priority input returns only after it
has remained healthy for `backup_return_delay_sec`. Probes must not displace the
active reader until recovery is confirmed.

Status exposes active input, recovery candidate, PAT/PMT/A/V state, bitrate,
failure reason, failed checks, and recovery progress.

### 7.3 Client socket resilience

Accepted HTTP clients receive a bounded send timeout and TCP keepalive. Linux
`TCP_USER_TIMEOUT` is enabled conditionally when the platform provides it. A
stalled client must be disconnected without blocking producer or other client
delivery.

### 7.4 Configuration, API, UI, and managed dashboard link

The five health settings are persisted in `buffer_resources`, exported through
the buffer API, passed to the C module, and editable in the existing buffer UI.
Schema changes are additive and idempotent.

Buffer publication to the main dashboard is optional. When enabled, Stream Hub
may create or maintain a local HTTP stream marked with
`buffer_managed_resource_id`. It may link to an already compatible manual
stream, but it must never overwrite an unrelated stream with the requested ID.
Deletion removes only links and streams carrying the matching managed marker.

## 8. Exclusions

The following are deliberately excluded from the unified source:

- deployed JSON configuration, SQLite databases, recordings, logs, and caches;
- CAM hosts, usernames, passwords, DES keys, SSH data, and private addresses;
- built binaries and generated `config.h` files;
- macOS `._*` resource-fork files and minified artifacts copied from deployment;
- the channel-specific `pol-sport3-hls` FFmpeg/gateway/watchdog prototype;
- hard-coded Sport 3 input names or canary allowlists;
- server versions of Newcamd files that are older than current `main`;
- threshold suppression or any change that hides CC/PES errors.

The channel-specific prototype remains audit evidence only. Its useful general
ideas—media health, controlled failover, and recovery delay—are implemented in
the generic buffer subsystem.

## 9. Verification gates

### 9.1 Source and unit gates

- compile and run the Newcamd CW scope test;
- compile and run key-guard timing and shift-size tests;
- run Lua tests for key-guard precedence and active HLS segment de-duplication;
- run buffer configuration, migration, API, and managed-link tests;
- run a deterministic primary/backup HTTP buffer canary with video and audio
  loss scenarios;
- run repository sensitive-data, documentation, JavaScript syntax, and diff
  hygiene checks.

### 9.2 Linux build gate

Build on Linux with OpenSSL and the normal SoftCAM dependencies. The build must
include the Newcamd module; a successful macOS build with Newcamd disabled is
not sufficient.

### 9.3 Canary playback gate

Deployment is a separate, explicitly approved operation. Before deployment:

- create a timestamped backup under `/root/back/` containing the binary,
  scripts, web assets, service metadata, hashes, and relevant configuration;
- deploy first to a separate canary port or unit;
- preserve the production unit and channel configuration;
- define a one-command rollback to the recorded backup.

For at least 10 minutes on representative Newcamd channels, verify:

- `on_air=true` with stable bitrate;
- CC and PES deltas remain zero during the observation window;
- `cw_applied` increases across real odd/even key changes;
- mismatch, stale-response, rejected-scope, and key-guard counters remain
  explainable and bounded;
- external FFmpeg decodes both video and audio without PPS, MMCO, or AC-3
  errors;
- primary loss causes bounded failover and healthy primary return observes the
  configured recovery delay.

No production replacement or GitHub `main` update occurs until these gates pass
and the exact deployment scope receives separate confirmation.
