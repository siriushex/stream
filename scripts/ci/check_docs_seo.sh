#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

if [[ ! -d ".venv-docs" ]]; then
  python3 -m venv .venv-docs
fi

./.venv-docs/bin/python -m pip -q install --upgrade pip
./.venv-docs/bin/python -m pip -q install \
  mkdocs==1.6.1 \
  mkdocs-material==9.6.5 \
  pymdown-extensions

./.venv-docs/bin/mkdocs build --strict >/tmp/stream_docs_build.log

fail() {
  echo "[docs-seo] FAIL: $1" >&2
  exit 1
}

[[ -f site/sitemap.xml ]] || fail "missing site/sitemap.xml"
[[ -f site/robots.txt ]] || fail "missing site/robots.txt"
[[ -f site/search/search_index.json ]] || fail "missing site/search/search_index.json"

grep -q "Sitemap: https://stream.centv.ru/sitemap.xml" site/robots.txt || fail "robots.txt missing Sitemap link"
grep -q "Disallow: /admin/" site/robots.txt || fail "robots.txt missing Disallow /admin/"
grep -q "Disallow: /admin/api/" site/robots.txt || fail "robots.txt missing Disallow /admin/api/"
grep -q "FAQPage" site/faq/index.html || fail "FAQ schema is missing on /faq/"
if grep -q "https://stream.centv.ru/admin/" site/sitemap.xml; then
  fail "sitemap must not contain /admin/"
fi

pages=(
  "/"
  "about/what-is-stream-hub/"
  "about/stream-hub-iptv/"
  "about/why-stream-hub/"
  "about/stream-hub-web-ui/"
  "about/stream-hub-api/"
  "about/stream-hub-monitoring/"
  "quick-start/"
  "quick-start/installation/"
  "quick-start/run/"
  "quick-start/web-ui/"
  "quick-start/first-stream/"
  "quick-start/check-playback/"
  "quick-start/run-as-service/"
  "faq/"
  "manual/troubleshooting/"
  "changelog/"
)

for page in "${pages[@]}"; do
  if [[ "${page}" == "/" ]]; then
    file="site/index.html"
  else
    file="site/${page}index.html"
  fi

  [[ -f "${file}" ]] || fail "missing built page: ${file}"

  title="$(perl -ne 'if (/<title>(.*?)<\/title>/){print $1; exit}' "${file}")"
  desc="$(perl -ne 'if (/<meta name="description" content="(.*?)"/){print $1; exit}' "${file}")"
  canonical="$(perl -ne 'if (/<link rel="canonical" href="(.*?)"/){print $1; exit}' "${file}")"

  [[ -n "${title}" ]] || fail "missing <title> on ${page}"
  [[ -n "${desc}" ]] || fail "missing meta description on ${page}"
  [[ -n "${canonical}" ]] || fail "missing canonical on ${page}"

  title_len=${#title}
  desc_len=${#desc}

  if (( title_len < 50 || title_len > 60 )); then
    fail "title length out of range on ${page}: ${title_len}"
  fi
  if (( desc_len < 140 || desc_len > 160 )); then
    fail "description length out of range on ${page}: ${desc_len}"
  fi
done

echo "[docs-seo] PASS"
