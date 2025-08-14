#!/usr/bin/env bash
# Linux-only installer: replace official Tailscale with Amnezia-WG-enabled binaries
# Supports major Linux distributions (Debian/Ubuntu, RHEL/CentOS/Fedora, Arch Linux, SUSE/openSUSE)
# Includes package hold functionality to prevent official updates from overriding custom binaries
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash
#   # With mirror:
#   curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com

set -euo pipefail

REPO="LiuTangLei/tailscale"
VERSION="latest"   # Always use latest release
MIRROR_PREFIX=""   # GitHub mirror prefix
DISTRO=""          # Will be detected automatically
PACKAGE_MANAGER="" # Will be detected automatically

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect Linux distribution and package manager
detect_distro() {
	if [[ -f /etc/os-release ]]; then
		# shellcheck source=/dev/null
		source /etc/os-release
		case "${ID-}" in
		ubuntu | debian | linuxmint | elementary | zorin)
			DISTRO="debian"
			PACKAGE_MANAGER="apt"
			;;
		fedora | rhel | centos | rocky | almalinux | ol)
			DISTRO="redhat"
			PACKAGE_MANAGER="dnf"
			# For older RHEL/CentOS versions
			if ! command -v dnf >/dev/null 2>&1; then
				PACKAGE_MANAGER="yum"
			fi
			;;
		arch | manjaro | endeavouros)
			DISTRO="arch"
			PACKAGE_MANAGER="pacman"
			;;
		opensuse* | sles)
			DISTRO="suse"
			PACKAGE_MANAGER="zypper"
			;;
		alpine)
			DISTRO="alpine"
			PACKAGE_MANAGER="apk"
			;;
		*)
			log_warn "Unknown distribution: ${ID:-unknown}"
			DISTRO="unknown"
			PACKAGE_MANAGER=""
			;;
		esac
	else
		log_warn "Cannot detect distribution (/etc/os-release not found)"
		DISTRO="unknown"
		PACKAGE_MANAGER=""
	fi

	log_info "Detected distribution: ${DISTRO}"
	if [[ -n ${PACKAGE_MANAGER} ]]; then
		log_info "Package manager: ${PACKAGE_MANAGER}"
	fi
}

# Install official Tailscale using distribution-specific method
install_official_tailscale() {
	case "${DISTRO}" in
	debian)
		log_info "Installing Tailscale via APT repository..."
		curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | ${SUDO} tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
		curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.list | ${SUDO} tee /etc/apt/sources.list.d/tailscale.list
		${SUDO} apt update
		${SUDO} apt install -y tailscale
		;;
	redhat)
		log_info "Installing Tailscale via ${PACKAGE_MANAGER}..."
		${SUDO} "${PACKAGE_MANAGER}" config-manager --add-repo https://pkgs.tailscale.com/stable/rhel/tailscale.repo || {
			# Fallback for older versions
			curl -fsSL https://pkgs.tailscale.com/stable/rhel/repo.gpg | ${SUDO} tee /etc/pki/rpm-gpg/RPM-GPG-KEY-tailscale >/dev/null
			cat <<EOF | ${SUDO} tee /etc/yum.repos.d/tailscale.repo
[tailscale-stable]
name=Tailscale stable
baseurl=https://pkgs.tailscale.com/stable/rhel/\$basearch
enabled=1
type=rpm
repo_gpgcheck=1
gpgcheck=0
gpgkey=https://pkgs.tailscale.com/stable/rhel/repo.gpg
EOF
		}
		${SUDO} "${PACKAGE_MANAGER}" install -y tailscale
		;;
	arch)
		log_info "Installing Tailscale from AUR..."
		if command -v yay >/dev/null 2>&1; then
			yay -S --noconfirm tailscale
		elif command -v paru >/dev/null 2>&1; then
			paru -S --noconfirm tailscale
		else
			log_warn "No AUR helper found. Please install tailscale manually or install yay/paru"
			# Fallback: install from official script
			curl -fsSL https://tailscale.com/install.sh | sh
		fi
		;;
	suse)
		log_info "Installing Tailscale via zypper..."
		${SUDO} rpm --import https://pkgs.tailscale.com/stable/sles/repo.gpg
		${SUDO} zypper addrepo --gpgcheck --type rpm https://pkgs.tailscale.com/stable/sles/tailscale.repo
		${SUDO} zypper refresh
		${SUDO} zypper install -y tailscale
		;;
	alpine)
		log_info "Installing Tailscale via apk..."
		# Alpine Linux has Tailscale in community repository
		${SUDO} apk add --update tailscale
		;;
	*)
		log_warn "Unknown distribution, falling back to official install script..."
		curl -fsSL https://tailscale.com/install.sh | sh
		;;
	esac
}

