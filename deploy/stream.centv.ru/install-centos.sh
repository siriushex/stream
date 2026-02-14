#!/usr/bin/env bash
set -euo pipefail

# Централизованный установщик для CentOS/RHEL/Rocky/Alma.
# Нужен для случаев, когда HTTPS недоступен из‑за старых CA.

BASE_URL="https://stream.centv.ru"
INSTALL_URL="${BASE_URL}/install.sh"
TMP_FILE="$(mktemp -t stream-install.XXXXXX)"

cleanup() {
  rm -f "$TMP_FILE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! curl -fsSL "$INSTALL_URL" -o "$TMP_FILE"; then
  echo "WARN: HTTPS download failed. Falling back to HTTP for bootstrap: http://stream.centv.ru/install.sh" >&2
  BASE_URL="http://stream.centv.ru"
  INSTALL_URL="${BASE_URL}/install.sh"
  curl -fsSL "$INSTALL_URL" -o "$TMP_FILE"
fi

chmod +x "$TMP_FILE"
exec "$TMP_FILE" --base-url "$BASE_URL" "$@"
