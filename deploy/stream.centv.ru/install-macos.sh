#!/usr/bin/env bash
set -euo pipefail

BASE_URL="https://stream.centv.ru"
BIN_PATH="/usr/local/bin/stream"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) ARTIFACT="stream-macos-arm64" ;;
  x86_64) ARTIFACT="stream-macos-x86_64" ;;
  *) die "Unsupported macOS arch: $ARCH" ;;
esac

URL="${BASE_URL}/${ARTIFACT}"
TMP_FILE="$(mktemp -t stream-macos.XXXXXX)"
trap 'rm -f "$TMP_FILE" >/dev/null 2>&1 || true' EXIT

log "Downloading binary: $URL"
curl -fsSL -o "$TMP_FILE" "$URL"

chmod +x "$TMP_FILE"
sudo mkdir -p "$(dirname "$BIN_PATH")"
sudo install -m 755 "$TMP_FILE" "$BIN_PATH"

log "Done. Binary: $BIN_PATH"
