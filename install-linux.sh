#!/usr/bin/env bash
# Linux-only installer: replace official Tailscale with Amnezia-WG-enabled binaries
# Reliable, minimal dependencies. Requires systemd for service management.

set -euo pipefail

REPO="LiuTangLei/tailscale"
VERSION="latest"  # Always use latest release

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_err()   { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
  if [[ $EUID -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi
}

# Detect architecture and set paths
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) arch="amd64";;
  aarch64|arm64) arch="arm64";;
  *) log_err "Unsupported architecture: $arch"; exit 1;;

esac
platform="linux-$arch"
INSTALL_DIR="/usr/local/bin"

log_info "Platform: $platform"
log_info "Install dir: $INSTALL_DIR"

# Determine the actual target paths
resolve_install_targets() {
  TS_PATH=$(command -v tailscale 2>/dev/null || true)
  TSD_PATH=$(command -v tailscaled 2>/dev/null || true)
  [[ -z "${TS_PATH:-}" ]] && TS_PATH="$INSTALL_DIR/tailscale"
  [[ -z "${TSD_PATH:-}" ]] && TSD_PATH="$INSTALL_DIR/tailscaled"

  if command -v systemctl >/dev/null 2>&1; then
    local exec_start
    exec_start=$(systemctl show -p ExecStart tailscaled 2>/dev/null | sed -E 's/^ExecStart=\??([^ ]+).*/\1/' || true)
    if [[ -n "$exec_start" && -x "$exec_start" ]]; then
      TSD_PATH="$exec_start"
    fi
  fi
  export TS_PATH TSD_PATH
  log_info "tailscale -> $TS_PATH"
  log_info "tailscaled -> $TSD_PATH"
}

stop_service() {
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet tailscaled 2>/dev/null; then
      log_info "Stopping tailscaled service..."
      $SUDO systemctl stop tailscaled || true
    fi
  else
    log_warn "systemd not found; ensure tailscaled is stopped manually"
  fi
}

start_service() {
  if command -v systemctl >/dev/null 2>&1; then
    log_info "Starting tailscaled service..."
    $SUDO systemctl start tailscaled || true
    $SUDO systemctl enable tailscaled || true
  fi
}

install_official_if_missing() {
  if ! command -v tailscale >/dev/null 2>&1; then
    log_warn "Tailscale not found. Installing official version first..."
    curl -fsSL https://tailscale.com/install.sh | sh
    log_ok "Official Tailscale installed"
  else
    log_info "Tailscale found; will replace binaries"
  fi
}

install_binaries() {
  if [[ "$VERSION" == "latest" ]]; then
    log_info "Fetching latest release tag..."
    local latest_tag
    latest_tag=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^\"]+)".*/\1/')
    [[ -z "$latest_tag" ]] && { log_err "Failed to resolve latest release"; exit 1; }
    VERSION="$latest_tag"
    log_info "Latest version: $VERSION"
  fi

  local base_url="https://github.com/$REPO/releases/download/$VERSION"
  local tailscale_binary="tailscale-$platform"
  local tailscaled_binary="tailscaled-$platform"

  local tmp
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  pushd "$tmp" >/dev/null

  log_info "Downloading $tailscale_binary"
  curl -fL "$base_url/$tailscale_binary" -o tailscale
  log_info "Downloading $tailscaled_binary"
  curl -fL "$base_url/$tailscaled_binary" -o tailscaled
  chmod +x tailscale tailscaled

  stop_service
  resolve_install_targets

  $SUDO mkdir -p "$(dirname "$TS_PATH")" "$(dirname "$TSD_PATH")"
  log_info "Installing to $TS_PATH"
  $SUDO install -m 0755 tailscale "$TS_PATH"
  log_info "Installing to $TSD_PATH"
  $SUDO install -m 0755 tailscaled "$TSD_PATH"

  popd >/dev/null
  rm -rf "$tmp"
  trap - EXIT
  log_ok "Binaries installed"
}

usage() {
  echo ""
  echo "Quick Start:"; echo "  tailscale up"; echo ""
  echo "Amnezia-WG commands:"; echo "  tailscale amnezia-wg set"; echo "  tailscale amnezia-wg get"; echo "  tailscale amnezia-wg reset"; echo ""
}

main() {
  echo "🔧 Linux Installer (Amnezia-WG 1.5)"
  check_root
  install_official_if_missing
  install_binaries
  start_service
  usage
}

main "$@"
