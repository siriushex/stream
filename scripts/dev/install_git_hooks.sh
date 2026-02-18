#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/pre-push scripts/ci/check_sensitive_data.sh

echo "Git hooks installed: core.hooksPath=.githooks"
