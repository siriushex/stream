#!/usr/bin/env bash
set -euo pipefail

# При запуске через pipe (curl | bash) BASH_SOURCE может быть пустым, а set -u
# превращает обращение к BASH_SOURCE[0] в фатальную ошибку.

usage() {
  cat <<'USAGE'
Usage:
  sudo ./install.sh [options]

Modes:
  --mode source|binary     Download and build from sources, or download a ready binary.

Source/binary download:
  --url URL                Explicit URL to download (source tarball or binary).
  --base-url URL           Base URL for artifacts (default: https://stream.centv.ru).
  --artifact NAME          Artifact filename under base URL.
  --git-url URL            Git repository URL for --mode source (default: https://github.com/siriushex/stream.git).
  --git-ref REF            Git ref/branch/tag for --mode source (default: main).
  --allow-generic          Allow generic binary on older distros (may be incompatible).

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
  --ffmpeg-bundle          Install a bundled ffmpeg/ffprobe (recommended on CentOS 7).
  --ffmpeg-system          Use distro packages for ffmpeg/ffprobe (default on Debian/Ubuntu).
  --runtime-only           Install only runtime deps (no compiler toolchain). Requires --mode binary.
  --verify-transcode       After install, verify FULL build + ffmpeg availability (exit non-zero on failure).
  --no-verify-transcode    Disable transcode verification (overrides --verify-transcode).
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
# Default artifact host. Can be overridden with --base-url/--url.
BASE_URL="https://stream.centv.ru"
ARTIFACT=""
GIT_URL="https://github.com/siriushex/stream.git"
GIT_REF="main"
BIN_PATH="/usr/local/bin/stream"
DATA_DIR="/etc/stream"
WORKDIR="/tmp/stream-build"
INSTALL_WEB=0
INSTALL_FFMPEG=1
FFMPEG_MODE="auto"
RUNTIME_ONLY=0
DRY_RUN=0
INSTANCE_NAME=""
PORT=""
ENABLE_SERVICE=0
ALLOW_GENERIC=0
VERIFY_TRANSCODE=0
INSTALLER_VERSION="1.2.4"
STREAM_RELEASE="${STREAM_RELEASE:-1.2.4}"

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

STREAM_TMP_BIN=""
cleanup_tmp() {
  if [ -n "${STREAM_TMP_BIN:-}" ] && [ -f "${STREAM_TMP_BIN:-}" ]; then
    rm -f "$STREAM_TMP_BIN" >/dev/null 2>&1 || true
  fi
}
trap cleanup_tmp EXIT

is_elf_binary() {
  # Если вместо бинарника скачался HTML (например, index.html), не устанавливаем.
  # ELF magic: 0x7f 'E' 'L' 'F' -> 7f454c46.
  local f="$1"
  if [ ! -f "$f" ]; then
    return 1
  fi
  local magic
  magic="$(dd if="$f" bs=1 count=4 2>/dev/null | od -An -t x1 | tr -d ' \n' || true)"
  [ "$magic" = "7f454c46" ]
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] $*"
    return 0
  fi
  "$@"
}

curl_download() {
  local url="$1"
  local out="$2"
  # Keep downloads predictable on unstable links: short connect timeout +
  # retries. Works on legacy CentOS curl as well.
  run curl -fL -sS --retry 3 --retry-delay 1 --connect-timeout 10 --max-time 600 -o "$out" "$url"
}

detect_make_jobs() {
  if [ -n "${STREAM_MAKE_JOBS:-}" ]; then
    printf '%s' "$STREAM_MAKE_JOBS"
    return 0
  fi
  local jobs
  jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
  if ! echo "$jobs" | grep -Eq '^[0-9]+$'; then
    jobs=2
  fi
  if [ "$jobs" -lt 1 ]; then
    jobs=1
  fi
  # Avoid aggressive oversubscription on older CentOS hosts with limited RAM.
  if [ "$jobs" -gt 8 ]; then
    jobs=8
  fi
  printf '%s' "$jobs"
}

ensure_stream_path_compat() {
  # Some CentOS/RHEL environments run helper subprocesses with a minimal PATH
  # that does not include /usr/local/bin. Keep a compatibility symlink in /usr/bin
  # when it is safe to do so.
  local compat_link="/usr/bin/stream"
  if [ "$BIN_PATH" = "$compat_link" ]; then
    return 0
  fi
  if [ ! -d /usr/bin ]; then
    return 0
  fi

  if [ -L "$compat_link" ]; then
    local current=""
    current="$(readlink "$compat_link" 2>/dev/null || true)"
    if [ "$current" != "$BIN_PATH" ]; then
      run ln -sfn "$BIN_PATH" "$compat_link"
    fi
    return 0
  fi

  if [ -e "$compat_link" ]; then
    if [ -f "$compat_link" ] && [ -f "$BIN_PATH" ] && [ "$compat_link" -ef "$BIN_PATH" ]; then
      return 0
    fi
    warn "$compat_link exists and is not a symlink; leaving it unchanged"
    return 0
  fi

  run ln -s "$BIN_PATH" "$compat_link"
}

resolve_stream_share_scripts_dir() {
  local bin_dir
  local prefix
  bin_dir="$(dirname "$BIN_PATH")"
  prefix="$(cd "$bin_dir/.." 2>/dev/null && pwd -P || true)"
  if [ -z "$prefix" ] || [ "$prefix" = "/" ]; then
    prefix="/usr/local"
  fi
  printf '%s' "${prefix}/share/stream/scripts"
}

install_runtime_scripts_from_source() {
  local src_root="$1"
  [ -n "$src_root" ] || return 0
  [ -d "$src_root/scripts" ] || return 0

  local dst
  dst="$(resolve_stream_share_scripts_dir)"
  run mkdir -p "$dst"

  local helper_scripts=(
    export_write.lua
    base.lua
    config.lua
  )
  local name=""
  for name in "${helper_scripts[@]}"; do
    if [ -f "$src_root/scripts/$name" ]; then
      run install -m 644 "$src_root/scripts/$name" "$dst/$name"
    fi
  done
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
    --git-url)
      GIT_URL="${2:-}"; shift 2;;
    --git-ref)
      GIT_REF="${2:-}"; shift 2;;
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
    --ffmpeg-bundle)
      FFMPEG_MODE="bundle"; shift;;
    --ffmpeg-system)
      FFMPEG_MODE="system"; shift;;
    --runtime-only)
      RUNTIME_ONLY=1; shift;;
    --allow-generic)
      ALLOW_GENERIC=1; shift;;
    --verify-transcode)
      VERIFY_TRANSCODE=1; shift;;
    --no-verify-transcode)
      VERIFY_TRANSCODE=0; shift;;
    --dry-run)
      DRY_RUN=1; shift;;
    --name)
      INSTANCE_NAME="${2:-}"; shift 2;;
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