# Hold package to prevent updates (distribution-specific)
hold_package() {
	log_info "Preventing Tailscale package updates..."
	case "${DISTRO}" in
	debian)
		${SUDO} apt-mark hold tailscale 2>/dev/null || true
		log_ok "Tailscale package held (apt-mark)"
		;;
	redhat)
		if command -v dnf >/dev/null 2>&1; then
			${SUDO} dnf versionlock add tailscale 2>/dev/null || true
			log_ok "Tailscale package locked (dnf versionlock)"
		elif command -v yum >/dev/null 2>&1; then
			${SUDO} yum versionlock add tailscale 2>/dev/null || {
				log_warn "yum-plugin-versionlock not installed. Please install it to prevent updates"
			}
		fi
		;;
	arch)
		# Add to IgnorePkg in pacman.conf
		if ! grep -q "^IgnorePkg.*tailscale" /etc/pacman.conf 2>/dev/null; then
			${SUDO} sed -i '/^#IgnorePkg/s/^#//' /etc/pacman.conf 2>/dev/null || true
			if grep -q "^IgnorePkg" /etc/pacman.conf 2>/dev/null; then
				${SUDO} sed -i '/^IgnorePkg/s/$/ tailscale/' /etc/pacman.conf
			else
				echo "IgnorePkg = tailscale" | ${SUDO} tee -a /etc/pacman.conf >/dev/null
			fi
			log_ok "Tailscale added to IgnorePkg (pacman.conf)"
		fi
		;;
	suse)
		${SUDO} zypper addlock tailscale 2>/dev/null || true
		log_ok "Tailscale package locked (zypper lock)"
		;;
	alpine)
		log_warn "Alpine Linux doesn't have built-in package hold. Consider using package masks."
		;;
	*)
		log_warn "Cannot hold package updates for unknown distribution"
		;;
	esac
}

# Release package hold (for uninstalling or manual updates)
release_package() {
	case "${DISTRO}" in
	debian)
		${SUDO} apt-mark unhold tailscale 2>/dev/null || true
		;;
	redhat)
		if command -v dnf >/dev/null 2>&1; then
			${SUDO} dnf versionlock delete tailscale 2>/dev/null || true
		elif command -v yum >/dev/null 2>&1; then
			${SUDO} yum versionlock delete tailscale 2>/dev/null || true
		fi
		;;
	arch)
		${SUDO} sed -i '/^IgnorePkg.*tailscale/s/ tailscale//' /etc/pacman.conf 2>/dev/null || true
		;;
	suse)
		${SUDO} zypper removelock tailscale 2>/dev/null || true
		;;
	esac
}

check_root() {
	if [[ ${EUID} -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi
}

# Detect architecture and set paths
arch="$(uname -m)"
case "${arch}" in
x86_64 | amd64) arch="amd64" ;;
aarch64 | arm64) arch="arm64" ;;
*)
	log_err "Unsupported architecture: ${arch}"
	exit 1
	;;

esac
platform="linux-${arch}"
INSTALL_DIR="/usr/local/bin"

log_info "Platform: ${platform}"
log_info "Install dir: ${INSTALL_DIR}"

# Determine the actual target paths
resolve_install_targets() {
	TS_PATH=$(command -v tailscale 2>/dev/null || true)
	TSD_PATH=$(command -v tailscaled 2>/dev/null || true)
	[[ -z ${TS_PATH-} ]] && TS_PATH="${INSTALL_DIR}/tailscale"
	[[ -z ${TSD_PATH-} ]] && TSD_PATH="${INSTALL_DIR}/tailscaled"

	if command -v systemctl >/dev/null 2>&1; then
		local exec_start
		exec_start=$(systemctl show -p ExecStart tailscaled 2>/dev/null | sed -E 's/^ExecStart=\??([^ ]+).*/\1/' || true)
		if [[ -n ${exec_start} && -x ${exec_start} ]]; then
			TSD_PATH="${exec_start}"
		fi
	fi
	export TS_PATH TSD_PATH
	log_info "tailscale -> ${TS_PATH}"
	log_info "tailscaled -> ${TSD_PATH}"
}

stop_service() {
	if command -v systemctl >/dev/null 2>&1; then
		if systemctl is-active --quiet tailscaled 2>/dev/null; then
			log_info "Stopping tailscaled service..."
			${SUDO} systemctl stop tailscaled || true
		fi
	else
		log_warn "systemd not found; ensure tailscaled is stopped manually"
	fi
}

