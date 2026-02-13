#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

usage() {
  cat <<'USAGE'
Usage:
  sudo ./install.sh [options]

Modes:
  --mode source|binary     Download and build from sources, or download a ready binary.

Source/binary download:
  --url URL                Explicit URL to download (source tarball or binary).
  --base-url URL           Base URL for artifacts (default: https://a.centv.ru).
  --artifact NAME          Artifact filename under base URL.

Install paths:
  --bin PATH               Install path for the binary (default: /usr/local/bin/stream).
  --data-dir DIR           Config/data root (default: /etc/stream).
  --workdir DIR            Temporary build dir (default: /tmp/stream-build).

Web assets:
  --install-web            Copy web assets to /usr/local/share/stream/web (optional override from disk).
  --no-web                 Do not install web assets (UI will be served from embedded bundle).

Service:
  --name NAME              Instance name (creates /etc/stream/NAME.json and NAME.env).
  --port PORT              HTTP port for the instance (requires --name).
  --enable                 Enable+start systemd unit after install (requires --name).

Deps:
  --no-ffmpeg              Skip installing ffmpeg/ffprobe + dev libs.
  --runtime-only           Install only runtime deps (no compiler toolchain). Requires --mode binary.
  --dry-run                Print actions without running them.
  -h, --help               Show help.

Notes:
  - Supports CentOS/RHEL/Rocky/Alma and Debian/Ubuntu.
  - Source mode builds locally using ./configure.sh && make.
  - By default, build artifacts are removed after install.
USAGE
}

MODE="source"
URL=""
BASE_URL="https://a.centv.ru"
ARTIFACT=""
BIN_PATH="/usr/local/bin/stream"
DATA_DIR="/etc/stream"
WORKDIR="/tmp/stream-build"
INSTALL_WEB=0
INSTALL_FFMPEG=1
RUNTIME_ONLY=0
DRY_RUN=0
NAME=""
PORT=""
ENABLE_SERVICE=0

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] $*"
    return 0
  fi
  "$@"
}

while [ "${#:-0}" -gt 0 ]; do
  case "${1:-}" in
    --mode)
      MODE="${2:-}"; shift 2;;
    --url)
      URL="${2:-}"; shift 2;;
    --base-url)
      BASE_URL="${2:-}"; shift 2;;
    --artifact)
      ARTIFACT="${2:-}"; shift 2;;
    --bin)
      BIN_PATH="${2:-}"; shift 2;;
    --data-dir)
      DATA_DIR="${2:-}"; shift 2;;
    --workdir)
      WORKDIR="${2:-}"; shift 2;;
    --install-web)
      INSTALL_WEB=1; shift;;
    --no-web)
      INSTALL_WEB=0; shift;;
    --no-ffmpeg)
      INSTALL_FFMPEG=0; shift;;
    --runtime-only)
      RUNTIME_ONLY=1; shift;;
    --dry-run)
      DRY_RUN=1; shift;;
    --name)
      NAME="${2:-}"; shift 2;;
    --port)
      PORT="${2:-}"; shift 2;;
    --enable)
      ENABLE_SERVICE=1; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      die "Unknown argument: ${1:-}";;
  esac
done

if [ "$(uname -s)" != "Linux" ]; then
  die "This installer must be run on Linux."
fi

if [ "$(id -u)" -ne 0 ]; then
  die "Please run as root (sudo)."
fi

PKG_MGR=""
if command -v apt-get >/dev/null 2>&1; then
  PKG_MGR="apt"
elif command -v dnf >/dev/null 2>&1; then
  PKG_MGR="dnf"
elif command -v yum >/dev/null 2>&1; then
  PKG_MGR="yum"
else
  die "No supported package manager found (apt, dnf, yum)."
fi

. /etc/os-release || true
OS_ID="${ID:-unknown}"
OS_LIKE="${ID_LIKE:-}"
OS_VER="${VERSION_ID:-}"
OS_CODENAME="${VERSION_CODENAME:-}"

ARCH="$(uname -m)"

ensure_dirs() {
  run mkdir -p "$DATA_DIR"
  run chmod 755 "$DATA_DIR"
}

