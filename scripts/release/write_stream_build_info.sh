#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BINARY=${1:?binary path required}
OUTPUT=${2:?output path required}
VERSION=${3:?version required}
ARCH=${4:?architecture required}
PROFILE=${5:?profile required}

if [[ ! -f "$BINARY" ]]; then
  echo "Binary not found: $BINARY" >&2
  exit 1
fi

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no)" \
      && "${STREAM_ALLOW_DIRTY_BUILD:-0}" != "1" ]]; then
  echo "Refusing to record provenance from a dirty source tree" >&2
  exit 1
fi

SHA256_CMD=(sha256sum)
if ! command -v sha256sum >/dev/null 2>&1; then
  SHA256_CMD=(shasum -a 256)
fi

GIT_COMMIT=$(git -C "$ROOT_DIR" rev-parse HEAD)
BINARY_SHA256=$("${SHA256_CMD[@]}" "$BINARY" | awk '{print $1}')
mkdir -p "$(dirname "$OUTPUT")"

{
  echo "Stream-Version: $VERSION"
  echo "Git-Commit: $GIT_COMMIT"
  echo "Built-At-UTC: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "Binary-SHA256: $BINARY_SHA256"
  echo "Architecture: $ARCH"
  echo "Profile: $PROFILE"
} > "$OUTPUT"
