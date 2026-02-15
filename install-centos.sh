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

# On older CentOS/RHEL the CA bundle is often outdated, so curl prints:
#   curl: (60) Peer's Certificate issuer is not recognized.
# Hide the noisy curl error and show a clear warning instead.
if ! curl -fsSL "$INSTALL_URL" -o "$TMP_FILE" 2>/dev/null; then
  echo "WARN: HTTPS download failed (old CA bundle?). Falling back to HTTP for bootstrap: http://stream.centv.ru/install.sh" >&2
  BASE_URL="http://stream.centv.ru"
  INSTALL_URL="${BASE_URL}/install.sh"
  curl -fsSL "$INSTALL_URL" -o "$TMP_FILE"
fi

chmod +x "$TMP_FILE"
exec "$TMP_FILE" --base-url "$BASE_URL" --verify-transcode "$@"
