#!/usr/bin/env bash
set -euo pipefail

# Astral runtime deps installer for Debian/Ubuntu.
# - Checks missing shared libraries via ldd (binary runtime deps).
# - Optionally installs external tools used by features (ffmpeg/ffprobe).
# - Handles Ubuntu 22.04+ case where libssl1.1 is not in apt repos.

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

usage() {
  cat <<'EOF'
Usage:
  sudo ./install.sh [--bin /path/to/astral] [--no-ffmpeg] [--dry-run]

Options:
  --bin PATH       Path to Astral/Astra binary to validate with ldd.
  --no-ffmpeg      Do not install ffmpeg/ffprobe.
  --dry-run        Print actions without installing anything.
  -h, --help       Show this help.

Notes:
  - This script targets Debian/Ubuntu with apt.
  - If the binary requires libssl.so.1.1 on Ubuntu 22.04+, the script can
    download and install a compatible libssl1.1 .deb from official Ubuntu
    archives (security.ubuntu.com / ports.ubuntu.com).
EOF
}

BIN_PATH=""
INSTALL_FFMPEG=1
DRY_RUN=0

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
    --bin)
      BIN_PATH="${2:-}"
      shift 2
      ;;
    --no-ffmpeg)
      INSTALL_FFMPEG=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: ${1:-}"
      ;;
  esac
done

if [ "$(uname -s)" != "Linux" ]; then
  die "This installer must be run on Linux (Debian/Ubuntu)."
fi

if [ "$(id -u)" -ne 0 ]; then
  die "Please run as root (sudo)."
fi

if ! command -v apt-get >/dev/null 2>&1; then
  die "apt-get not found. This installer supports Debian/Ubuntu only."
fi

if [ -z "$BIN_PATH" ]; then
  for c in ./astral ./astra ./astra-linux-ubuntu22.04 /opt/astra/astra /opt/astral/astral; do
    if [ -x "$c" ]; then
      BIN_PATH="$c"
      break
    fi
  done
fi

if [ -z "$BIN_PATH" ]; then
  warn "Binary path not provided and no default candidates found."
  warn "You can still use this script to install ffmpeg, but ldd checks will be skipped."
else
  if [ ! -x "$BIN_PATH" ]; then
    die "Binary is not executable: $BIN_PATH"
  fi
fi

. /etc/os-release || true
OS_ID="${ID:-unknown}"
OS_LIKE="${ID_LIKE:-}"
OS_VER="${VERSION_ID:-}"
OS_CODENAME="${VERSION_CODENAME:-}"

if [ "$OS_ID" != "ubuntu" ] && [ "$OS_ID" != "debian" ] && ! printf '%s' "$OS_LIKE" | grep -qi debian; then
  warn "Detected OS: id=$OS_ID version=$OS_VER codename=$OS_CODENAME (not Debian/Ubuntu)."
  warn "Proceeding anyway, but package names and repos may differ."
fi

ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
if [ -z "$ARCH" ]; then
  ARCH="$(uname -m)"
fi

ensure_base_tools() {
  # curl is used for libssl1.1 fallback download.
  run apt-get update -y
  run apt-get install -y --no-install-recommends ca-certificates curl
}

unique_words() {
  # Prints unique tokens preserving first occurrence order.
  # shellcheck disable=SC2048
  awk '
    {
      for (i=1; i<=NF; i++) {
        if (!seen[$i]++) out[++n]=$i
      }
    }
    END {
      for (i=1; i<=n; i++) print out[i]
    }
  '
}

missing_libs_ldd() {
  ldd "$BIN_PATH" 2>/dev/null | awk '/=> not found/ {print $1}' | sort -u || true
}

is_pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

apt_install_pkgs() {
  if [ "$#" -eq 0 ]; then
    return 0
  fi
  run apt-get install -y --no-install-recommends "$@"
}