start_service() {
	if command -v systemctl >/dev/null 2>&1; then
		log_info "Starting tailscaled service..."
		${SUDO} systemctl start tailscaled || true
		${SUDO} systemctl enable tailscaled || true
	fi
}

install_official_if_missing() {
	if ! command -v tailscale >/dev/null 2>&1; then
		log_warn "Tailscale not found. Installing official version first..."
		install_official_tailscale
		log_ok "Official Tailscale installed"
	else
		log_info "Tailscale found; will replace binaries"
	fi
}

install_binaries() {
	if [[ ${VERSION} == "latest" ]]; then
		log_info "Fetching latest release tag..."
		local api_url="https://api.github.com/repos/${REPO}/releases/latest"
		local latest_tag
		latest_tag=$(curl -fsSL "${api_url}" | grep '"tag_name"' | sed -E 's/.*"([^\"]+)".*/\1/')
		[[ -z ${latest_tag} ]] && {
			log_err "Failed to resolve latest release"
			exit 1
		}
		VERSION="${latest_tag}"
		log_info "Latest version: ${VERSION}"
	fi

	local base_url="https://github.com/${REPO}/releases/download/${VERSION}"
	if [[ -n ${MIRROR_PREFIX} ]]; then
		base_url="${MIRROR_PREFIX}/https://github.com/${REPO}/releases/download/${VERSION}"
		log_info "Using mirror for downloads: ${MIRROR_PREFIX}"
	fi

	local tailscale_binary="tailscale-${platform}"
	local tailscaled_binary="tailscaled-${platform}"

	local tmp
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	pushd "${tmp}" >/dev/null

	log_info "Downloading ${tailscale_binary}"
	curl -fL "${base_url}/${tailscale_binary}" -o tailscale
	log_info "Downloading ${tailscaled_binary}"
	curl -fL "${base_url}/${tailscaled_binary}" -o tailscaled
	chmod +x tailscale tailscaled

	stop_service
	resolve_install_targets

	${SUDO} mkdir -p "$(dirname "${TS_PATH}")" "$(dirname "${TSD_PATH}")"
	log_info "Installing to ${TS_PATH}"
	${SUDO} install -m 0755 tailscale "${TS_PATH}"
	log_info "Installing to ${TSD_PATH}"
	${SUDO} install -m 0755 tailscaled "${TSD_PATH}"

	popd >/dev/null
	rm -rf "${tmp}"
	trap - EXIT
	log_ok "Binaries installed"
}

usage() {
	echo ""
	echo "🎉 Installation completed!"
	echo ""
	echo "Quick Start:"
	echo "  tailscale up"
	echo ""
	echo "Amnezia-WG commands:"
	echo "  tailscale amnezia-wg set"
	echo "  tailscale amnezia-wg get"
	echo "  tailscale amnezia-wg reset"
	echo ""
}

main() {
	echo "🔧 Linux Installer (Amnezia-WG 1.5)"

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--mirror)
			MIRROR_PREFIX="$2"
			log_info "Using mirror: ${MIRROR_PREFIX}"
			shift 2
			;;
		--no-hold)
			NO_HOLD=true
			log_info "Package hold disabled"
			shift
			;;
		--release-hold)
			detect_distro
			check_root
			release_package
			log_ok "Package hold released"
			exit 0
			;;
		--help | -h)
			echo "Usage: $0 [OPTIONS]"
			echo ""
			echo "Options:"
			echo "  --mirror PREFIX     Use GitHub mirror with specified prefix"
			echo "  --no-hold          Don't hold package to prevent updates"
			echo "  --release-hold     Release package hold and exit"
			echo "  --help, -h         Show this help"
			echo ""
			echo "Examples:"
			echo "  # Install with mirror:"
			echo "  curl -fsSL URL | bash -s -- --mirror https://your-mirror-site.com"
			echo ""
			echo "  # Install without package hold:"
			echo "  curl -fsSL URL | bash -s -- --no-hold"
			echo ""
			echo "  # Release package hold:"
			echo "  curl -fsSL URL | bash -s -- --release-hold"
			exit 0
			;;
		*)
			log_warn "Unknown option: $1"
			shift
			;;
		esac
	done

	detect_distro
	check_root
	install_official_if_missing
	install_binaries

	# Hold package updates unless explicitly disabled
	if [[ ${NO_HOLD:-false} != true ]]; then
		hold_package
	fi

	start_service
	usage
}

main "$@"
