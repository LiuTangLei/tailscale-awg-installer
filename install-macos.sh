#!/usr/bin/env bash
# macOS-only installer: replace official Tailscale with Amnezia-WG-enabled binaries
# Reliable, minimal dependencies. Supports Intel & Apple Silicon, Homebrew paths.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash
#   # With mirror:
#   curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --mirror https://your-mirror-site.com

set -euo pipefail

REPO="LiuTangLei/tailscale"
VERSION="latest"
MIRROR_PREFIX="" # GitHub mirror prefix

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
log() { echo -e "$1"; }
info() { log "${BLUE}[INFO]${NC} $1"; }
ok() { log "${GREEN}[SUCCESS]${NC} $1"; }
warn() { log "${YELLOW}[WARNING]${NC} $1"; }
err() { log "${RED}[ERROR]${NC} $1"; }

check_root() { if [[ ${EUID} -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi; }

arch="$(uname -m)"
case "${arch}" in
x86_64 | amd64) arch="amd64" ;;
arm64 | aarch64) arch="arm64" ;;
*)
	err "Unsupported arch: ${arch}"
	exit 1
	;;
esac
platform="darwin-${arch}"

# Determine install dir and current tailscaled path
INSTALL_DIR="/usr/local/bin"
if [[ -d "/opt/homebrew/bin" ]]; then INSTALL_DIR="/opt/homebrew/bin"; fi

resolve_install_targets() {
	TS_PATH=$(command -v tailscale 2>/dev/null || true)
	TSD_PATH=$(command -v tailscaled 2>/dev/null || true)
	[[ -z ${TS_PATH-} ]] && TS_PATH="${INSTALL_DIR}/tailscale"
	[[ -z ${TSD_PATH-} ]] && TSD_PATH="${INSTALL_DIR}/tailscaled"

	if [[ -f "/Library/LaunchDaemons/com.tailscale.tailscaled.plist" ]]; then
		local plist_path
		plist_path=$(grep -Eo '/[^ "<]*?/tailscaled' /Library/LaunchDaemons/com.tailscale.tailscaled.plist | head -n1 || true)
		if [[ -n ${plist_path} && -e ${plist_path} ]]; then TSD_PATH="${plist_path}"; fi
	fi
	export TS_PATH TSD_PATH
	info "tailscale -> ${TS_PATH}"
	info "tailscaled -> ${TSD_PATH}"
}

stop_service() {
	if launchctl list | grep -q com.tailscale.tailscaled 2>/dev/null; then
		info "Stopping tailscaled (launchctl unload)..."
		${SUDO} launchctl unload /Library/LaunchDaemons/com.tailscale.tailscaled.plist 2>/dev/null || true
	fi
}

start_service() {
	info "Starting tailscaled (launchctl load)..."
	${SUDO} launchctl load /Library/LaunchDaemons/com.tailscale.tailscaled.plist 2>/dev/null || true
}

install_official_if_missing() {
	if ! command -v tailscale >/dev/null 2>&1; then
		warn "Tailscale not found. Installing via Homebrew..."
		if command -v brew >/dev/null 2>&1; then
			brew install tailscale
		else
			err "Homebrew not found. Install from https://tailscale.com/download and rerun."
			exit 1
		fi
	else
		info "Tailscale found; will replace binaries"
	fi
}

install_binaries() {
	if [[ ${VERSION} == "latest" ]]; then
		info "Fetching latest release tag..."
		local api_url="https://api.github.com/repos/${REPO}/releases/latest"
		local tag
		tag=$(curl -fsSL "${api_url}" | grep '"tag_name"' | sed -E 's/.*"([^\"]+)".*/\1/')
		[[ -z ${tag} ]] && {
			err "Failed to resolve latest release"
			exit 1
		}
		VERSION="${tag}"
		info "Latest version: ${VERSION}"
	fi

	local base_url="https://github.com/${REPO}/releases/download/${VERSION}"
	if [[ -n ${MIRROR_PREFIX} ]]; then
		base_url="${MIRROR_PREFIX}/https://github.com/${REPO}/releases/download/${VERSION}"
		info "Using mirror for downloads: ${MIRROR_PREFIX}"
	fi

	local ts="tailscale-${platform}"
	local tsd="tailscaled-${platform}"
	local tmp
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	pushd "${tmp}" >/dev/null
	info "Downloading ${ts}"
	curl -fL "${base_url}/${ts}" -o tailscale
	info "Downloading ${tsd}"
	curl -fL "${base_url}/${tsd}" -o tailscaled
	chmod +x tailscale tailscaled

	stop_service
	resolve_install_targets

	${SUDO} mkdir -p "$(dirname "${TS_PATH}")" "$(dirname "${TSD_PATH}")"
	info "Installing to ${TS_PATH}"
	${SUDO} install -m 0755 tailscale "${TS_PATH}"
	info "Installing to ${TSD_PATH}"
	${SUDO} install -m 0755 tailscaled "${TSD_PATH}"

	popd >/dev/null
	rm -rf "${tmp}"
	trap - EXIT
	ok "Binaries installed"
}

usage() {
	echo ""
	echo "Quick Start:"
	echo "  tailscale up"
	echo "  tailscale amnezia-wg set"
	echo "  tailscale amnezia-wg get"
	echo "  tailscale amnezia-wg reset"
	echo ""
}

main() {
	echo "🔧 macOS Installer (Amnezia-WG 1.5)"

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--mirror)
			MIRROR_PREFIX="$2"
			info "Using mirror: ${MIRROR_PREFIX}"
			shift 2
			;;
		--help | -h)
			echo "Usage: $0 [--mirror PREFIX]"
			echo "  --mirror PREFIX  Use GitHub mirror with specified prefix"
			echo ""
			echo "Example with mirror:"
			echo "  curl -fsSL URL | bash -s -- --mirror https://your-mirror-site.com"
			exit 0
			;;
		*)
			warn "Unknown option: $1"
			shift
			;;
		esac
	done

	check_root
	install_official_if_missing
	install_binaries
	start_service
	usage
}

main "$@"
