#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <host> [port] [ssh_key]"
  echo "Example: $0 root@178.212.236.2 40242 ~/.ssh/root_blast"
  exit 1
fi

HOST="$1"
PORT="${2:-40242}"
KEY="${3:-$HOME/.ssh/root_blast}"

ROOT_DIR="/Users/mac/0009/astra"

echo "[deploy] rsync -> ${HOST} (port ${PORT})"
rsync -az --delete -e "ssh -p ${PORT} -i ${KEY}" \
  --exclude '.git' --exclude '.DS_Store' \
  --exclude 'astra' --exclude 'astral' \
  --exclude 'data' --exclude 'data/*' --exclude 'data_*' \
  --exclude 'logs' --exclude '*.db' --exclude '*.sqlite*' --exclude 'release' \
  "${ROOT_DIR}/" "${HOST}:/home/hex/astra/"

echo "[deploy] rebuild on ${HOST}"
ssh -p "${PORT}" -i "${KEY}" "${HOST}" \
  'cd /home/hex/astra && ./configure.sh --with-libdvbcsa && make -j"$(nproc)"'

echo "[deploy] done"