install_deps_debian() {
  run apt-get update -y
  # Ubuntu keeps ffmpeg and some optional deps in "universe". Enable it on-demand.
  if [ "${OS_ID:-}" = "ubuntu" ]; then
    if ! apt-cache show ffmpeg >/dev/null 2>&1; then
      run apt-get install -y --no-install-recommends software-properties-common
      if command -v add-apt-repository >/dev/null 2>&1; then
        run add-apt-repository -y universe || true
        run apt-get update -y
      else
        warn "add-apt-repository not found; ffmpeg/libdvbcsa packages may be unavailable."
      fi
    fi
  fi

  run apt-get install -y --no-install-recommends ca-certificates curl tar gzip xz-utils git gcc make pkg-config python3 \
    openssl libssl-dev libsqlite3-dev

  if [ "$INSTALL_FFMPEG" -eq 1 ]; then
    run apt-get install -y --no-install-recommends ffmpeg libavcodec-dev libavutil-dev
  fi

  # Optional deps (soft failure if missing in repo)
  run apt-get install -y --no-install-recommends libdvbcsa-dev libpq-dev || true
}

install_runtime_deps_debian() {
  run apt-get update -y

  # Ubuntu: ensure universe for ffmpeg/libdvbcsa runtime packages.
  if [ "${OS_ID:-}" = "ubuntu" ]; then
    if ! apt-cache show ffmpeg >/dev/null 2>&1; then
      run apt-get install -y --no-install-recommends software-properties-common
      if command -v add-apt-repository >/dev/null 2>&1; then
        run add-apt-repository -y universe || true
        run apt-get update -y
      else
        warn "add-apt-repository not found; some packages may be unavailable."
      fi
    fi
  fi

  run apt-get install -y --no-install-recommends ca-certificates curl

  if [ "$INSTALL_FFMPEG" -eq 1 ]; then
    run apt-get install -y --no-install-recommends ffmpeg
  fi

  # Runtime libraries for dynamically linked builds.
  run apt-get install -y --no-install-recommends libsqlite3-0 libpq5 libdvbcsa1 || true
  # OpenSSL runtime package name depends on Ubuntu/Debian version.
  run apt-get install -y --no-install-recommends libssl3 || run apt-get install -y --no-install-recommends libssl1.1 || true
}

enable_epel_rhel() {
  if [ -f /etc/redhat-release ] && ! rpm -q epel-release >/dev/null 2>&1; then
    run "$PKG_MGR" -y install epel-release || true
  fi
}

enable_rpmfusion() {
  if rpm -q rpmfusion-free-release >/dev/null 2>&1; then
    return 0
  fi
  if [ -f /etc/redhat-release ]; then
    local rel
    rel=$(rpm -E %rhel)
    if [ -n "$rel" ]; then
      run "$PKG_MGR" -y install "https://download1.rpmfusion.org/free/el/rpmfusion-free-release-${rel}.noarch.rpm" || true
    fi
  fi
}

install_deps_rhel() {
  enable_epel_rhel
  run "$PKG_MGR" -y install ca-certificates curl tar gzip xz git gcc make pkgconfig \
    openssl-devel sqlite-devel

  # Optional deps: dvbcsa, postgres
  run "$PKG_MGR" -y install libdvbcsa-devel postgresql-devel || true

  if [ "$INSTALL_FFMPEG" -eq 1 ]; then
    enable_rpmfusion
    run "$PKG_MGR" -y install ffmpeg ffmpeg-devel || true
  fi
}

install_runtime_deps_rhel() {
  enable_epel_rhel
  run "$PKG_MGR" -y install ca-certificates curl sqlite-libs openssl-libs || true
  run "$PKG_MGR" -y install libdvbcsa postgresql-libs || true
  if [ "$INSTALL_FFMPEG" -eq 1 ]; then
    enable_rpmfusion
    run "$PKG_MGR" -y install ffmpeg || true
  fi
}

resolve_url() {
  if [ -n "$URL" ]; then
    printf '%s' "$URL"
    return 0
  fi

  if [ -n "$ARTIFACT" ]; then
    printf '%s/%s' "$BASE_URL" "$ARTIFACT"
    return 0
  fi

  if [ "$MODE" = "binary" ]; then
    # Default artifact naming for prebuilt binaries. Override with --artifact/--url if needed.
    printf '%s/stream-linux-%s' "$BASE_URL" "$ARCH"
    return 0
  fi

  # Default source tarball name guesses.
  printf '%s/stream-src.tar.gz' "$BASE_URL"
}

