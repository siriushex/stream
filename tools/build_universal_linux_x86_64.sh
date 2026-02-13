#!/usr/bin/env bash
set -euo pipefail

# Сборка "универсального" Linux x86_64 бинарника для старых Ubuntu.
# Требования:
# - docker
# - запускать на Linux x86_64 (на macOS это будет медленно/сложно из-за кросс-арх).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
IMAGE="stream-build-linux-compat:ubuntu16"

mkdir -p "$DIST_DIR"

echo "Building docker image: ${IMAGE}"
docker build -f "${ROOT_DIR}/tools/docker/Dockerfile.linux-compat" -t "${IMAGE}" "${ROOT_DIR}"

cid="$(docker create "${IMAGE}")"
trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT

out="${DIST_DIR}/stream-linux-x86_64"
echo "Extracting binary to: ${out}"
docker cp "${cid}:/out/stream" "${out}"
chmod +x "${out}"

echo "OK: ${out}"

