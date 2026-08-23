#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/stream-build-info.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

TEST_REPO="$TMP_ROOT/repo"
mkdir -p "$TEST_REPO/scripts/release" "$TEST_REPO/bin"
cp "$ROOT_DIR/scripts/release/write_stream_build_info.sh" \
  "$TEST_REPO/scripts/release/write_stream_build_info.sh"
printf '%s\n' baseline > "$TEST_REPO/README.md"
printf '%s\n' binary > "$TEST_REPO/bin/stream"

git -C "$TEST_REPO" init -q
git -C "$TEST_REPO" -c user.name=Test -c user.email=test@example.invalid \
  add README.md scripts/release/write_stream_build_info.sh
git -C "$TEST_REPO" -c user.name=Test -c user.email=test@example.invalid \
  commit -qm baseline

WRITER="$TEST_REPO/scripts/release/write_stream_build_info.sh"
OUTPUT="$TMP_ROOT/STREAM_BUILD_INFO.txt"
"$WRITER" "$TEST_REPO/bin/stream" "$OUTPUT" 1.3.0 linux-x86_64 lgpl

grep -Eq '^Stream-Version: 1\.3\.0$' "$OUTPUT"
grep -Eq '^Git-Commit: [0-9a-f]{40}$' "$OUTPUT"
grep -Eq '^Built-At-UTC: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$OUTPUT"
grep -Eq '^Binary-SHA256: [0-9a-f]{64}$' "$OUTPUT"
grep -Eq '^Architecture: linux-x86_64$' "$OUTPUT"
grep -Eq '^Profile: lgpl$' "$OUTPUT"

printf '%s\n' dirty >> "$TEST_REPO/README.md"
if "$WRITER" "$TEST_REPO/bin/stream" "$OUTPUT" 1.3.0 linux-x86_64 lgpl \
    >"$TMP_ROOT/dirty.out" 2>"$TMP_ROOT/dirty.err"; then
  echo 'dirty provenance write unexpectedly succeeded' >&2
  exit 1
fi
grep -q 'Refusing to record provenance from a dirty source tree' "$TMP_ROOT/dirty.err"

STREAM_ALLOW_DIRTY_BUILD=1 \
  "$WRITER" "$TEST_REPO/bin/stream" "$OUTPUT" 1.3.0 linux-x86_64 lgpl

printf '%s\n' 'Release build info tests: OK.'
