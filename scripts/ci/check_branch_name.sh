#!/usr/bin/env bash
set -euo pipefail

# Enforce branch naming for PRs only.
# Expected: codex/<agent>/<topic>

if [[ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]]; then
  echo "Branch name check skipped (not a pull_request)."
  exit 0
fi

branch="${GITHUB_HEAD_REF:-}"
if [[ -z "$branch" ]]; then
  echo "Branch name check skipped (no GITHUB_HEAD_REF)."
  exit 0
fi

if [[ ! "$branch" =~ ^codex/[^/]+/.+ && ! "$branch" =~ ^codex/[^/]+$ ]]; then
  echo "ERROR: Invalid branch name: $branch"
  echo "Expected pattern: codex/<agent>/<topic>"
  exit 1
fi

echo "Branch name OK: $branch"
