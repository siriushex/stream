#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: build_astral_bundle.sh [options]

Options:
  --arch <linux-x86_64|linux-aarch64>   Target arch (default: host)
  --profile <lgpl|gpl>                  FFmpeg profile (default: lgpl)
  --version <version>                   Bundle version override
  --output-dir <dir>                    Output directory (default: ./dist)
  --ffmpeg-local <path>                 Local ffmpeg tarball or binary
  --ffprobe-local <path>                Local ffprobe tarball or binary
  -h, --help                            Show help

Environment overrides:
  FFMPEG_URL / FFMPEG_SHA256            Download ffmpeg bundle tarball
  FFMPEG_FFPROBE_URL / FFMPEG_FFPROBE_SHA256  Optional separate ffprobe download

Examples:
  scripts/release/build_astral_bundle.sh --arch linux-x86_64 --profile lgpl
  FFMPEG_URL=... FFMPEG_SHA256=... scripts/release/build_astral_bundle.sh
USAGE
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/dist"
PROFILE="lgpl"
ARCH=""
VERSION_OVERRIDE=""
FFMPEG_LOCAL=""
FFPROBE_LOCAL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      ARCH="$2"
      shift 2
      ;;
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --version)
      VERSION_OVERRIDE="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --ffmpeg-local)
      FFMPEG_LOCAL="$2"
      shift 2
      ;;
    --ffprobe-local)
      FFPROBE_LOCAL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

normalize_arch() {
  local raw="$1"
  case "$raw" in
    linux-x86_64|linux-amd64)
      echo "linux-x86_64";
      ;;
    linux-aarch64|linux-arm64)
      echo "linux-aarch64";
      ;;
    x86_64|amd64)
      echo "linux-x86_64";
      ;;
    aarch64|arm64)
      echo "linux-aarch64";
      ;;
    *)
      echo "";
      ;;
  esac
}

if [[ -z "$ARCH" ]]; then
  ARCH="$(normalize_arch "$(uname -m)")"
else
  ARCH="$(normalize_arch "$ARCH")"
fi

if [[ -z "$ARCH" ]]; then
  echo "Unsupported arch. Use --arch linux-x86_64 or linux-aarch64." >&2
  exit 1
fi

if [[ "$PROFILE" != "lgpl" && "$PROFILE" != "gpl" ]]; then
  echo "Profile must be lgpl or gpl" >&2
  exit 1
fi

require_cmd curl
require_cmd tar
require_cmd python3

SHA256_CMD="sha256sum"
if ! command -v sha256sum >/dev/null 2>&1; then
  if command -v shasum >/dev/null 2>&1; then
    SHA256_CMD="shasum -a 256"
  else
    echo "Missing sha256sum (or shasum)" >&2
    exit 1
  fi
fi

if [[ -n "$FFMPEG_LOCAL" && ! -e "$FFMPEG_LOCAL" ]]; then
  echo "ffmpeg-local not found: $FFMPEG_LOCAL" >&2
  exit 1
fi
if [[ -n "$FFPROBE_LOCAL" && ! -e "$FFPROBE_LOCAL" ]]; then
  echo "ffprobe-local not found: $FFPROBE_LOCAL" >&2
  exit 1
fi

