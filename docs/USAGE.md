# Stream Hub usage guide

This guide describes a safe, source-based installation and day-to-day operation
of Stream Hub. It uses placeholders such as `HOST`, `PORT`, `STREAM_ID`, and
`CONFIG`; replace them with values for the target environment. Keep access data
and provider data outside Git.

## 1. What Stream Hub does

Stream Hub receives transport streams from network, file, and DVB sources;
processes them through the runtime; and publishes outputs for playback or
downstream distribution. The web UI controls streams, inputs, outputs,
SoftCAM, system settings, monitoring, DVR, and remote-server integrations.

The project is source-first. Build a binary for the exact operating system and
CPU that will run it. Do not copy a binary built on a different platform.

## 2. Requirements

Prepare a supported Unix-like host with:

- a C compiler, `make`, standard development tools, and Git;
- Lua runtime dependencies required by the selected modules;
- enough disk space for the runtime database, logs, HLS segments, and DVR;
- network reachability to every intended input and output;
- FFmpeg only when a selected workflow requires transcoding or external decode
  verification.

Enable optional build features only when their dependencies are installed. For
example, `--with-libdvbcsa` enables the detected library and
`--without-transcode` builds without transcoding support. Review all build
options with:

```bash
./configure.sh --help
```

## 3. Build from source

Clone the repository and build from its root:

```bash
./configure.sh
make
```

For a faster build, use the platform's normal parallel-build option. A clean
build is required after changing build flags or platform architecture.

Run the focused checks before packaging a change:

```bash
node --check web/app.js
./stream scripts/tests/runtime_status_lite_fastpath_unit.lua
./stream scripts/tests/stream_status_ids_api_unit.lua
```

Run an appropriate smoke test when the runtime or transport path changes:

```bash
contrib/ci/smoke.sh
```

## 4. First start

Start the server with isolated runtime storage. `PORT`, `DATA_DIR`, and
`WEB_DIR` are placeholders:

```bash
./stream scripts/server.lua \
  -p PORT \
  --data-dir DATA_DIR \
  --web-dir WEB_DIR
```

Open `http://HOST:PORT/` in a browser and complete the initial administrator
setup. Replace the bootstrap access secret before exposing the service to any
untrusted network.

Use a configuration import when a reviewed configuration must seed a new
instance:

```bash
./stream scripts/server.lua \
  -p PORT \
  --data-dir DATA_DIR \
  --web-dir WEB_DIR \
  --config CONFIG
```

The runtime imports an unchanged configuration only once by default. Use the
UI or an explicit reviewed import workflow for subsequent configuration
changes; do not overwrite a working runtime database casually.

## 5. Web UI workflow

1. Sign in and open **Streams**.
2. Create a stream with a stable, readable identifier.
3. Add one input and save it. Start with one known-good input before enabling
   failover or replicas.
4. Add the required output, then start the stream.
5. Watch the card and stream details: active input, bitrate, `on_air`, input
   state, CC, PES, and recent errors.
6. Test the final playback URL in an independent player before treating the
   stream as ready.

Use **Settings** for global defaults and **System** for service and resource
inspection. Avoid changing several resilience or SoftCAM settings at once: it
makes the cause of a failure impossible to isolate.

## 6. Inputs, outputs, and failover

### Inputs

Create HTTP, HLS, UDP, file, or DVB inputs through the stream editor. Confirm
the input's expected codec, transport shape, and access rights before adding
it to a live stream.

For unstable HTTP or HLS sources, select a network profile deliberately and
increase buffering only enough to absorb measured jitter. Excessive buffering
increases latency and can hide upstream failures. Validate after every change
using the final output, not merely a successful input connection.

### Outputs

The runtime can serve playback paths and generate delivery outputs such as
UDP, HTTP transport stream, HLS, MPTS, and transcoded outputs, depending on
the configured modules. Keep transport settings explicit: program selection,
PID policy, bitrate budget, and output destination must match the downstream
consumer.

If one source feeds multiple consumer types, first prove a direct output,
then add MPTS, HLS, transcoding, or distribution branches one at a time. This
keeps failures local and makes rollback straightforward.

### Failover

Add a backup input only after the primary path is proved. Exercise a controlled
primary-input loss and verify that the selected backup becomes active, audio
and video continue decoding, and error counters remain acceptable. A backup
that only establishes a network connection is not a verified recovery path.

For HTTP buffer resources, the A/V health gate has five controls:

- `health_require_video` and `health_require_audio` require recent payload on
  PIDs identified from PAT/PMT stream types;
- `health_min_bitrate_kbps` rejects a stream that has transport structure but
  insufficient payload;
- `health_failover_sec` is the minimum continuous unhealthy interval;
- `health_fail_checks` is the minimum number of failed observations.

Both failure limits must be reached before switching. A higher-priority input
must then remain healthy for `backup_return_delay_sec` before failback. Keep the
CC and PES thresholds enabled: these A/V checks complement transport integrity
checks and must not hide or reset them. Dashboard publication is optional. If
enabled, leave `dashboard_stream_id` empty to use the buffer ID; Stream creates
or updates only an output it owns, and reports a conflict for an unrelated ID.

For native HLS playout, `media_kbps` is derived from PCR and controls pacing.
`arrival_kbps` describes HTTP download speed and can be zero when a complete
localhost burst finishes inside its sampling window. `prebuffering` should
change from true to false once the startup reserve is filled and should re-enter
only after the media buffer becomes empty.

## 7. SoftCAM and Newcamd

