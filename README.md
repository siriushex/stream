# Stream Hub

Stream Hub is a streaming server with Web UI.

This repository contains only source code and runtime components required for build and execution:
- core daemon and modules,
- web interface assets,
- runtime scripts,
- installer scripts.

Operational manuals, internal infrastructure notes, logs, and environment-specific data are intentionally excluded.

License: see `COPYING`.

## Observability Runbook (Production)

Use these settings to keep long history with low overhead:

- `observability_enabled=true`
- `observability_stream_detail_enabled=true`
- `observability_stream_highres_enabled=true`
- `observability_stream_ffmpeg_metrics_enabled=true`
- `observability_stream_highres_max_streams=20`
- `ai_metrics_on_demand=false`
- `ai_metrics_retention_days=30`
- `ai_rollup_interval_sec=60`
- `ai_logs_retention_days=30`
- `observability_system_rollup_enabled=true`
- `observability_system_rollup_interval_sec=60`
- `observability_system_retention_sec=604800` (7 days)

Minimal API checks (replace host/port):

```bash
# login
TOKEN=$(curl -sS -X POST http://HOST:PORT/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"admin"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')

# global metrics mode + flags
curl -sS -H "Authorization: Bearer $TOKEN" \
  "http://HOST:PORT/api/v1/ai/metrics?range=1h&scope=global"

# stream series (auto resolution with fallback)
curl -sS -H "Authorization: Bearer $TOKEN" \
  "http://HOST:PORT/api/v1/observability/stream-series?stream_id=STREAM_ID&range=1h&resolution=auto&metrics=stream.bitrate_kbps.avg,stream.cc_errors.delta,stream.pes_errors.delta,stream.ffmpeg.restart.total"

# system timeseries
curl -sS -H "Authorization: Bearer $TOKEN" \
  "http://HOST:PORT/api/v1/observability/system/timeseries?range=1h"
```