VERSION="$VERSION_OVERRIDE"
if [[ -z "$VERSION" ]]; then
  if [[ -f "$ROOT_DIR/version.h" ]]; then
    VERSION="$(grep -E '^#define ASTRA_VERSION' "$ROOT_DIR/version.h" | sed -E 's/.*"([^"]+)".*/\1/')"
  fi
fi
if [[ -z "$VERSION" ]]; then
  VERSION="$(git -C "$ROOT_DIR" describe --tags --always 2>/dev/null || echo "dev")"
fi

WORK_DIR="$(mktemp -d)"
STAGE_DIR="$WORK_DIR/astral-transcode-${VERSION}-${ARCH}-${PROFILE}"
mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/LICENSES"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fetch_with_sha() {
  local url="$1"
  local sha="$2"
  local dest="$3"
  if [[ -z "$url" || -z "$sha" ]]; then
    echo "Missing URL or SHA256" >&2
    exit 1
  fi
  echo "Downloading $url"
  curl -fsSL "$url" -o "$dest"
  echo "${sha}  ${dest}" | $SHA256_CMD -c -
}

extract_ffmpeg_bundle() {
  local archive="$1"
  local dest="$2"
  mkdir -p "$dest"
  tar -xf "$archive" -C "$dest"
}

resolve_from_archive() {
  local dir="$1"
  local name="$2"
  local found
  found="$(find "$dir" -type f -name "$name" -perm -111 | head -n 1)"
  if [[ -z "$found" ]]; then
    found="$(find "$dir" -type f -name "$name" | head -n 1)"
  fi
  echo "$found"
}

FFMPEG_BIN=""
FFPROBE_BIN=""
FFMPEG_SRC_URL=""
FFMPEG_SHA=""

if [[ -z "$FFMPEG_LOCAL" ]]; then
  if [[ -n "${FFMPEG_URL:-}" ]]; then
    if [[ -z "${FFMPEG_SHA256:-}" ]]; then
      echo "FFMPEG_SHA256 is required when FFMPEG_URL is set" >&2
      exit 1
    fi
    FFMPEG_SRC_URL="$FFMPEG_URL"
    FFMPEG_SHA="$FFMPEG_SHA256"
  else
    SOURCE_JSON="$ROOT_DIR/scripts/release/ffmpeg_sources.json"
    if [[ ! -f "$SOURCE_JSON" ]]; then
      echo "Missing $SOURCE_JSON" >&2
      exit 1
    fi
    readarray -t source_line < <(SOURCE_JSON="$SOURCE_JSON" ARCH="$ARCH" PROFILE="$PROFILE" python3 - <<'PY'
import json, os, sys
root = os.environ.get('SOURCE_JSON')
arch = os.environ.get('ARCH')
profile = os.environ.get('PROFILE')
with open(root, 'r', encoding='utf-8') as f:
    data = json.load(f)
entry = data.get(arch, {}).get(profile)
if not entry:
    print('', file=sys.stderr)
    sys.exit(1)
print(entry['url'])
print(entry['sha256'])
PY
    )
    if [[ ${#source_line[@]} -lt 2 ]]; then
      echo "No ffmpeg source for $ARCH/$PROFILE" >&2
      exit 1
    fi
    FFMPEG_SRC_URL="${source_line[0]}"
    FFMPEG_SHA="${source_line[1]}"
  fi

  ARCHIVE="$WORK_DIR/ffmpeg_bundle.tar"
  fetch_with_sha "$FFMPEG_SRC_URL" "$FFMPEG_SHA" "$ARCHIVE"
  EXTRACT_DIR="$WORK_DIR/ffmpeg_extract"
  extract_ffmpeg_bundle "$ARCHIVE" "$EXTRACT_DIR"
  FFMPEG_BIN="$(resolve_from_archive "$EXTRACT_DIR" ffmpeg)"
  FFPROBE_BIN="$(resolve_from_archive "$EXTRACT_DIR" ffprobe)"
  if [[ -z "$FFMPEG_BIN" ]]; then
    echo "ffmpeg binary not found in bundle" >&2
    exit 1
  fi
  if [[ -z "$FFPROBE_BIN" ]]; then
    echo "ffprobe binary not found in bundle" >&2
    exit 1
  fi
else
  if [[ "$FFMPEG_LOCAL" == *.tar.gz || "$FFMPEG_LOCAL" == *.tar.xz || "$FFMPEG_LOCAL" == *.tgz ]]; then
    EXTRACT_DIR="$WORK_DIR/ffmpeg_extract"
    extract_ffmpeg_bundle "$FFMPEG_LOCAL" "$EXTRACT_DIR"
    FFMPEG_BIN="$(resolve_from_archive "$EXTRACT_DIR" ffmpeg)"
    FFPROBE_BIN="$(resolve_from_archive "$EXTRACT_DIR" ffprobe)"
  else
    FFMPEG_BIN="$FFMPEG_LOCAL"
    if [[ -z "$FFPROBE_LOCAL" ]]; then
      FFPROBE_BIN="$(dirname "$FFMPEG_LOCAL")/ffprobe"
      if [[ ! -x "$FFPROBE_BIN" ]]; then
        FFPROBE_BIN=""
      fi
    fi
  fi
fi

if [[ -n "${FFMPEG_FFPROBE_URL:-}" ]]; then
  if [[ -z "${FFMPEG_FFPROBE_SHA256:-}" ]]; then
    echo "FFMPEG_FFPROBE_SHA256 is required when FFMPEG_FFPROBE_URL is set" >&2
    exit 1
  fi
  PROBE_ARCHIVE="$WORK_DIR/ffprobe_bundle"
  fetch_with_sha "$FFMPEG_FFPROBE_URL" "$FFMPEG_FFPROBE_SHA256" "$PROBE_ARCHIVE"
  case "$FFMPEG_FFPROBE_URL" in
    *.tar|*.tar.gz|*.tgz|*.tar.xz)
      PROBE_DIR="$WORK_DIR/ffprobe_extract"
      extract_ffmpeg_bundle "$PROBE_ARCHIVE" "$PROBE_DIR"
      FFPROBE_BIN="$(resolve_from_archive "$PROBE_DIR" ffprobe)"
      ;;
    *)
      FFPROBE_BIN="$PROBE_ARCHIVE"
      ;;
  esac
fi

if [[ -z "$FFPROBE_BIN" && -n "$FFPROBE_LOCAL" ]]; then
  if [[ "$FFPROBE_LOCAL" == *.tar.gz || "$FFPROBE_LOCAL" == *.tar.xz || "$FFPROBE_LOCAL" == *.tgz ]]; then
    PROBE_DIR="$WORK_DIR/ffprobe_extract"
    extract_ffmpeg_bundle "$FFPROBE_LOCAL" "$PROBE_DIR"
    FFPROBE_BIN="$(resolve_from_archive "$PROBE_DIR" ffprobe)"
  else
    FFPROBE_BIN="$FFPROBE_LOCAL"
  fi
fi

if [[ -z "$FFMPEG_BIN" || -z "$FFPROBE_BIN" ]]; then
  echo "Unable to resolve ffmpeg/ffprobe binaries" >&2
  exit 1
fi

if [[ ! -x "$FFMPEG_BIN" ]]; then
  chmod +x "$FFMPEG_BIN" 2>/dev/null || true
fi
if [[ ! -x "$FFPROBE_BIN" ]]; then
  chmod +x "$FFPROBE_BIN" 2>/dev/null || true
fi

if [[ ! -x "$ROOT_DIR/astra" ]]; then
  echo "Building astra..."
  (cd "$ROOT_DIR" && ./configure.sh && make)
fi
if [[ ! -x "$ROOT_DIR/astra" ]]; then
  echo "astra binary not found after build" >&2
  exit 1
fi

cp "$ROOT_DIR/astra" "$STAGE_DIR/bin/astra"
cat > "$STAGE_DIR/bin/astral" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ASTRA_BASE_DIR="$BASE_DIR"
export ASTRA_EDITION="${ASTRA_EDITION:-ASTRAL}"
export PATH="$BASE_DIR/bin:$PATH"
exec "$BASE_DIR/bin/astra" "$@"
SH
chmod +x "$STAGE_DIR/bin/astral"

cat > "$STAGE_DIR/run.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ASTRA_BASE_DIR="$BASE_DIR"
export ASTRA_EDITION="${ASTRA_EDITION:-ASTRAL}"
export PATH="$BASE_DIR/bin:$PATH"
exec "$BASE_DIR/bin/astral" "$@"
SH
chmod +x "$STAGE_DIR/run.sh"

cp -R "$ROOT_DIR/web" "$STAGE_DIR/"
cp -R "$ROOT_DIR/scripts" "$STAGE_DIR/"

cp "$FFMPEG_BIN" "$STAGE_DIR/bin/ffmpeg"
cp "$FFPROBE_BIN" "$STAGE_DIR/bin/ffprobe"

if [[ -f "$ROOT_DIR/COPYING" ]]; then
  cp "$ROOT_DIR/COPYING" "$STAGE_DIR/LICENSES/ASTRA_LICENSE.txt"
fi

if [[ -n "${EXTRACT_DIR:-}" ]]; then
  for candidate in "$EXTRACT_DIR"/*/LICENSE* "$EXTRACT_DIR"/*/COPYING* "$EXTRACT_DIR"/LICENSE*; do
    if [[ -f "$candidate" ]]; then
      cp "$candidate" "$STAGE_DIR/LICENSES/FFMPEG_LICENSE.txt"
      break
    fi
  done
  for candidate in "$EXTRACT_DIR"/*/README* "$EXTRACT_DIR"/README*; do
    if [[ -f "$candidate" ]]; then
      cp "$candidate" "$STAGE_DIR/LICENSES/FFMPEG_README.txt"
      break
    fi
  done
fi

BUILD_INFO="$STAGE_DIR/LICENSES/FFMPEG_BUILD_INFO.txt"
{
  echo "Source: ${FFMPEG_SRC_URL:-local}"
  if [[ -n "$FFMPEG_SHA" ]]; then
    echo "SHA256: ${FFMPEG_SHA}"
  fi
  echo "Profile: ${PROFILE}"
  echo "Built at: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  if [[ -x "$STAGE_DIR/bin/ffmpeg" ]]; then
    version_line="$($STAGE_DIR/bin/ffmpeg -hide_banner -version 2>/dev/null | head -n 1 || true)"
    if [[ -n "$version_line" ]]; then
      echo "ffmpeg version: $version_line"
    else
      echo "ffmpeg version: unavailable"
    fi
  fi
} > "$BUILD_INFO"

if [[ -d "$ROOT_DIR/contrib/systemd" ]]; then
  mkdir -p "$STAGE_DIR/systemd"
  cp -R "$ROOT_DIR/contrib/systemd"/* "$STAGE_DIR/systemd/" || true
fi

mkdir -p "$OUTPUT_DIR"
BUNDLE_NAME="astral-transcode-${VERSION}-${ARCH}"
if [[ "$PROFILE" == "gpl" ]]; then
  BUNDLE_NAME+="-gpl"
else
  BUNDLE_NAME+="-lgpl"
fi
BUNDLE_NAME+=".tar.gz"

TAR_PATH="$OUTPUT_DIR/$BUNDLE_NAME"
( cd "$WORK_DIR" && tar -czf "$TAR_PATH" "$(basename "$STAGE_DIR")" )

( cd "$OUTPUT_DIR" && sha256sum "$BUNDLE_NAME" > "SHA256SUMS" )

echo "Bundle created: $TAR_PATH"
