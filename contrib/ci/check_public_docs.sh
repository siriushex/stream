#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUIDE="$ROOT/docs/USAGE.md"
INDEX="$ROOT/web/index.html"
URL="https://github.com/siriushex/stream/blob/main/docs/USAGE.md"

test -s "$GUIDE"
rg -Fq "$URL" "$INDEX"
rg -Fq '[Usage guide](docs/USAGE.md)' "$ROOT/README.md"
! rg -n '([0-9]{1,3}\.){3}[0-9]{1,3}|api[_-]?key|token=|Authorization:|password|\.ssh|BEGIN (RSA|OPENSSH) PRIVATE KEY' "$GUIDE"

printf '%s\n' 'Public documentation check: OK.'