normalize_ffmpeg_arch() {
  case "${ARCH:-}" in
    x86_64|amd64)
      printf '%s' "linux-x86_64"
      ;;
    aarch64|arm64)
      printf '%s' "linux-aarch64"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

resolve_sha256_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "sha256sum"
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "shasum -a 256"
    return 0
  fi
  printf '%s' ""
  return 0
}

ffmpeg_bundle_url_sha() {
  # Returns: "url|sha256"
  local arch="$1"
  local profile="$2"
  case "$arch/$profile" in
    linux-x86_64/lgpl)
      printf '%s' "https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-02-05-13-01/ffmpeg-N-122647-gb628cafd48-linux64-lgpl.tar.xz|00e8808415fc081af9f96ed0a36c1022a9e0766429f1c0835a4c2320d7e6e35e"
      ;;
    linux-x86_64/gpl)
      printf '%s' "https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-02-05-13-01/ffmpeg-N-122647-gb628cafd48-linux64-gpl.tar.xz|9f63ca812df522e944065c8011ff10f8aa6d043230a0cf28e868bf5c05d18877"
      ;;
    linux-aarch64/lgpl)
      printf '%s' "https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-02-05-13-01/ffmpeg-N-122647-gb628cafd48-linuxarm64-lgpl.tar.xz|cb1ed6d420523fba7d81313458cc0ea9271c392976f399384d617105ee42a160"
      ;;
    linux-aarch64/gpl)
      printf '%s' "https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-02-05-13-01/ffmpeg-N-122647-gb628cafd48-linuxarm64-gpl.tar.xz|061235d7f44059fbf0b2e2068f43f1fbddcdf35400e1c25dc7a2c84161b031eb"
      ;;
    *)
      printf '%s' ""
      ;;
  esac
}

FFMPEG_BUNDLE_INSTALLED=0
FFMPEG_BUNDLE_PROFILE="${FFMPEG_BUNDLE_PROFILE:-lgpl}"
FFMPEG_BIN_PATH="/usr/local/bin/stream-ffmpeg"
FFPROBE_BIN_PATH="/usr/local/bin/stream-ffprobe"

