#!/usr/bin/env bash
# Linux installer: replace official Tailscale with Amnezia-WG-enabled binaries
# Usage: curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash

set -euo pipefail

# Constants
readonly REPO="LiuTangLei/tailscale"
readonly INSTALL_DIR="/usr/local/bin"

# Colors
readonly R='\033[31m' G='\033[32m' Y='\033[33m' B='\033[34m' N='\033[0m'
log() { echo -e "${!1}[${1}]${N} $2"; }

# Global variables
DISTRO="" PACKAGE_MANAGER="" SUDO="" RELEASE_TAG="latest" MIRROR_PREFIX="" FALLBACK_BINARY=false ACTION="install"
TMP_DIRS=()
CURL_HTTP1_FLAG=""

# Detect if curl supports --http1.1 (old curl like 7.29.0 on CentOS 7 doesn't)
if command -v curl &>/dev/null; then
	if curl --help 2>&1 | grep -q -- '--http1\.1'; then
		CURL_HTTP1_FLAG='--http1.1'
	fi
fi

# Robust cleanup (single trap, additive)
cleanup() {
	local code=$?
	for d in "${TMP_DIRS[@]-}"; do
		[[ -n ${d} && -d ${d} ]] && rm -rf -- "${d}"
	done
	exit "${code}"
}
trap cleanup EXIT INT TERM

# Detect distribution and package manager
detect_system() {
	[[ ${EUID} -eq 0 ]] && SUDO="" || SUDO="sudo"

	if [[ -f /etc/os-release ]]; then
		source /etc/os-release
		case "${ID}" in
		ubuntu | debian | mint* | elementary | zorin)
			DISTRO="debian"
			PACKAGE_MANAGER="apt"
			;;
		fedora | rhel | centos | rocky | almalinux | ol)
			DISTRO="redhat"
			PACKAGE_MANAGER="dnf"
			! command -v dnf &>/dev/null && PACKAGE_MANAGER="yum"
			;;
		arch | manjaro | endeavour*)
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
		*) DISTRO="unknown" ;;
		esac
	fi

	log B "Platform: linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
	log B "Distribution: ${DISTRO}${PACKAGE_MANAGER:+ (${PACKAGE_MANAGER})}"
}

# Smart download with fallbacks
smart_download() {
	local url="$1" output="$2"
	# Prefer HTTP/1.1 if supported (avoid some HTTP/2 issues); fallback silently if flag unsupported
	if command -v curl &>/dev/null; then
		curl -fsSL ${CURL_HTTP1_FLAG:+${CURL_HTTP1_FLAG}} --max-time 30 "${url}" -o "${output}" 2>/dev/null || true
	fi
	[[ -s ${output} ]] || wget -qO "${output}" --timeout=30 "${url}" 2>/dev/null || {
		log R "Failed to download: ${url}"
		return 1
	}
}

# Install official Tailscale if missing
install_tailscale() {
	if command -v tailscale &>/dev/null; then
		log B "Tailscale found"
		return
	fi
	log Y "Installing official Tailscale via upstream script..."
	# Prefer curl then wget
	if command -v curl &>/dev/null; then
		if ! curl -fsSL https://tailscale.com/install.sh | sh 2>/dev/null; then
			log R "Official installer failed; will fallback to direct binary replacement"
			FALLBACK_BINARY=true
			return
		fi
	elif command -v wget &>/dev/null; then
		if ! wget -qO- https://tailscale.com/install.sh | sh 2>/dev/null; then
			log R "Official installer failed; will fallback to direct binary replacement"
			FALLBACK_BINARY=true
			return
		fi
	else
		log R "Neither curl nor wget available to fetch official installer; fallback to direct binary replacement"
		FALLBACK_BINARY=true
		return
	fi
	log G "Official Tailscale installed"
}