Use SoftCAM only for services that you are authorized to receive and decode.
Create the Newcamd entry in the UI or in protected runtime configuration, then
assign its identifier to the relevant stream input. Keep provider connection
data, user identity, CW values, and keys out of source control, screenshots,
and support messages.

Before enabling redundancy, prove one stream with one CAM path:

1. Run the UI SoftCAM test and confirm that the module is available and ready.
2. Start one encrypted stream with a single selected CAM.
3. Observe a full control-word rotation, not only the first few seconds after
   stream start.
4. Confirm continuous decoded video and audio at the final output.
5. Record CC and PES counter deltas for at least five to ten minutes.

For a backup CAM, add it only when the primary path passes the same test.
Select the mode deliberately: failover waits for primary failure, while race
and hedge modes can reduce response delay at additional provider and CPU cost.
Do not share a single connection across many streams unless its measured ECM
latency and capacity support that load. Where parallelism is needed, use a
bounded split-CAM pool and watch queue depth, dropped batches, reconnects, and
CPU usage.

`key_guard` precedence is input, then CAM, then global setting. The SoftCAM
status exposes candidate validation counters plus the accepted key's parity mask
and `apply_seq`; shift stats expose ingress and egress packet sequences. During
an odd/even rotation, confirm that `cw_applied` advances while candidate rejects,
CC, and PES deltas remain zero. A partial Newcamd CW is completed only from the
same service scope and current connection generation; it must never borrow a
half-key from another channel.

Do not disable CC or PES thresholds to make a card appear healthy. Nonzero or
growing counters indicate a transport or descrambling defect that needs
investigation.

## 8. Proving the output is healthy

Control-plane state alone is insufficient. A positive UI state, a connected
input, or bytes arriving at a playback URL does not prove decoded media.

For every new or changed stream, check all of the following:

- `on_air` remains true during the observation period;
- the selected input stays active and bitrate is stable for the source;
- CC and PES deltas stay at zero unless a documented upstream discontinuity is
  being investigated;
- SoftCAM counters progress across control-word changes without zero or stale
  values being applied;
- an external decoder sees real video dimensions and audio parameters, then
  decodes both tracks without recurring codec warnings.

An example external decode check is:

```bash
ffmpeg -hide_banner -loglevel warning \
  -i "http://HOST:PORT/play/STREAM_ID" \
  -t 30 -map 0:v? -map 0:a? -f null -
```

Run this check for at least five to ten minutes after a SoftCAM, input,
buffering, or failover change. If it fails, preserve logs and counter history;
do not silence alarms or lower quality limits as a workaround.

## 9. Monitoring and logs

Use the Dashboard for an overview and the stream detail view for the active
input, bitrate, state transitions, CC, PES, and output status. Enable only the
observability detail level required for the incident: high-resolution metrics
consume storage and CPU.

For a systemd-managed instance, inspect the unit and recent journal entries
after any service restart. Keep logs and metrics long enough to cover the
failure window, then compare the first error with input changes, CAM reconnects,
output restarts, and resource pressure.

When measuring a fault, capture:

- stream identifier and UTC time window;
- selected input and its reconnect history;
- bitrate, CC, PES, and decoder result;
- SoftCAM readiness and control-word application counters when relevant;
- CPU, memory, disk, and network pressure;
- the minimal configuration change that preceded the event.

Redact all access data from tickets and logs shared outside the operating team.

## 10. DVR and remote servers

Enable DVR only after calculating retention, free disk, write bandwidth, and
recovery behavior. Test archive playback, quota enforcement, and restart
recovery with a noncritical stream before enabling large channel groups.

For remote-server integration, test capabilities and credentials from the UI,
then import a single noncritical stream. Verify the remote output and the
origin output independently. Keep source ownership clear: do not configure a
remote DVR to ingest its own origin path, and do not bulk-mutate remote streams
until the single-stream path has passed playback verification.

## 11. Upgrades and rollback

1. Review the Git diff and run relevant tests on a noncritical instance.
2. Back up the runtime database and the active configuration outside the source
   checkout.
3. Build the new binary for the target platform.
4. Update one instance or one stream group at a time.
5. Verify service state, logs, final decoded audio/video, CC, PES, and recovery
   behavior.
6. Keep the prior binary and configuration until the observation window passes.

If quality regresses, stop only the affected instance, restore the known-good
binary and configuration, restart it, and repeat final-path validation. Record
the rollback reason before attempting a new change.

## 12. Troubleshooting

| Symptom | Check first | Safe next action |
| --- | --- | --- |
| No active input | Source reachability, input syntax, and recent logs | Prove the source with one input before changing output settings. |
| Bitrate exists but playback fails | Decoder output, CC, PES, codec parameters | Investigate the input or descrambling path; do not accept byte flow as proof. |
| Stream works briefly then degrades | Control-word rotation, CAM reconnects, queues, and counter deltas | Test one CAM path over a complete rotation; then add bounded backup or pooling. |
| Repeated HLS or HTTP gaps | Jitter, segment retry history, buffer level, and upstream failures | Apply the smallest measured resilience profile and recheck final playback. |
| Output restarts | Output logs, bitrate budget, downstream reachability, and resource limits | Isolate one output branch; re-enable dependent outputs one at a time. |
| DVR fills storage | Retention, quota, writer errors, and stale segments | Pause noncritical recording, restore free space safely, then review retention. |

## 13. Related documents

- [Architecture](ARCHITECTURE.md)
- [DevOps](DEVOPS.md)
- [Security review](SECURITY_REVIEW.md)
- [Auth backends](../contrib/auth-backends/README.md)
- [CI smoke checks](../contrib/ci/README.md)
