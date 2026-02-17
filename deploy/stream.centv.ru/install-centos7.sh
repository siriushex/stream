#!/usr/bin/env bash
set -euo pipefail

# Dedicated bootstrap for CentOS 7 / RHEL 7.
# Uses legacy static ffmpeg bundle profile compatible with glibc 2.17.

BASE_URL="https://stream.centv.ru"
INSTALL_URL="${BASE_URL}/install.sh"
BOOTSTRAP_VERSION="1.2.5"
TMP_FILE="$(mktemp -t stream-install.XXXXXX)"
CURL_FLAGS=(-fL -sS --retry 2 --retry-delay 1 --connect-timeout 10 --max-time 120)

cleanup() {
  rm -f "$TMP_FILE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Stream CentOS 7 bootstrap ${BOOTSTRAP_VERSION}" >&2

if ! curl "${CURL_FLAGS[@]}" "$INSTALL_URL" -o "$TMP_FILE" 2>/dev/null; then
  echo "WARN: HTTPS download failed (old CA bundle?). Falling back to HTTP for bootstrap: http://stream.centv.ru/install.sh" >&2
  BASE_URL="http://stream.centv.ru"
  INSTALL_URL="${BASE_URL}/install.sh"
  curl "${CURL_FLAGS[@]}" "$INSTALL_URL" -o "$TMP_FILE"
fi

chmod +x "$TMP_FILE"

has_mode=0
has_ffmpeg=0
for arg in "$@"; do
  case "$arg" in
    --mode|--mode=*)
      has_mode=1
      ;;
    --ffmpeg-bundle|--ffmpeg-system|--no-ffmpeg)
      has_ffmpeg=1
      ;;
  esac
done

extra=()
if [ "$has_mode" -eq 0 ]; then
  extra+=(--mode source)
fi
if [ "$has_ffmpeg" -eq 0 ]; then
  extra+=(--ffmpeg-bundle)
fi

# CentOS7-specific profile: static ffmpeg build compatible with old glibc.
export FFMPEG_BUNDLE_PROFILE="${FFMPEG_BUNDLE_PROFILE:-legacy-static}"

# Run through bash to work even when /tmp is mounted with noexec.
exec bash "$TMP_FILE" --base-url "$BASE_URL" "${extra[@]}" "$@"
