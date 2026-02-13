#!/usr/bin/env bash
set -euo pipefail

# Stream Hub installer wrapper for CentOS/RHEL/Rocky/Alma.
# Default: build from source (more compatible across distros than a random prebuilt binary).

BASE_URL="https://stream.centv.ru"

if [ "$(uname -s)" != "Linux" ]; then
  echo "ERROR: This installer is for Linux (CentOS/RHEL-like)." >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Please run as root (sudo)." >&2
  exit 1
fi

# If user didn't specify --mode, default to --mode source.
MODE_SET=0
for a in "$@"; do
  if [ "$a" = "--mode" ]; then
    MODE_SET=1
    break
  fi
done

TMP="$(mktemp -t stream-install.XXXXXX)"
trap 'rm -f "$TMP"' EXIT

curl -fsSL "${BASE_URL}/install.sh" -o "$TMP"
chmod +x "$TMP"

if [ "$MODE_SET" -eq 1 ]; then
  exec "$TMP" "$@"
fi

exec "$TMP" --mode source "$@"