# Get latest version from GitHub API
get_version() {
	# Fetch latest GitHub release tag unless user pinned via RELEASE_TAG env/arg
	[[ ${RELEASE_TAG} != "latest" ]] && return

	# If /etc/os-release exported VERSION (e.g. "9.0 (Emerald Puma)") it must NOT override our release tag logic
	# We intentionally keep our own variable name RELEASE_TAG to avoid collision.

	local api_url="https://api.github.com/repos/${REPO}/releases/latest"
	local tag_name=""

	if command -v curl &>/dev/null; then
		tag_name=$(curl -fsSL ${CURL_HTTP1_FLAG:+${CURL_HTTP1_FLAG}} --max-time 15 "${api_url}" | grep '"tag_name":' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' | head -1)
	elif command -v wget &>/dev/null; then
		tag_name=$(wget -qO- --timeout=15 "${api_url}" | grep '"tag_name":' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' | head -1)
	else
		log R "curl or wget required to fetch version"
		exit 1
	fi

	if [[ -z ${tag_name} || ! ${tag_name} =~ ^v[0-9]+\.[0-9]+ ]]; then
		log R "Failed to get version from GitHub API"
		exit 1
	fi

	RELEASE_TAG="${tag_name}"
	log B "Latest version: ${RELEASE_TAG}"
}

# Install custom binaries
install_binaries() {
	local arch platform base_url tmp_dir
	arch=$(uname -m)
	case "${arch}" in
	x86_64 | amd64) platform="linux-amd64" ;;
	aarch64 | arm64) platform="linux-arm64" ;;
	*)
		log R "Unsupported architecture: ${arch}"
		exit 1
		;;
	esac

	base_url="https://github.com/${REPO}/releases/download/${RELEASE_TAG}"
	[[ -n ${MIRROR_PREFIX} ]] && base_url="${MIRROR_PREFIX}/${base_url}"

	tmp_dir=$(mktemp -d)
	TMP_DIRS+=("${tmp_dir}")

	log B "Downloading Amnezia-WG binaries..."
	smart_download "${base_url}/tailscale-${platform}" "${tmp_dir}/tailscale" &&
		smart_download "${base_url}/tailscaled-${platform}" "${tmp_dir}/tailscaled" ||
		{
			log R "Download failed"
			exit 1
		}

	# Verify files: non-empty + ELF magic
	local ok=true
	for f in tailscale tailscaled; do
		if [[ ! -s "${tmp_dir}/${f}" ]]; then
			log R "File ${f} empty"
			ok=false
		elif ! head -c4 "${tmp_dir}/${f}" 2>/dev/null | grep -q $'\x7fELF'; then
			log R "File ${f} not ELF"
			ok=false
		fi
		# Basic permission set before install
		chmod 755 "${tmp_dir}/${f}" 2>/dev/null || true
	done
	if [[ ${ok} == false ]]; then
		log R "Binary validation failed"
		exit 1
	fi

	# Stop service and install
	systemctl is-active --quiet tailscaled 2>/dev/null && ${SUDO} systemctl stop tailscaled || true

	local ts_path td_path
	ts_path=$(command -v tailscale || echo "${INSTALL_DIR}/tailscale")
	td_path=$(command -v tailscaled || echo "${INSTALL_DIR}/tailscaled")

	# Use systemd path if available
	if command -v systemctl &>/dev/null; then
		local exec_start
		exec_start=$(systemctl show -p ExecStart tailscaled 2>/dev/null | sed -E 's/^ExecStart=\??([^ ]+).*/\1/' || true)
		[[ -n ${exec_start} && -x ${exec_start} ]] && td_path="${exec_start}"
	fi

	${SUDO} mkdir -p "$(dirname "${ts_path}")" "$(dirname "${td_path}")"
	${SUDO} install -m 755 "${tmp_dir}/tailscale" "${ts_path}"
	${SUDO} install -m 755 "${tmp_dir}/tailscaled" "${td_path}"

	log G "Binaries installed: ${ts_path}, ${td_path}"

	# If we had no official install (fallback) and no systemd unit, create a minimal one
	if [[ ${FALLBACK_BINARY} == true ]] && command -v systemctl &>/dev/null; then
		if ! systemctl list-unit-files | grep -q '^tailscaled\.service'; then
			log Y "Creating minimal systemd unit for tailscaled (fallback)"
			# Use discovered td_path instead of hardcoding
			cat <<UNIT | ${SUDO} tee /etc/systemd/system/tailscaled.service >/dev/null
[Unit]
Description=Tailscale node agent (fallback minimal unit)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=${td_path} --state=/var/lib/tailscale/tailscaled.state
Restart=on-failure
RuntimeDirectory=tailscale
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SYS_MODULE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SYS_MODULE
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT
			${SUDO} systemctl daemon-reload || true
		fi
	fi
}

