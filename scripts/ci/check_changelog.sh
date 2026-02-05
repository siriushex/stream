#!/usr/bin/env bash
set -euo pipefail

# Enforce CHANGELOG update for PRs only.

if [[ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]]; then
  echo "CHANGELOG check skipped (not a pull_request)."
  exit 0
fi

base_ref="${GITHUB_BASE_REF:-}"
if [[ -z "$base_ref" ]]; then
  echo "CHANGELOG check skipped (no GITHUB_BASE_REF)."
  exit 0
fi

# Ensure base ref is available even with shallow checkout.
git fetch origin "$base_ref":"refs/remotes/origin/$base_ref" --depth=50

# If merge base is missing, deepen fetch to avoid "no merge base" in shallow clones.
if ! git merge-base "origin/$base_ref" HEAD >/dev/null 2>&1; then
  if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
    git fetch --unshallow origin || git fetch origin "$base_ref":"refs/remotes/origin/$base_ref" --depth=2000
  else
    git fetch origin "$base_ref":"refs/remotes/origin/$base_ref" --depth=2000
  fi
fi

if ! git diff --name-only "origin/$base_ref...HEAD" | grep -q '^CHANGELOG.md$'; then
  echo "ERROR: CHANGELOG.md not updated in this PR."
  exit 1
fi

echo "CHANGELOG OK"
