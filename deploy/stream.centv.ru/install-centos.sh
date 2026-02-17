#!/usr/bin/env bash
set -euo pipefail

# Централизованный установщик для CentOS/RHEL/Rocky/Alma.
# Нужен для случаев, когда HTTPS недоступен из‑за старых CA.
# Не принуждаем --verify-transcode: на старых системах ffmpeg может быть
# установлен, но не запускаться из-за системных библиотек.

BASE_URL="https://stream.centv.ru"
INSTALL_URL="${BASE_URL}/install.sh"
BOOTSTRAP_VERSION="1.2.4"
TMP_FILE="$(mktemp -t stream-install.XXXXXX)"
CURL_FLAGS=(-fL -sS --retry 2 --retry-delay 1 --connect-timeout 10 --max-time 120)

cleanup() {
  rm -f "$TMP_FILE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Stream CentOS bootstrap ${BOOTSTRAP_VERSION}" >&2

# On older CentOS/RHEL the CA bundle is often outdated, so curl prints:
#   curl: (60) Peer's Certificate issuer is not recognized.
# Hide the noisy curl error and show a clear warning instead.
if ! curl "${CURL_FLAGS[@]}" "$INSTALL_URL" -o "$TMP_FILE" 2>/dev/null; then
  echo "WARN: HTTPS download failed (old CA bundle?). Falling back to HTTP for bootstrap: http://stream.centv.ru/install.sh" >&2
  BASE_URL="http://stream.centv.ru"
  INSTALL_URL="${BASE_URL}/install.sh"
  curl "${CURL_FLAGS[@]}" "$INSTALL_URL" -o "$TMP_FILE"
fi

chmod +x "$TMP_FILE"
# Run through bash to work even when /tmp is mounted with noexec.
exec bash "$TMP_FILE" --base-url "$BASE_URL" "$@"
