#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$ROOT_DIR/contrib/systemd"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl not found. This installer requires systemd." >&2
  exit 1
fi

install -m 755 "$SRC_DIR/stream-watchdog.sh" /usr/local/bin/stream-watchdog.sh
install -m 644 "$SRC_DIR/stream-watchdog.service" /etc/systemd/system/stream-watchdog.service
install -m 644 "$SRC_DIR/stream-watchdog.timer" /etc/systemd/system/stream-watchdog.timer

if [ ! -f /etc/stream-watchdog.env ]; then
  install -m 644 "$SRC_DIR/stream-watchdog.env" /etc/stream-watchdog.env
fi

systemctl daemon-reload
systemctl enable --now stream-watchdog.timer

echo "Stream watchdog installed and enabled."
echo "Config: /etc/stream-watchdog.env"