install_libssl11_fallback() {
  if is_pkg_installed libssl1.1; then
    return 0
  fi

log "libssl.so.1.1 is required but libssl1.1 is not available via apt on some Ubuntu releases (22.04+)."
  warn "Installing legacy libssl1.1 from official Ubuntu archives. Prefer using a build linked to OpenSSL 3 (libssl3) for long-term support."

  # Try apt first (works on older Ubuntu/Debian).
  if apt-cache show libssl1.1 >/dev/null 2>&1; then
    apt_install_pkgs libssl1.1
    return 0
  fi

  # Determine archive base URL by architecture.
  local base_url=""
  case "$ARCH" in
    amd64|i386)
      base_url="https://security.ubuntu.com/ubuntu/pool/main/o/openssl"
      ;;
    *)
      base_url="https://ports.ubuntu.com/ubuntu-ports/pool/main/o/openssl"
      ;;
  esac

  # Pick the newest deb for our arch by modified time.
  local listing=""
  listing="$(curl -fsSL "${base_url}/?C=M;O=D")" || die "Failed to fetch Ubuntu archive listing for libssl1.1."

  local deb=""
  deb="$(printf '%s' "$listing" | grep -o "libssl1\\.1_[^\"]*_${ARCH}\\.deb" | head -n 1 || true)"
  if [ -z "$deb" ]; then
    die "Could not find libssl1.1 .deb for arch=$ARCH at $base_url"
  fi

  local tmp_dir=""
  tmp_dir="$(mktemp -d)"
  local deb_path="$tmp_dir/$deb"

  log "Downloading: $deb"
  run curl -fsSL -o "$deb_path" "${base_url}/${deb}"

  log "Installing: $deb"
  # dpkg can fail with missing deps; apt -f fixes them.
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] dpkg -i $deb_path"
  else
    if ! dpkg -i "$deb_path" >/dev/null 2>&1; then
      run apt-get -f install -y
    fi
  fi

  rm -rf "$tmp_dir"
}

main() {
  ensure_base_tools

  # External tools used by runtime features (transcode bridge, probes, etc).
  if [ "$INSTALL_FFMPEG" -eq 1 ]; then
    if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
      apt_install_pkgs ffmpeg
    fi
  fi

  if [ -z "$BIN_PATH" ]; then
    log "No binary selected; skipping ldd checks."
    return 0
  fi

  if ! command -v ldd >/dev/null 2>&1; then
    die "ldd not found. Cannot validate binary shared library dependencies."
  fi

  local missing_libs=""
  missing_libs="$(missing_libs_ldd)"

  local needs_ssl11=0
  local pkgs=""

  # Map missing .so to apt packages.
  # Keep this list small and focused; unknown libs are reported.
  local lib
  while IFS= read -r lib; do
    [ -z "$lib" ] && continue
    case "$lib" in
      libssl.so.1.1|libcrypto.so.1.1)
        needs_ssl11=1
        ;;
      libdvbcsa.so.1)
        pkgs="$pkgs libdvbcsa1"
        ;;
      libpq.so.5)
        pkgs="$pkgs libpq5"
        ;;
      libssl.so.3|libcrypto.so.3)
        pkgs="$pkgs libssl3"
        ;;
      *)
        warn "Missing shared library (no mapping): $lib"
        ;;
    esac
  done <<<"$missing_libs"

  # Install mapped packages.
  pkgs="$(printf '%s\n' "$pkgs" | unique_words | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [ -n "$pkgs" ]; then
    # shellcheck disable=SC2086
    apt_install_pkgs $pkgs
  fi

  if [ "$needs_ssl11" -eq 1 ]; then
    install_libssl11_fallback
  fi

  # Final verification.
  local still_missing=""
  still_missing="$(missing_libs_ldd)"
  if [ -n "$still_missing" ]; then
    warn "Some libraries are still missing for: $BIN_PATH"
    printf '%s\n' "$still_missing" >&2
    die "Dependency installation incomplete."
  fi

  log "OK: runtime dependencies look satisfied for $BIN_PATH"
}

main

