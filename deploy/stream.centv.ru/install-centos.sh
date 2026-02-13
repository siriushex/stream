#!/usr/bin/env bash
set -euo pipefail

# Stream Hub installer wrapper for CentOS/RHEL/Rocky/Alma.
# Default: build from source (more compatible across distros than a random prebuilt binary).

BASE_URL_HTTPS="https://stream.centv.ru"
BASE_URL_HTTP="http://stream.centv.ru"

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

BASE_URL="$BASE_URL_HTTPS"
BASE_URL_ARG=()

# На минимальных CentOS/RHEL образах часто нет актуального набора CA,
# и HTTPS download падает с ошибкой "certificate issuer is not recognized".
# В этом случае делаем fallback на HTTP для загрузки установщика и артефактов.
if ! curl -fsSL "${BASE_URL}/install.sh" -o "$TMP" >/dev/null 2>&1; then
  BASE_URL="$BASE_URL_HTTP"
  echo "WARN: HTTPS download failed. Falling back to HTTP for bootstrap: ${BASE_URL}/install.sh" >&2
  curl -fsSL "${BASE_URL}/install.sh" -o "$TMP"
  BASE_URL_ARG=(--base-url "$BASE_URL")
fi
chmod +x "$TMP"

if [ "$MODE_SET" -eq 1 ]; then
  exec "$TMP" "${BASE_URL_ARG[@]}" "$@"
fi

exec "$TMP" --mode source "${BASE_URL_ARG[@]}" "$@"
