#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

set +e
output="$(scripts/ci/check_docs_seo.sh 2>&1)"
status=$?
set -e

if [[ "$status" -ne 0 ]]; then
  printf '%s\n' "$output" >&2
  echo "docs SEO check must skip a source-only checkout without mkdocs.yml" >&2
  exit 1
fi

grep -Fq '[docs-seo] SKIP: mkdocs.yml is not present in this source-only checkout' <<<"$output"

echo "Docs SEO missing-config test: OK."
