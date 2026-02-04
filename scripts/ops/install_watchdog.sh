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

install -m 755 "$SRC_DIR/astral-watchdog.sh" /usr/local/bin/astral-watchdog.sh
install -m 644 "$SRC_DIR/astral-watchdog.service" /etc/systemd/system/astral-watchdog.service
install -m 644 "$SRC_DIR/astral-watchdog.timer" /etc/systemd/system/astral-watchdog.timer

if [ ! -f /etc/astral-watchdog.env ]; then
  install -m 644 "$SRC_DIR/astral-watchdog.env" /etc/astral-watchdog.env
fi

systemctl daemon-reload
systemctl enable --now astral-watchdog.timer

echo "Astral watchdog installed and enabled."
echo "Config: /etc/astral-watchdog.env"