install_ffmpeg_bundle() {
  if [ -x "$FFMPEG_BIN_PATH" ] && [ -x "$FFPROBE_BIN_PATH" ]; then
    if "$FFMPEG_BIN_PATH" -hide_banner -version >/dev/null 2>&1 \
      && "$FFPROBE_BIN_PATH" -hide_banner -version >/dev/null 2>&1; then
      log "ffmpeg bundle already installed; skipping download"
      FFMPEG_BUNDLE_INSTALLED=1
      return 0
    fi
    warn "existing ffmpeg bundle is not runnable; reinstalling"
    rm -f "$FFMPEG_BIN_PATH" "$FFPROBE_BIN_PATH" >/dev/null 2>&1 || true
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] install ffmpeg bundle -> ${FFMPEG_BIN_PATH}, ${FFPROBE_BIN_PATH}"
    FFMPEG_BUNDLE_INSTALLED=1
    return 0
  fi

  local arch
  arch="$(normalize_ffmpeg_arch)"
  if [ -z "$arch" ]; then
    warn "Unsupported arch for ffmpeg bundle: ${ARCH:-unknown}"
    return 1
  fi

  local sha_cmd
  sha_cmd="$(resolve_sha256_cmd)"
  if [ -z "$sha_cmd" ]; then
    warn "Missing sha256sum (or shasum) for ffmpeg bundle verification"
    return 1
  fi

  local line
  line="$(ffmpeg_bundle_url_sha "$arch" "$FFMPEG_BUNDLE_PROFILE")"
  if [ -z "$line" ]; then
    warn "No ffmpeg bundle mapping for ${arch}/${FFMPEG_BUNDLE_PROFILE}"
    return 1
  fi
  local url sha
  IFS='|' read -r url sha <<<"$line"
  if [ -z "$url" ] || [ -z "$sha" ]; then
    warn "Invalid ffmpeg bundle mapping for ${arch}/${FFMPEG_BUNDLE_PROFILE}"
    return 1
  fi

  local work
  work="$(mktemp -d -t stream-ffmpeg.XXXXXX)"
  local archive="$work/ffmpeg.tar.xz"
  local extract="$work/extract"
  mkdir -p "$extract"

  log "Downloading ffmpeg bundle: $url"
  if ! curl_download "$url" "$archive"; then
    warn "ffmpeg bundle download failed: $url"
    rm -rf "$work" >/dev/null 2>&1 || true
    return 1
  fi

  if ! echo "${sha}  ${archive}" | $sha_cmd -c - >/dev/null; then
    warn "ffmpeg bundle checksum mismatch"
    rm -rf "$work" >/dev/null 2>&1 || true
    return 1
  fi

  if ! tar -xJf "$archive" -C "$extract"; then
    warn "ffmpeg bundle extract failed"
    rm -rf "$work" >/dev/null 2>&1 || true
    return 1
  fi

  local ffmpeg_src ffprobe_src
  ffmpeg_src="$(find "$extract" -type f -name ffmpeg -perm -111 | head -n 1 || true)"
  ffprobe_src="$(find "$extract" -type f -name ffprobe -perm -111 | head -n 1 || true)"
  if [ -z "$ffmpeg_src" ] || [ -z "$ffprobe_src" ]; then
    warn "ffmpeg/ffprobe binaries not found in downloaded bundle"
    rm -rf "$work" >/dev/null 2>&1 || true
    return 1
  fi

  if ! run install -m 755 "$ffmpeg_src" "$FFMPEG_BIN_PATH"; then
    warn "failed to install ffmpeg bundle binary"
    rm -rf "$work" >/dev/null 2>&1 || true
    return 1
  fi
  if ! run install -m 755 "$ffprobe_src" "$FFPROBE_BIN_PATH"; then
    warn "failed to install ffmpeg bundle ffprobe binary"
    rm -rf "$work" >/dev/null 2>&1 || true
    return 1
  fi

  # На старых дистрибутивах бинарник из bundle может не запуститься
  # (glibc/libstdc++ mismatch). Проверяем сразу и даём install_deps_* сделать fallback.
  if ! "$FFMPEG_BIN_PATH" -hide_banner -version >/dev/null 2>&1; then
    warn "ffmpeg bundle installed but not runnable on this system; falling back to system ffmpeg"
    rm -f "$FFMPEG_BIN_PATH" "$FFPROBE_BIN_PATH" >/dev/null 2>&1 || true
    rm -rf "$work" >/dev/null 2>&1 || true
    return 1
  fi
  if ! "$FFPROBE_BIN_PATH" -hide_banner -version >/dev/null 2>&1; then
    warn "ffprobe bundle installed but not runnable on this system; falling back to system ffmpeg"
    rm -f "$FFMPEG_BIN_PATH" "$FFPROBE_BIN_PATH" >/dev/null 2>&1 || true
    rm -rf "$work" >/dev/null 2>&1 || true
    return 1
  fi

  FFMPEG_BUNDLE_INSTALLED=1
  rm -rf "$work" >/dev/null 2>&1 || true
  return 0
}

