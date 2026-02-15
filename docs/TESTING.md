# Testing

## Local Build (optional)
```sh
./configure.sh
make
```

## Local Smoke (recommended)
Uses the built-in smoke script:
```sh
contrib/ci/smoke.sh
```

What it does:
- builds the binary
- starts server on port 9050
- checks UI assets
- validates auth/session
- hits metrics + health endpoints
- runs export

## Telegram Unit Test
```sh
./stream scripts/tests/telegram_unit.lua
```

## AstralAI Tests
```sh
./stream scripts/tests/ai_plan_smoke.lua
./stream scripts/tests/ai_apply_smoke.lua
./stream scripts/tests/ai_summary_unit.lua
./stream scripts/tests/ai_charts_unit.lua
./stream scripts/tests/ai_observability_unit.lua
./stream scripts/tests/ai_context_unit.lua
./stream scripts/tests/ai_context_cli_unit.lua
./stream scripts/tests/ai_context_api_unit.lua
./stream scripts/tests/ai_runtime_context_unit.lua
./stream scripts/tests/ai_plan_context_unit.lua
```

## Bundle Smoke (transcode)
Build or provide a bundle, then run:
```sh
contrib/ci/smoke_bundle_transcode.sh
```

Environment:
- `BUNDLE_TAR=/path/to/stream-transcode-<version>-linux-<arch>-<profile>.tar.gz`
- `PORT=9065` (optional)

## MPTS Smoke (runtime apply)
```sh
contrib/ci/smoke_mpts.sh
```

Дополнительно можно прогнать verify напрямую:
```sh
./tools/verify_mpts.sh "udp://127.0.0.1:12346"
EXPECT_TOT=1 EXPECT_PNRS="101,102" EXPECT_PMT_PNRS="101,102" ./tools/verify_mpts.sh "udp://127.0.0.1:12346"
EXPECT_TOT=1 EXPECT_NIT_TS_LIST="1:1,2:1,3:1" EXPECT_PMT_ES_PIDS="101=256;102=256" ./tools/verify_mpts.sh "udp://127.0.0.1:12346"
```

## Server Verification (required for release)
All final verification must run on the target server in `/home/hex`.
See `AGENT.md` for the full checklist and constraints (no DVB tests).

## Notes
- DVB-related tests are not allowed on the server (no DVB hardware).
- HLS and HTTP Play tests require a running stream source (ffmpeg or real input).