# Comprehensive uninstall (remove packages, binaries, configs, state)
uninstall_all() {
	log Y "Uninstalling Tailscale (packages, binaries, config, state)..."

	detect_system

	# Stop service if running
	if command -v systemctl &>/dev/null; then
		if systemctl list-unit-files | grep -q '^tailscaled\.service'; then
			systemctl is-active --quiet tailscaled 2>/dev/null && ${SUDO} systemctl stop tailscaled || true
			${SUDO} systemctl disable tailscaled &>/dev/null || true
			log G "Service tailscaled stopped/disabled"
		fi
	fi

	# tailscale logout (ignore errors)
	if command -v tailscale &>/dev/null; then
		tailscale status &>/dev/null && tailscale logout 2>/dev/null || true
		tailscale down 2>/dev/null || true
	fi

	# (Legacy) attempt to clean any ignore/lock patterns if they exist (harmless)
	if [[ -f /etc/pacman.conf ]]; then
		${SUDO} sed -i '/^IgnorePkg/ { s/ tailscale//; s/tailscale //; }' /etc/pacman.conf 2>/dev/null || true
	fi

	# Uninstall via package manager if installed that way
	if command -v tailscale &>/dev/null || command -v tailscaled &>/dev/null; then
		case "${DISTRO}" in
		debian)
			${SUDO} apt-get remove -y tailscale 2>/dev/null || true
			;;
		redhat)
			if command -v dnf &>/dev/null; then ${SUDO} dnf remove -y tailscale 2>/dev/null || true; fi
			if command -v yum &>/dev/null; then ${SUDO} yum remove -y tailscale 2>/dev/null || true; fi
			;;
		arch)
			${SUDO} pacman -R --noconfirm tailscale 2>/dev/null || true
			;;
		alpine)
			${SUDO} apk del tailscale 2>/dev/null || true
			;;
		suse)
			${SUDO} zypper --non-interactive remove tailscale 2>/dev/null || true
			;;
		esac
	fi

	# Remove binaries (both our install dir and common paths)
	for b in /usr/local/bin/tailscale /usr/local/bin/tailscaled /usr/bin/tailscale /usr/bin/tailscaled; do
		if [[ -e ${b} ]]; then
			${SUDO} rm -f -- "${b}" && log G "Removed ${b}" || true
		fi
	done

	# Remove systemd unit & reload
	if command -v systemctl &>/dev/null; then
		for u in /etc/systemd/system/tailscaled.service /lib/systemd/system/tailscaled.service /usr/lib/systemd/system/tailscaled.service; do
			[[ -e ${u} ]] && ${SUDO} rm -f -- "${u}" && log G "Removed unit ${u}" || true
		done
		${SUDO} systemctl daemon-reload || true
	fi

	# Remove state & config directories
	for d in /var/lib/tailscale /var/run/tailscale /run/tailscale; do
		[[ -e ${d} ]] && ${SUDO} rm -rf -- "${d}" && log G "Removed dir ${d}" || true
	done
	for f in /etc/default/tailscaled /etc/sysconfig/tailscaled; do
		[[ -e ${f} ]] && ${SUDO} rm -f -- "${f}" && log G "Removed file ${f}" || true
	done

	# Remove repository config files
	for rf in /etc/apt/sources.list.d/tailscale.list /usr/share/keyrings/tailscale-archive-keyring.gpg /etc/yum.repos.d/tailscale.repo /etc/zypp/repos.d/tailscale.repo; do
		[[ -e ${rf} ]] && ${SUDO} rm -f -- "${rf}" && log G "Removed repo file ${rf}" || true
	done

	log G "Tailscale uninstalled (artifacts removed)"
	echo -e "\nIf you had iptables/routes modifications manually, review them. Reboot recommended for full cleanup of kernel modules (if any)."
}

# Main installation process
main() {
	echo "🔧 Tailscale Amnezia-WG Installer"

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--version)
			RELEASE_TAG="$2"
			shift 2
			;;
		--mirror)
			MIRROR_PREFIX="$2"
			shift 2
			;;
		--uninstall)
			ACTION="uninstall"
			shift
			;;
		--help | -h)
			cat <<EOF
Usage: $0 [OPTIONS]
Options:
  --mirror PREFIX     Use GitHub mirror
  --version TAG       Use specific GitHub release tag (e.g. v1.68.2)
  --uninstall        Remove Tailscale (packages, binaries, config, state) and exit
  --help, -h         Show this help
EOF
			exit 0
			;;
		*)
			log Y "Unknown option: $1"
			shift
			;;
		esac
	done

	detect_system

	if [[ ${ACTION} == "uninstall" ]]; then
		uninstall_all
		exit 0
	fi

	# Ensure we have curl or wget before using official installer
	if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
		log Y "Attempting to install curl (network tool)..."
		case "${DISTRO}" in
		debian) ${SUDO} apt update &>/dev/null && ${SUDO} apt install -y curl &>/dev/null || true ;;
		redhat) ${SUDO} "${PACKAGE_MANAGER}" install -y curl &>/dev/null || true ;;
		arch) ${SUDO} pacman -Sy --noconfirm curl &>/dev/null || true ;;
		alpine) ${SUDO} apk add --update curl &>/dev/null || true ;;
		suse) ${SUDO} zypper install -y curl &>/dev/null || true ;;
		esac
	fi
	install_tailscale
	get_version
	install_binaries

	# Start service
	if command -v systemctl &>/dev/null; then
		${SUDO} systemctl enable --now tailscaled &>/dev/null || true
		log G "Service started and enabled"
	fi

	echo -e "\n🎉 Installation completed!\n\nQuick Start:\n  tailscale up\n\nAmnezia-WG commands:\n  tailscale amnezia-wg set\n  tailscale amnezia-wg get\n  tailscale amnezia-wg reset"
}

main "$@"
