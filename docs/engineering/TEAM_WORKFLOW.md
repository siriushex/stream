# Team Workflow (Strict)

This repo is developed by multiple agents in parallel. These rules are mandatory and are designed to prevent conflicts and accidental overwrites.

## Scope
- Applies to all changes in this repository.
- The source of truth for code ownership is `.github/CODEOWNERS`.

## Branching
- No direct commits to `main`.
- Branch naming: `codex/<agent>/<topic>` (example: `codex/alex/tiles-compact`).
- Start from fresh `main`:
  - `git fetch origin`
  - `git checkout main`
  - `git pull --rebase`
  - `git checkout -b codex/<agent>/<topic>`

## Ownership & Reviews
- `.github/CODEOWNERS` defines folder ownership.
- Any change touching an owned path must be approved by its owners.
- If a change crosses multiple ownership areas, approvals are required from each.

## Merge Lock
- Only one agent merges to `main` at a time.
- Declare intent to merge in shared chat before starting and after completing the merge.

## Pre-Merge Requirements (Mandatory)
- CI workflow `ci` is green.
- CODEOWNERS approvals are present.
- `CHANGELOG.md` updated for every change.
- Rebase onto the latest `origin/main` and resolve conflicts on the branch.
- `main` merges are fast-forward only.

## Conflict Policy
- Conflicts must be resolved on the feature branch.
- Never force-push to `main`.

## Required Repository Settings (GitHub)
These are enforced in GitHub settings (not in code):
- Protect `main` branch.
- Require pull requests before merging.
- Require status checks to pass (`ci`).
- Require CODEOWNERS review.
- Require linear history.

## Automation Checklist
The CI workflow includes an ownership check. If `.github/CODEOWNERS` is missing required entries, CI fails.
