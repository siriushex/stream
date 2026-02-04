#!/usr/bin/env bash
set -euo pipefail

file=".github/CODEOWNERS"

if [[ ! -f "$file" ]]; then
  echo "ERROR: $file is missing."
  exit 1
fi

required_patterns=(
  '^\*\s+.+\S'
  '^/web/\s+.+\S'
  '^/scripts/\s+.+\S'
  '^/modules/\s+.+\S'
  '^/core/\s+.+\S'
  '^/docs/\s+.+\S'
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Eq "$pattern" "$file"; then
    echo "ERROR: Missing CODEOWNERS entry matching pattern: $pattern"
    exit 1
  fi
done

echo "CODEOWNERS OK"