resolve_ffmpeg_mode() {
  if [ "$INSTALL_FFMPEG" -ne 1 ]; then
    printf '%s' "none"
    return 0
  fi
  local mode="${FFMPEG_MODE:-auto}"
  if [ "$mode" = "auto" ]; then
    if [ "$PKG_MGR" = "apt" ]; then
      mode="system"
    else
      mode="bundle"
    fi
  fi
  printf '%s' "$mode"
  return 0
}

apt_has_candidate() {
  # apt-cache show может возвращать 0 даже если пакета нет. Используем policy.
  # Возвращает 0, если у пакета есть Candidate (не "(none)").
  local pkg="$1"
  if ! command -v apt-cache >/dev/null 2>&1; then
    return 1
  fi
  local cand
  cand="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/{print $2}' | head -n1)"
  [ -n "$cand" ] && [ "$cand" != "(none)" ]
}

ensure_dirs() {
  run mkdir -p "$DATA_DIR"
  run chmod 755 "$DATA_DIR"
}

install_deps_debian() {
  local ffmpeg_mode
  ffmpeg_mode="$(resolve_ffmpeg_mode)"

  run apt-get update -y
  # Ubuntu keeps ffmpeg and some optional deps in "universe". Enable it on-demand.
  if [ "$ffmpeg_mode" = "system" ] && [ "${OS_ID:-}" = "ubuntu" ]; then
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
    if [ "$ffmpeg_mode" = "bundle" ]; then
      if ! install_ffmpeg_bundle; then
        die "ffmpeg bundle install failed (re-run with --ffmpeg-system)"
      fi
    else
      run apt-get install -y --no-install-recommends ffmpeg libavcodec-dev libavutil-dev
    fi
  fi

  # Optional deps (soft failure if missing in repo)
  run apt-get install -y --no-install-recommends libdvbcsa-dev libpq-dev || true
}

install_runtime_deps_debian() {
  local ffmpeg_mode
  ffmpeg_mode="$(resolve_ffmpeg_mode)"

  run apt-get update -y

  # Ubuntu: ensure universe for ffmpeg/libdvbcsa runtime packages.
  if [ "$ffmpeg_mode" = "system" ] && [ "${OS_ID:-}" = "ubuntu" ]; then
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
    if [ "$ffmpeg_mode" = "bundle" ]; then
      if ! install_ffmpeg_bundle; then
        die "ffmpeg bundle install failed (re-run with --ffmpeg-system)"
      fi
    else
      run apt-get install -y --no-install-recommends ffmpeg
    fi
  fi

  # Runtime libraries for dynamically linked builds.
  run apt-get install -y --no-install-recommends libsqlite3-0 libpq5 libdvbcsa1 || true
  # OpenSSL runtime package name depends on Ubuntu/Debian version.
  # Не пытаемся ставить несуществующие пакеты, чтобы не засорять вывод ошибками apt.
  if apt_has_candidate libssl3; then
    run apt-get install -y --no-install-recommends libssl3 || true
  elif apt_has_candidate libssl1.1; then
    run apt-get install -y --no-install-recommends libssl1.1 || true
  elif apt_has_candidate libssl1.0.0; then
    run apt-get install -y --no-install-recommends libssl1.0.0 || true
  fi
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
      if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] $PKG_MGR -y install https://download1.rpmfusion.org/free/el/rpmfusion-free-release-${rel}.noarch.rpm"
        return 0
      fi
      if ! "$PKG_MGR" -y install "https://download1.rpmfusion.org/free/el/rpmfusion-free-release-${rel}.noarch.rpm"; then
        warn "rpmfusion HTTPS install failed; trying HTTP"
        "$PKG_MGR" -y install "http://download1.rpmfusion.org/free/el/rpmfusion-free-release-${rel}.noarch.rpm" || true
      fi
    fi
  fi
}