fetch_artifact() {
  local url="$1"
  local out="$2"
  run curl -fsSL -o "$out" "$url"
}

build_from_source() {
  local url
  url=$(resolve_url)
  log "Downloading sources: $url"

  run rm -rf "$WORKDIR"
  run mkdir -p "$WORKDIR"
  local archive="$WORKDIR/stream-src.tar.gz"
  fetch_artifact "$url" "$archive"

  run tar -xf "$archive" -C "$WORKDIR"

  local src_root
  src_root=$(find "$WORKDIR" -maxdepth 3 -name configure.sh -print -quit | xargs -r dirname)
  if [ -z "$src_root" ]; then
    die "Could not find configure.sh in extracted sources. Provide --url explicitly."
  fi

  log "Building from: $src_root"
  (cd "$src_root" && ./configure.sh && make -j"$(getconf _NPROCESSORS_ONLN || echo 2)")

  if [ ! -x "$src_root/astra" ]; then
    die "Build succeeded but binary 'astra' not found."
  fi

  run install -m 755 "$src_root/astra" "$BIN_PATH"

  if [ "$INSTALL_WEB" -eq 1 ]; then
    run mkdir -p /usr/local/share/stream/web
    run cp -r "$src_root/web"/* /usr/local/share/stream/web/
  fi

  run rm -rf "$WORKDIR"
}

install_binary() {
  local url
  url=$(resolve_url)
  log "Downloading binary: $url"
  run mkdir -p "$(dirname "$BIN_PATH")"
  fetch_artifact "$url" "$BIN_PATH"
  run chmod 755 "$BIN_PATH"
}

write_systemd_unit() {
  local unit_path="/etc/systemd/system/stream@.service"
  if [ ! -f "$unit_path" ]; then
    cat > "$unit_path" <<'UNIT'
[Unit]
Description=Stream server (%i)
After=network.target

[Service]
Type=simple
EnvironmentFile=-/etc/stream/%i.env
WorkingDirectory=/etc/stream
ExecStart=/usr/local/bin/stream -c /etc/stream/%i.json -p ${STREAM_PORT:-8816}
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
  fi
  run systemctl daemon-reload
}

write_instance_files() {
  if [ -z "$NAME" ]; then
    return 0
  fi

  local cfg="$DATA_DIR/${NAME}.json"
  local env="$DATA_DIR/${NAME}.env"

  if [ ! -f "$cfg" ]; then
    printf '{}' > "$cfg"
  fi

  if [ -z "$PORT" ]; then
    PORT="8816"
  fi

  {
    printf 'STREAM_PORT=%s\n' "$PORT"
    if [ "$INSTALL_WEB" -eq 1 ]; then
      printf 'ASTRAL_WEB_DIR=%s\n' "/usr/local/share/stream/web"
    fi
  } > "$env"
}

maybe_enable_service() {
  if [ "$ENABLE_SERVICE" -ne 1 ] || [ -z "$NAME" ]; then
    return 0
  fi
  run systemctl enable --now "stream@${NAME}.service"
}

main() {
  if [ "$MODE" != "source" ] && [ "$MODE" != "binary" ]; then
    die "Unsupported --mode: $MODE (use source or binary)"
  fi

  if [ "$RUNTIME_ONLY" -eq 1 ] && [ "$MODE" != "binary" ]; then
    die "--runtime-only requires --mode binary"
  fi

  ensure_dirs

  if [ "$PKG_MGR" = "apt" ]; then
    if [ "$RUNTIME_ONLY" -eq 1 ]; then
      install_runtime_deps_debian
    else
      install_deps_debian
    fi
  else
    if [ "$RUNTIME_ONLY" -eq 1 ]; then
      install_runtime_deps_rhel
    else
      install_deps_rhel
    fi
  fi

  if [ "$MODE" = "source" ]; then
    build_from_source
  else
    install_binary
  fi

  if [ "$INSTALL_WEB" -eq 0 ]; then
    log "Web assets not installed. UI will be served from embedded bundle."
  fi

  write_systemd_unit
  write_instance_files
  maybe_enable_service

  log "Done. Binary: $BIN_PATH"
  log "Config root: $DATA_DIR"
}

main
