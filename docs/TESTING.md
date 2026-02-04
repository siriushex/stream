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
./astra scripts/tests/telegram_unit.lua
```

## Server Verification (required for release)
All final verification must run on the target server in `/home/hex`.
See `AGENT.md` for the full checklist and constraints (no DVB tests).

## Notes
- DVB-related tests are not allowed on the server (no DVB hardware).
- HLS and HTTP Play tests require a running stream source (ffmpeg or real input).