install_deps_rhel() {
  local ffmpeg_mode
  ffmpeg_mode="$(resolve_ffmpeg_mode)"

  enable_epel_rhel
  run "$PKG_MGR" -y install ca-certificates curl tar gzip xz git gcc make pkgconfig \
    openssl-devel sqlite-devel

  # Optional deps: dvbcsa, postgres
  run "$PKG_MGR" -y install libdvbcsa-devel postgresql-devel || true

  if [ "$INSTALL_FFMPEG" -eq 1 ]; then
    if [ "$ffmpeg_mode" = "bundle" ]; then
      if ! install_ffmpeg_bundle; then
        if [ "${FFMPEG_MODE:-auto}" = "auto" ]; then
          warn "ffmpeg bundle install failed; falling back to system packages"
          if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
            log "ffmpeg already installed; skipping package install"
          else
            enable_rpmfusion
            run "$PKG_MGR" -y install ffmpeg ffmpeg-devel || true
          fi
        else
          die "ffmpeg bundle install failed"
        fi
      fi
    else
      if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
        log "ffmpeg already installed; skipping package install"
      else
        enable_rpmfusion
        run "$PKG_MGR" -y install ffmpeg ffmpeg-devel || true
      fi
    fi
  fi
}

install_runtime_deps_rhel() {
  local ffmpeg_mode
  ffmpeg_mode="$(resolve_ffmpeg_mode)"

  enable_epel_rhel
  run "$PKG_MGR" -y install ca-certificates curl sqlite-libs openssl-libs || true
  run "$PKG_MGR" -y install libdvbcsa postgresql-libs || true
  if [ "$INSTALL_FFMPEG" -eq 1 ]; then
    if [ "$ffmpeg_mode" = "bundle" ]; then
      if ! install_ffmpeg_bundle; then
        if [ "${FFMPEG_MODE:-auto}" = "auto" ]; then
          warn "ffmpeg bundle install failed; falling back to system packages"
          if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
            log "ffmpeg already installed; skipping package install"
          else
            enable_rpmfusion
            run "$PKG_MGR" -y install ffmpeg || true
          fi
        else
          die "ffmpeg bundle install failed"
        fi
      fi
    else
      if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1; then
        log "ffmpeg already installed; skipping package install"
      else
        enable_rpmfusion
        run "$PKG_MGR" -y install ffmpeg || true
      fi
    fi
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
    printf '%s/stream-linux-%s' "$BASE_URL" "$ARCH"
    return 0
  fi

  # Default source tarball name guesses.
  printf '%s/stream-src.tar.gz' "$BASE_URL"
}

source_url_candidates() {
  local urls=()
  local rel
  rel="$(printf '%s' "${STREAM_RELEASE:-}" | tr -cd '0-9A-Za-z._-')"
  if [ -n "$rel" ]; then
    urls+=("${BASE_URL}/stream-src-${rel}.tar.gz")
  fi
  urls+=("${BASE_URL}/stream-src.tar.gz")
  printf '%s\n' "${urls[@]}"
}

binary_url_candidates() {
  # Пытаемся подобрать "наиболее совместимый" артефакт.
  # Правило: сначала дистро-специфичный, затем generic.
  #
  # Это важно для старых Ubuntu/Debian, где:
  # - другой glibc
  # - другие версии libssl/libcrypto
  # - нет libavcodec.so.58 и т.п.
  local urls=()

  # Ubuntu / Debian
  if [ -n "${OS_ID:-}" ] && [ -n "${OS_VER:-}" ]; then
    case "${OS_ID:-}" in
      ubuntu|debian)
        urls+=("${BASE_URL}/stream-linux-${OS_ID}${OS_VER}-${ARCH}")
        urls+=("${BASE_URL}/stream-linux-${OS_ID}${OS_VER%%.*}-${ARCH}")
        ;;
    esac
  fi

  # Generic fallback (может быть несовместим на старых дистрибутивах).
  local use_generic=1
  if [ "$ALLOW_GENERIC" -ne 1 ] && [ -n "${OS_ID:-}" ] && [ -n "${OS_VER:-}" ]; then
    local major="${OS_VER%%.*}"
    case "${OS_ID:-}" in
      ubuntu)
        [ "$major" -lt 20 ] && use_generic=0
        ;;
      debian)
        [ "$major" -lt 11 ] && use_generic=0
        ;;
      centos|rhel|rocky|almalinux)
        [ "$major" -lt 8 ] && use_generic=0
        ;;
    esac
  fi

  if [ "$use_generic" -eq 1 ]; then
    urls+=("${BASE_URL}/stream-linux-${ARCH}")
  fi

  printf '%s\n' "${urls[@]}"
}

