#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  check_sensitive_data.sh --staged
  check_sensitive_data.sh --all
  check_sensitive_data.sh --range <git-range>
EOF
}

mode=""
range=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --staged)
      mode="staged"
      shift
      ;;
    --all)
      mode="all"
      shift
      ;;
    --range)
      mode="range"
      range="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$mode" ]]; then
  mode="all"
fi

mapfile -t files < <(
  case "$mode" in
    staged)
      git diff --cached --name-only --diff-filter=ACMR
      ;;
    all)
      git ls-files
      ;;
    range)
      if [[ -z "$range" ]]; then
        echo "ERROR: --range requires a value" >&2
        exit 2
      fi
      git diff --name-only --diff-filter=ACMR "$range"
      ;;
  esac | sed '/^$/d' | sort -u
)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "Sensitive data check: no files to scan."
  exit 0
fi

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

violations=0

path_block_re='(^|/)(data(_[^/]+)?|site|stream-diag-[^/]+)(/|$)|(^|/)\.env(\..*)?$|(^|/)(id_rsa|id_ed25519)(\.pub)?$|(^|/).*\.(log|db|sqlite|sqlite3|pem|key|p12|pfx)$|(^|/)(AGENTS\.md|AI_NOTES\.md|Stream\.sublime-project|generate_art\.py|scenario_writer\.py|hlssplitter_20200305\.tar\.bz2|astra-241024|astra-250612|astra-linux-amd64|astra-linux-ubuntu22\.04|astra-macos-arm64)$'

declare -a content_checks=(
  '-----BEGIN [A-Z ]*PRIVATE KEY-----|Private key material'
  'root_blast|Private SSH key alias marker'
  '~/.ssh/|SSH key path leaked'
  'ssh[[:space:]]+-p[[:space:]]+[0-9]+[[:space:]]+-i[[:space:]]+|Raw SSH command leaked'
  'root@[0-9]{1,3}(\.[0-9]{1,3}){3}|Root login to raw IP leaked'
  '178\.212\.236\.2|Known private server IP leaked'
  '192\.168\.241\.104|Known private server IP leaked'
  '37\.221\.64\.117|Known private server IP leaked'
  'OPENAI_API_KEY[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']+["'"'"']|Hardcoded OPENAI key assignment'
  'ASTRAL_OPENAI_API_KEY[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']+["'"'"']|Hardcoded OpenAI key assignment'
  'Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._-]{12,}|Hardcoded bearer token'
)

for f in "${files[@]}"; do
  if printf '%s\n' "$f" | LC_ALL=C grep -Eq -- "$path_block_re"; then
    echo "ERROR: blocked path in git content: $f"
    violations=1
  fi

  if [[ "$f" == "scripts/ci/check_sensitive_data.sh" ]]; then
    continue
  fi

  case "$mode" in
    staged)
      if ! git cat-file -e ":$f" 2>/dev/null; then
        continue
      fi
      blob="$tmpdir/blob.txt"
      git show ":$f" > "$blob" || true
      ;;
    *)
      if [[ ! -f "$f" ]]; then
        continue
      fi
      blob="$f"
      ;;
  esac

  if LC_ALL=C grep -Iq . "$blob"; then
    :
  else
    continue
  fi

  for check in "${content_checks[@]}"; do
    re="${check%%|*}"
    title="${check#*|}"
    if LC_ALL=C grep -nE -- "$re" "$blob" >/dev/null; then
      echo "ERROR: $title in $f"
      LC_ALL=C grep -nE -- "$re" "$blob" | head -n 3 | sed 's/^/  /'
      violations=1
    fi
  done
done

if [[ "$violations" -ne 0 ]]; then
  cat <<'EOF'
Sensitive data check failed.
Remove sensitive content or move runtime artifacts to ignored paths.
EOF
  exit 1
fi

echo "Sensitive data check: OK."
