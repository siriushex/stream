#!/usr/bin/env bash
set -euo pipefail

# Stream Hub installer for macOS.
# Installs a prebuilt binary (Apple Silicon) and creates a default config directory.

BASE_URL="https://stream.centv.ru"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "ERROR: This installer is for macOS." >&2
  exit 1
fi

ARCH="$(uname -m)"
URL=""

case "$ARCH" in
  arm64)
    URL="${BASE_URL}/stream-macos-arm64"
    ;;
  x86_64)
    URL="${BASE_URL}/stream-macos-x86_64"
    ;;
  *)
    echo "ERROR: Unsupported macOS arch: $ARCH" >&2
    exit 1
    ;;
esac

BIN="/usr/local/bin/stream"
CONF_DIR="/usr/local/etc/stream"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "ERROR: Need root to install to /usr/local/bin (sudo not found)." >&2
    exit 1
  fi
fi

TMP="$(mktemp -t stream-macos.XXXXXX)"
trap 'rm -f "$TMP"' EXIT

if ! curl -fsSL "$URL" -o "$TMP"; then
  echo "ERROR: Failed to download: $URL" >&2
  echo "Hint: Intel macOS builds may be unavailable. Use Linux or build from source." >&2
  exit 1
fi

$SUDO mkdir -p "$(dirname "$BIN")"
$SUDO install -m 0755 "$TMP" "$BIN"
$SUDO mkdir -p "$CONF_DIR"

cat <<EOF
OK.

Binary:
  $BIN

Config directory:
  $CONF_DIR

Run example:
  $BIN -c $CONF_DIR/prod.json -p 9060

Optional (for transcoding):
  - Install ffmpeg (Homebrew), then enable transcoding in UI.
EOF
