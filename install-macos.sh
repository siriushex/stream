#!/usr/bin/env bash
set -euo pipefail

BASE_URL="https://stream.centv.ru"
BIN_PATH="/usr/local/bin/stream"
SRC_TARBALL_URL="${BASE_URL}/stream-src.tar.gz"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) ARTIFACT="stream-macos-arm64" ;;
  x86_64) ARTIFACT="stream-macos-x86_64" ;;
  *) die "Unsupported macOS arch: $ARCH" ;;
esac

URL="${BASE_URL}/${ARTIFACT}"
TMP_FILE="$(mktemp -t stream-macos.XXXXXX)"
BUILD_DIR=""
cleanup() {
  rm -f "$TMP_FILE" >/dev/null 2>&1 || true
  if [ -n "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

log "Downloading binary: $URL"
if curl -fsSL -o "$TMP_FILE" "$URL"; then
  chmod +x "$TMP_FILE"
  sudo mkdir -p "$(dirname "$BIN_PATH")"
  sudo install -m 755 "$TMP_FILE" "$BIN_PATH"
  log "Done. Binary: $BIN_PATH"
  exit 0
fi

warn "Prebuilt binary is unavailable for this macOS architecture. Falling back to source build."
command -v xcode-select >/dev/null 2>&1 || die "xcode-select is required (install Xcode Command Line Tools)."
xcode-select -p >/dev/null 2>&1 || die "Xcode Command Line Tools are not installed. Run: xcode-select --install"

BUILD_DIR="$(mktemp -d -t stream-src.XXXXXX)"
SRC_DIR="$BUILD_DIR/src"
mkdir -p "$SRC_DIR"

log "Downloading sources: $SRC_TARBALL_URL"
curl -fsSL -o "$BUILD_DIR/stream-src.tar.gz" "$SRC_TARBALL_URL"
tar -xzf "$BUILD_DIR/stream-src.tar.gz" -C "$SRC_DIR"

cd "$SRC_DIR"
log "Building from source (this can take a few minutes)..."
./configure.sh >/tmp/stream-macos-configure.log 2>&1 || {
  tail -n 50 /tmp/stream-macos-configure.log >&2 || true
  die "configure failed"
}
JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"
make -j"$JOBS" >/tmp/stream-macos-build.log 2>&1 || {
  tail -n 50 /tmp/stream-macos-build.log >&2 || true
  die "build failed"
}

test -x "$SRC_DIR/stream" || die "built binary not found"
sudo mkdir -p "$(dirname "$BIN_PATH")"
sudo install -m 755 "$SRC_DIR/stream" "$BIN_PATH"
log "Done. Binary: $BIN_PATH"
