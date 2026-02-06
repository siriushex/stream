#!/usr/bin/env bash
set -euo pipefail

# Установка Astral (бинарник) как systemd-сервиса на Ubuntu/Debian.
# Скрипт:
# - скачивает бинарник по URL
# - создаёт unit-шаблон `astral@.service`
# - создаёт env-файл `/etc/astral/<name>.env` с CONFIG/PORT/EXTRA_OPTS
# - включает и запускает сервис

usage() {
  cat <<'EOF'
Usage:
  sudo ./tools/install_astral_systemd.sh \
    --name <instance> \
    --url <binary_url> \
    --config <config_path> \
    --port <port> \
    [--install-dir /opt/astral] \
    [--bin-name astral] \
    [--extra-opts "<opts>"] \
    [--no-ffmpeg]

Examples:
  sudo ./tools/install_astral_systemd.sh \
    --name ada-s \
    --url "https://example.com/astral-linux-amd64" \
    --config /etc/astral/ada-s.json \
    --port 8801

Notes:
  - `--config` файл должен существовать (скрипт его не генерирует).
  - По умолчанию ставим бинарник в /opt/astral и симлинк в /usr/local/bin/astral.
  - Service template: /etc/systemd/system/astral@.service
  - Env per instance: /etc/astral/<name>.env
EOF
}

NAME=""
URL=""
CONFIG_PATH=""
PORT=""
INSTALL_DIR="/opt/astral"
BIN_NAME="astral"
EXTRA_OPTS=""
INSTALL_FFMPEG=1

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "$*" >&2; }

while [[ "${#:-0}" -gt 0 ]]; do
  case "${1:-}" in
    --name)
      NAME="${2:-}"; shift 2 ;;
    --url)
      URL="${2:-}"; shift 2 ;;
    --config)
      CONFIG_PATH="${2:-}"; shift 2 ;;
    --port)
      PORT="${2:-}"; shift 2 ;;
    --install-dir)
      INSTALL_DIR="${2:-}"; shift 2 ;;
    --bin-name)
      BIN_NAME="${2:-}"; shift 2 ;;
    --extra-opts)
      EXTRA_OPTS="${2:-}"; shift 2 ;;
    --no-ffmpeg)
      INSTALL_FFMPEG=0; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "Unknown argument: ${1:-}" ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  die "Please run as root (sudo)."
fi

if [[ -z "$NAME" ]]; then die "--name is required"; fi
if [[ -z "$URL" ]]; then die "--url is required"; fi
if [[ -z "$CONFIG_PATH" ]]; then die "--config is required"; fi
if [[ -z "$PORT" ]]; then die "--port is required"; fi
if [[ ! -f "$CONFIG_PATH" ]]; then
  die "Config file not found: $CONFIG_PATH"
fi

if ! command -v systemctl >/dev/null 2>&1; then
  die "systemctl not found (systemd required)."
fi

if ! command -v apt-get >/dev/null 2>&1; then
  die "apt-get not found. This script targets Debian/Ubuntu."
fi

log "[astral-install] Installing base packages (curl, ca-certificates)..."
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl

if [[ "$INSTALL_FFMPEG" -eq 1 ]]; then
  log "[astral-install] Installing ffmpeg (preview/audio-aac requires it)..."
  apt-get install -y --no-install-recommends ffmpeg || true
fi

log "[astral-install] Installing binary to ${INSTALL_DIR}/${BIN_NAME}"
mkdir -p "$INSTALL_DIR"
curl -fsSL "$URL" -o "${INSTALL_DIR}/${BIN_NAME}"
chmod +x "${INSTALL_DIR}/${BIN_NAME}"
ln -sf "${INSTALL_DIR}/${BIN_NAME}" /usr/local/bin/astral

log "[astral-install] Preparing instance dirs"
mkdir -p /etc/astral
mkdir -p "/var/lib/astral/${NAME}"

ENV_PATH="/etc/astral/${NAME}.env"
log "[astral-install] Writing env: $ENV_PATH"
cat >"$ENV_PATH" <<EOF
CONFIG=$CONFIG_PATH
PORT=$PORT
EXTRA_OPTS=$EXTRA_OPTS
EOF

UNIT_PATH="/etc/systemd/system/astral@.service"
log "[astral-install] Writing unit template: $UNIT_PATH"
cat >"$UNIT_PATH" <<'EOF'
[Unit]
Description=ASTRAL Streaming Server (%i)
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
EnvironmentFile=/etc/astral/%i.env
WorkingDirectory=/var/lib/astral/%i
ExecStart=/bin/sh -lc 'exec /usr/local/bin/astral -c "$CONFIG" -p "$PORT" $EXTRA_OPTS'
Restart=always
RestartSec=2
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

log "[astral-install] Enabling and starting: astral@${NAME}.service"
systemctl daemon-reload
systemctl enable --now "astral@${NAME}.service"

log "[astral-install] Done. Status:"
systemctl --no-pager --full status "astral@${NAME}.service" || true