fetch_artifact() {
  local url="$1"
  local out="$2"
  if curl_download "$url" "$out"; then
    return 0
  fi
  # На старых системах часто нет актуальных CA. Для stream.centv.ru попробуем HTTP.
  if echo "$url" | grep -q "^https://stream.centv.ru/"; then
    local url_http="${url/https:\/\//http://}"
    warn "HTTPS download failed; trying HTTP: $url_http"
    curl_download "$url_http" "$out"
    return $?
  fi
  return 1
}

build_from_source() {
  run rm -rf "$WORKDIR"
  run mkdir -p "$WORKDIR"
  local src_root=""

  if [ -n "$URL" ] || [ -n "$ARTIFACT" ]; then
    local url
    url=$(resolve_url)
    log "Downloading sources: $url"

    local archive="$WORKDIR/stream-src.tar.gz"
    fetch_artifact "$url" "$archive"

    if ! tar -tf "$archive" >/dev/null 2>&1; then
      die "Downloaded sources are not a valid tar archive (maybe an HTML error page): $url"
    fi

    run tar -xf "$archive" -C "$WORKDIR"
    src_root=$(find "$WORKDIR" -maxdepth 3 -name configure.sh -print -quit | xargs -r dirname)
    if [ -z "$src_root" ]; then
      die "Could not find configure.sh in extracted sources. Provide --url explicitly."
    fi
  else
    # Prefer versioned source tarball from the artifact host, then fallback.
    # Fall back to git clone if the tarball doesn't exist or can't be downloaded.
    local url=""
    local fetched=0
    local archive="$WORKDIR/stream-src.tar.gz"

    while IFS= read -r url; do
      [ -n "$url" ] || continue
      log "Downloading sources: $url"
      if fetch_artifact "$url" "$archive"; then
        fetched=1
        if tar -tf "$archive" >/dev/null 2>&1; then
          run tar -xf "$archive" -C "$WORKDIR"
          src_root=$(find "$WORKDIR" -maxdepth 3 -name configure.sh -print -quit | xargs -r dirname)
          if [ -z "$src_root" ]; then
            warn "Could not find configure.sh in extracted sources ($url). Trying next source candidate."
            run rm -rf "$WORKDIR"/*
            continue
          fi
          break
        else
          warn "Source tarball is not a valid archive (maybe an HTML error page): $url"
        fi
      else
        warn "Source tarball download failed: $url"
      fi
    done < <(source_url_candidates)

    if [ "$fetched" -eq 0 ]; then
      warn "Source tarball download failed for all candidates. Falling back to git clone."
    fi

    if [ -z "$src_root" ]; then
      log "Cloning sources: $GIT_URL (ref: $GIT_REF)"
      run mkdir -p "$WORKDIR"
      run rm -rf "$WORKDIR/src"
      (cd "$WORKDIR" && run git clone --depth 1 --branch "$GIT_REF" "$GIT_URL" src)
      src_root="$WORKDIR/src"
      if [ ! -f "$src_root/configure.sh" ]; then
        die "Could not find configure.sh in cloned sources. Try --git-ref or --url."
      fi
    fi
  fi

  log "Building from: $src_root"
  # Стараемся собирать максимально полный функционал (softcam/descramble),
  # даже если в системе нет libdvbcsa-dev.
  local make_jobs
  make_jobs="$(detect_make_jobs)"
  (cd "$src_root" && ./configure.sh --with-libdvbcsa && make -j"$make_jobs")

  if [ ! -x "$src_root/stream" ]; then
    die "Build succeeded but binary 'stream' not found."
  fi

  run install -m 755 "$src_root/stream" "$BIN_PATH"
  install_runtime_scripts_from_source "$src_root"

  if [ "$INSTALL_WEB" -eq 1 ]; then
    run mkdir -p /usr/local/share/stream/web
    run cp -r "$src_root/web"/* /usr/local/share/stream/web/
  fi

  run rm -rf "$WORKDIR"
}

check_runtime_binary_usable() {
  # Проверяем, что бинарник можно запустить в этой системе:
  # - нет missing .so
  # - нет ошибок вида "version `GLIBC_2.xx' not found"
  # Возвращает 0 если ок. Если нет — возвращает 1 и печатает причину в stdout.
  local f="$1"
  if ! command -v ldd >/dev/null 2>&1; then
    return 0
  fi

  local out
  if ! out="$(ldd "$f" 2>&1)"; then
    # Обычно сюда попадают несовместимости glibc/loader.
    printf '%s' "$out"
    return 1
  fi
  if echo "$out" | grep -qi "not a dynamic executable"; then
    return 0
  fi

  local missing
  missing="$(echo "$out" | awk '/not found/{print $1}' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [ -n "$missing" ]; then
    printf 'missing libs: %s' "$missing"
    return 1
  fi

  return 0
}

install_binary() {
  run mkdir -p "$(dirname "$BIN_PATH")"

  STREAM_TMP_BIN="$(mktemp -t stream-bin.XXXXXX)"
  local tmp="$STREAM_TMP_BIN"

  # If user provided an explicit URL or artifact name, use it as-is.
  if [ -n "$URL" ] || [ -n "$ARTIFACT" ]; then
    local url
    url=$(resolve_url)
    log "Downloading binary: $url"
    fetch_artifact "$url" "$tmp"
    if ! is_elf_binary "$tmp"; then
      die "Downloaded file is not a Linux ELF binary (maybe an HTML error page): $url"
    fi
    local reason=""
    if ! reason="$(check_runtime_binary_usable "$tmp")"; then
      die "Downloaded binary is not usable on this system ($reason). Install required packages or use --mode source."
    fi
    run install -m 755 "$tmp" "$BIN_PATH"
    STREAM_TMP_BIN=""
    return 0
  fi

  local last_err=""
  local url=""
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    log "Downloading binary: $url"
    if ! fetch_artifact "$url" "$tmp"; then
      warn "Download failed: $url"
      last_err="download failed"
      continue
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      log "[dry-run] would install binary to: $BIN_PATH"
      return 0
    fi
    if ! is_elf_binary "$tmp"; then
      warn "Downloaded file is not a Linux ELF binary (maybe an HTML error page): $url"
      last_err="not an ELF binary"
      continue
    fi
    local reason=""
    if ! reason="$(check_runtime_binary_usable "$tmp")"; then
      warn "Downloaded binary is not usable on this system ($reason): $url"
      last_err="$reason"
      continue
    fi
    run install -m 755 "$tmp" "$BIN_PATH"
    STREAM_TMP_BIN=""
    return 0
  done < <(binary_url_candidates)

  die "Failed to download a usable prebuilt binary (last error: ${last_err:-unknown}). Try --mode source, or provide --url/--artifact explicitly."
}

check_runtime_libs() {
  if ! command -v ldd >/dev/null 2>&1; then
    return 0
  fi

  # Static binaries print "not a dynamic executable" - that's OK.
  local out
  out="$(ldd "$BIN_PATH" 2>&1 || true)"
  if echo "$out" | grep -qi "not a dynamic executable"; then
    return 0
  fi

  local missing
  missing="$(echo "$out" | awk '/not found/{print $1}' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [ -n "$missing" ]; then
    die "Missing runtime libraries for $BIN_PATH: $missing. Install the required packages or use --mode source."
  fi
}

verify_transcode() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] verify transcode (skipped)"
    return 0
  fi

  log "Verifying transcode..."

  local out=""
  local status=0
  set +e
  out="$("$BIN_PATH" --help 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    die "Failed to run ${BIN_PATH} --help (${status}). Output: ${out}"
  fi
  if ! echo "$out" | grep -q "Build: FULL"; then
    die "Installed build is not FULL (no transcode). Reinstall FULL build or rebuild from sources without --without-transcode."
  fi

  local ffmpeg_bin=""
  local ffprobe_bin=""
  local ffmpeg_candidates=()
  local ffprobe_candidates=()
  local c=""

  [ -x "$FFMPEG_BIN_PATH" ] && ffmpeg_candidates+=("$FFMPEG_BIN_PATH")
  command -v ffmpeg >/dev/null 2>&1 && ffmpeg_candidates+=("ffmpeg")
  for c in "${ffmpeg_candidates[@]}"; do
    if "$c" -hide_banner -version >/dev/null 2>&1; then
      ffmpeg_bin="$c"
      break
    fi
  done

  [ -x "$FFPROBE_BIN_PATH" ] && ffprobe_candidates+=("$FFPROBE_BIN_PATH")
  command -v ffprobe >/dev/null 2>&1 && ffprobe_candidates+=("ffprobe")
  for c in "${ffprobe_candidates[@]}"; do
    if "$c" -hide_banner -version >/dev/null 2>&1; then
      ffprobe_bin="$c"
      break
    fi
  done

  if [ -z "$ffmpeg_bin" ] || [ -z "$ffprobe_bin" ]; then
    die "ffmpeg/ffprobe not runnable. Re-run installer with --ffmpeg-system or --no-verify-transcode."
  fi

  log "Transcode verification: OK"
}

write_systemd_unit() {
  # В контейнерах (Docker) и некоторых минимальных окружениях systemd не работает.
  # Установку бинарника и конфигов делаем всё равно, а сервис пропускаем.
  if ! command -v systemctl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; then
    warn "systemd not detected; skipping unit install"
    return 0
  fi
  local unit_path="/etc/systemd/system/stream@.service"
  if [ ! -f "$unit_path" ]; then
    cat > "$unit_path" <<UNIT
[Unit]
Description=Stream server (%i)
After=network.target

[Service]
Type=simple
Environment=STREAM_PORT=8816
EnvironmentFile=-${DATA_DIR}/%i.env
WorkingDirectory=${DATA_DIR}
ExecStart=${BIN_PATH} -c ${DATA_DIR}/%i.json -p \$STREAM_PORT
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
  else
    # Migration for older installer templates that used shell parameter expansion
    # in ExecStart (${STREAM_PORT:-8816}) which systemd does not evaluate.
    if grep -q '\${STREAM_PORT:-8816}' "$unit_path"; then
      run sed -i 's#\${STREAM_PORT:-8816}#$STREAM_PORT#g' "$unit_path"
      if ! grep -q '^Environment=STREAM_PORT=' "$unit_path"; then
        run sed -i '/^\[Service\]/a Environment=STREAM_PORT=8816' "$unit_path"
      fi
      log "Updated incompatible systemd template: $unit_path"
    fi
  fi
  run systemctl daemon-reload
}

write_instance_files() {
  if [ -z "$INSTANCE_NAME" ]; then
    return 0
  fi

  local cfg="$DATA_DIR/${INSTANCE_NAME}.json"
  local env="$DATA_DIR/${INSTANCE_NAME}.env"

  if [ ! -f "$cfg" ]; then
    printf '{}' > "$cfg"
  fi

  if [ -z "$PORT" ]; then
    PORT="8816"
  fi

  {
    printf 'STREAM_PORT=%s\n' "$PORT"
    if [ "$INSTALL_WEB" -eq 1 ]; then
      printf 'STREAM_WEB_DIR=%s\n' "/usr/local/share/stream/web"
    fi
    if [ "$FFMPEG_BUNDLE_INSTALLED" -eq 1 ]; then
      # Prefer the bundled tools for this instance only.
      printf 'STREAM_FFMPEG_PATH=%s\n' "$FFMPEG_BIN_PATH"
      printf 'STREAM_FFPROBE_PATH=%s\n' "$FFPROBE_BIN_PATH"
      # Legacy env keys (kept for backwards compatibility).
      printf 'ASTRA_FFMPEG_PATH=%s\n' "$FFMPEG_BIN_PATH"
      printf 'ASTRA_FFPROBE_PATH=%s\n' "$FFPROBE_BIN_PATH"
    fi
  } > "$env"
}

maybe_enable_service() {
  if [ "$ENABLE_SERVICE" -ne 1 ] || [ -z "$INSTANCE_NAME" ]; then
    return 0
  fi
  if ! command -v systemctl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; then
    warn "systemd not detected; skipping enable/start"
    return 0
  fi
  run systemctl enable --now "stream@${INSTANCE_NAME}.service"
}

main() {
  if [ "$MODE" != "source" ] && [ "$MODE" != "binary" ]; then
    die "Unsupported --mode: $MODE (use source or binary)"
  fi

  if [ "$RUNTIME_ONLY" -eq 1 ] && [ "$MODE" != "binary" ]; then
    die "--runtime-only requires --mode binary"
  fi

  log "Stream installer ${INSTALLER_VERSION} (release ${STREAM_RELEASE})"

  # Важно: НЕ переключаемся автоматически на сборку из исходников.
  # Пользователь должен явно выбрать --mode source, если бинарник не подходит.

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
    check_runtime_libs
  fi

  ensure_stream_path_compat

  if [ "$INSTALL_WEB" -eq 0 ]; then
    log "Web assets not installed. UI will be served from embedded bundle."
  fi

  write_systemd_unit
  write_instance_files
  maybe_enable_service

  if [ "$VERIFY_TRANSCODE" -eq 1 ]; then
    verify_transcode
  fi

  log "Done. Binary: $BIN_PATH"
  log "Config root: $DATA_DIR"
}

main
