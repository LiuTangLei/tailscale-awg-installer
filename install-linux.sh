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

# Small helpers
has_cmd() { command -v "$1" &>/dev/null; }
systemd_available() { has_cmd systemctl; }
has_unit() { systemd_available && systemctl list-unit-files 2>/dev/null | grep -q "^$1"; }

# Extract official Tailscale version from fork tag (e.g., 1.90.6 from v1.90.6-awg2.0-1)
extract_official_version() {
	local tag="$1"
	if [[ ${tag} =~ ^v?([0-9]+\.[0-9]+\.[0-9]+) ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	fi
	return 1
}

# Write minimal/fallback systemd unit (idempotent overwrite)
write_minimal_unit() {
	local td_bin="$1"
	cat <<UNIT | ${SUDO} tee /etc/systemd/system/tailscaled.service >/dev/null
[Unit]
Description=Tailscale node agent (fallback minimal unit)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=${td_bin} --state=/var/lib/tailscale/tailscaled.state
Restart=on-failure
RuntimeDirectory=tailscale
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SYS_MODULE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SYS_MODULE
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT
	${SUDO} systemctl daemon-reload || true
}

stop_disable_tailscaled() {
	systemd_available || return 0
	has_unit tailscaled.service || return 0
	systemctl is-active --quiet tailscaled 2>/dev/null && ${SUDO} systemctl stop tailscaled || true
	# Only disable if uninstalling (ACTION=uninstall), otherwise just stop
	[[ ${ACTION} == "uninstall" ]] && ${SUDO} systemctl disable tailscaled &>/dev/null || true
}

# Global variables
DISTRO="" PACKAGE_MANAGER="" SUDO="" RELEASE_TAG="latest" MIRROR_PREFIX="" FALLBACK_BINARY=false ACTION="install" OFFICIAL_VERSION=""
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
	local target_version="$1" # Optional: specific version to install

	if command -v tailscale &>/dev/null; then
		log B "Tailscale found"
		# Check if installed version matches target version
		if [[ -n ${target_version} ]]; then
			local installed_version
			installed_version=$(tailscale version 2>/dev/null | head -1 | awk '{print $1}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "")
			if [[ -n ${installed_version} && ${installed_version} != "${target_version}" ]]; then
				log Y "Installed Tailscale version (${installed_version}) differs from fork base version (${target_version})"
				log Y "Will upgrade/downgrade to match fork version..."
				# Reinstall specific version via package manager
				reinstall_specific_version "${target_version}"
				return
			fi
		fi
		return
	fi

	log Y "Installing official Tailscale via upstream script..."
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

	# After installation, verify and adjust version if needed
	if [[ -n ${target_version} ]]; then
		local installed_version
		installed_version=$(tailscale version 2>/dev/null | head -1 | awk '{print $1}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "")
		if [[ -n ${installed_version} && ${installed_version} != "${target_version}" ]]; then
			log Y "Official installer installed ${installed_version}, but fork needs ${target_version}"
			reinstall_specific_version "${target_version}"
		fi
	fi
}

# Reinstall specific Tailscale version via package manager
reinstall_specific_version() {
	local version="$1"
	[[ -z ${version} ]] && return

	log B "Installing Tailscale ${version} via package manager..."
	case "${DISTRO}" in
	debian)
		${SUDO} apt-get update &>/dev/null || true
		${SUDO} apt-get install -y --allow-downgrades tailscale="${version}" 2>/dev/null ||
			log Y "Failed to install exact version ${version}, continuing with installed version"
		;;
	redhat)
		if command -v dnf &>/dev/null; then
			${SUDO} dnf install -y tailscale-"${version}" 2>/dev/null ||
				log Y "Failed to install exact version ${version}, continuing with installed version"
		elif command -v yum &>/dev/null; then
			${SUDO} yum install -y tailscale-"${version}" 2>/dev/null ||
				log Y "Failed to install exact version ${version}, continuing with installed version"
		fi
		;;
	suse)
		${SUDO} zypper --non-interactive install --force tailscale="${version}" 2>/dev/null ||
			log Y "Failed to install exact version ${version}, continuing with installed version"
		;;
	# arch, alpine use rolling/latest, version pinning not typically supported
	*)
		log Y "Version pinning not supported for ${DISTRO}, using installed version"
		;;
	esac
}

# Get latest version from GitHub API and extract official version
get_version() {
	if [[ ${RELEASE_TAG} != "latest" ]]; then
		# User specified a version tag via --version parameter
		# RELEASE_TAG is already set by user, just extract official version
		OFFICIAL_VERSION=$(extract_official_version "${RELEASE_TAG}")
		log B "Using version: ${RELEASE_TAG} (official base: v${OFFICIAL_VERSION})" >&2
		return
	fi

	local api_url="https://api.github.com/repos/${REPO}/releases/latest" tag_name=""
	if command -v curl &>/dev/null; then
		tag_name=$(curl -fsSL ${CURL_HTTP1_FLAG:+${CURL_HTTP1_FLAG}} --max-time 15 "${api_url}" | grep '"tag_name":' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' | head -1)
	elif command -v wget &>/dev/null; then
		tag_name=$(wget -qO- --timeout=15 "${api_url}" | grep '"tag_name":' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' | head -1)
	else
		log R "curl or wget required to fetch version" >&2
		exit 1
	fi

	if [[ -z ${tag_name} || ! ${tag_name} =~ ^v[0-9]+\.[0-9]+ ]]; then
		log R "Failed to get version from GitHub API" >&2
		exit 1
	fi

	# Extract official version number from fork tag (e.g., v1.90.6 from v1.90.6-awg2.0-1)
	OFFICIAL_VERSION=$(extract_official_version "${tag_name}")
	if [[ -n ${OFFICIAL_VERSION} ]]; then
		# Keep full fork tag for downloading binaries
		RELEASE_TAG="${tag_name}"
		log B "Latest version: ${tag_name} (official base: v${OFFICIAL_VERSION})" >&2
	else
		RELEASE_TAG="${tag_name}"
		log B "Latest version: ${RELEASE_TAG}" >&2
	fi
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
		smart_download "${base_url}/tailscaled-${platform}" "${tmp_dir}/tailscaled" || {
		log R "Download failed"
		exit 1
	}

	local ok=true f
	for f in tailscale tailscaled; do
		if [[ ! -s "${tmp_dir}/${f}" ]]; then
			log R "File ${f} empty"
			ok=false
		elif ! head -c4 "${tmp_dir}/${f}" 2>/dev/null | grep -q $'\x7fELF'; then
			log R "File ${f} not ELF"
			ok=false
		else
			# Verify it contains Amnezia-WG signature (awg command support)
			# Note: This is a best-effort check and may have false negatives
			if [[ ${f} == "tailscale" ]] && command -v strings &>/dev/null; then
				if ! strings "${tmp_dir}/${f}" 2>/dev/null | grep -qi "amnezia\|awg"; then
					# Suppress warning as it's often a false positive (AWG may be embedded differently)
					: # log Y "Debug: ${f} AWG signature not detected via strings (may be false negative)"
				fi
			fi
		fi
		chmod 755 "${tmp_dir}/${f}" 2>/dev/null || true
	done
	[[ ${ok} == false ]] && {
		log R "Binary validation failed"
		exit 1
	}

	# Stop running service if active (quieter helper)
	stop_disable_tailscaled || true

	# Determine existing paths (prefer existing commands for atomic replacement)
	local ts_path td_path
	ts_path=$(command -v tailscale || echo "${INSTALL_DIR}/tailscale")
	td_path=$(command -v tailscaled || echo "${INSTALL_DIR}/tailscaled")

	# Extract actual binary path from systemd service (more robust parsing)
	if systemd_available && systemctl list-unit-files 2>/dev/null | grep -q "^tailscaled.service"; then
		local exec_start
		# Try multiple parsing methods for compatibility
		# Method 1: Parse systemctl show output (structured format)
		exec_start=$(systemctl show -p ExecStart tailscaled 2>/dev/null | sed -n 's/.*path=\([^; ]\+\).*/\1/p' | head -1 || true)
		# Method 2: Alternative systemctl show parsing
		[[ -z ${exec_start} ]] && exec_start=$(systemctl show -p ExecStart tailscaled 2>/dev/null | sed -E 's/^ExecStart=[{ ]*path=([^ ;]+).*/\1/' || true)
		# Method 3: Parse unit file directly
		[[ -z ${exec_start} ]] && exec_start=$(systemctl cat tailscaled 2>/dev/null | grep '^ExecStart=' | sed 's/^ExecStart=\([^ ]\+\).*/\1/' | head -1 || true)
		# Method 4: Extract from systemctl status (fallback)
		[[ -z ${exec_start} ]] && exec_start=$(systemctl status tailscaled 2>/dev/null | grep -o '/[^ ]\+/tailscaled' | head -1 || true)
		# Method 5: Check common systemd paths directly
		if [[ -z ${exec_start} ]]; then
			for check_path in /usr/sbin/tailscaled /usr/bin/tailscaled /usr/local/sbin/tailscaled; do
				if [[ -x ${check_path} ]]; then
					exec_start="${check_path}"
					break
				fi
			done
		fi
		if [[ -n ${exec_start} && -x ${exec_start} ]]; then
			td_path="${exec_start}"
			log B "Detected tailscaled path from systemd: ${td_path}"
		fi
	fi

	# Also replace common alternative locations to ensure full coverage
	${SUDO} mkdir -p "$(dirname "${ts_path}")" "$(dirname "${td_path}")"
	${SUDO} install -m 755 "${tmp_dir}/tailscale" "${ts_path}"
	${SUDO} install -m 755 "${tmp_dir}/tailscaled" "${td_path}"

	# Replace in all common locations to ensure we get the one systemd is using
	for alt_path in /usr/bin/tailscale /usr/sbin/tailscale /usr/local/bin/tailscale; do
		if [[ -f ${alt_path} && ${alt_path} != "${ts_path}" ]]; then
			${SUDO} install -m 755 "${tmp_dir}/tailscale" "${alt_path}" 2>/dev/null || true
		fi
	done
	for alt_path in /usr/bin/tailscaled /usr/sbin/tailscaled /usr/local/bin/tailscaled; do
		if [[ -f ${alt_path} && ${alt_path} != "${td_path}" ]]; then
			${SUDO} install -m 755 "${tmp_dir}/tailscaled" "${alt_path}" 2>/dev/null || true
		fi
	done

	log G "Binaries installed: ${ts_path}, ${td_path}"

	# Fallback unit creation if no official unit existed and we came here due to binary fallback path
	if [[ ${FALLBACK_BINARY} == true ]] && systemd_available && ! has_unit tailscaled.service; then
		log Y "Creating minimal systemd unit for tailscaled (fallback)"
		write_minimal_unit "${td_path}"
	fi
}

# Comprehensive uninstall (remove packages, binaries, configs, state)
uninstall_all() {
	log Y "Uninstalling Tailscale (packages, binaries, config, state)..."

	# Stop & disable if present
	stop_disable_tailscaled && log G "Service tailscaled stopped/disabled" || true

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

	# Remove binaries, systemd units, state & config files
	for b in /usr/local/bin/tailscale{,d} /usr/bin/tailscale{,d} /usr/sbin/tailscale{,d}; do
		[[ -e ${b} ]] && ${SUDO} rm -f -- "${b}" && log G "Removed ${b}" || true
	done
	if command -v systemctl &>/dev/null; then
		for u in /etc/systemd/system/tailscaled.service /lib/systemd/system/tailscaled.service /usr/lib/systemd/system/tailscaled.service; do
			[[ -e ${u} ]] && ${SUDO} rm -f -- "${u}" && log G "Removed unit ${u}" || true
		done
		${SUDO} systemctl daemon-reload || true
	fi
	for d in /var/lib/tailscale /var/run/tailscale /run/tailscale; do
		[[ -e ${d} ]] && ${SUDO} rm -rf -- "${d}" && log G "Removed dir ${d}" || true
	done
	for f in /etc/default/tailscaled /etc/sysconfig/tailscaled /etc/apt/sources.list.d/tailscale.list /usr/share/keyrings/tailscale-archive-keyring.gpg /etc/yum.repos.d/tailscale.repo /etc/zypp/repos.d/tailscale.repo; do
		[[ -e ${f} ]] && ${SUDO} rm -f -- "${f}" && log G "Removed file ${f}" || true
	done

	log G "Tailscale uninstalled (artifacts removed)"
	echo -e "\nIf you had iptables/routes modifications manually, review them. Reboot recommended for full cleanup of kernel modules (if any)."
}

# Ensure required runtime/state directories exist (some minimal Debian/containers may not have them recreated automatically)
ensure_dirs() {
	${SUDO} mkdir -p /var/lib/tailscale 2>/dev/null || true
	${SUDO} chmod 700 /var/lib/tailscale 2>/dev/null || true
	# /var/run is typically a symlink to /run, so only create /run/tailscale
	${SUDO} mkdir -p /run/tailscale 2>/dev/null || true
}

# Health check with retries for tailscaled service / socket
health_check_tailscaled() {
	local attempts=0 max=8
	while ((attempts < max)); do
		# Active?
		if command -v systemctl &>/dev/null; then
			if systemctl is-active --quiet tailscaled 2>/dev/null; then
				# Socket responding?
				if command -v tailscale &>/dev/null; then
					tailscale status >/dev/null 2>&1 && return 0
				fi
				# If daemon active but tailscale client not yet ready, small sleep
			fi
		fi
		[[ -S /var/run/tailscale/tailscaled.sock || -S /run/tailscale/tailscaled.sock ]] && return 0
		sleep 1
		attempts=$((attempts + 1))
	done
	return 1
}

# Main installation process
main() {
	echo "🔧 Tailscale Amnezia-WG 2.0 Installer"

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

	get_version
	install_tailscale "${OFFICIAL_VERSION}"
	install_binaries

	# Start service
	if command -v systemctl &>/dev/null; then
		ensure_dirs
		# Force stop any running tailscaled processes before restart
		${SUDO} systemctl stop tailscaled &>/dev/null || true
		${SUDO} pkill -9 tailscaled 2>/dev/null || true
		sleep 1
		${SUDO} systemctl daemon-reload || true
		${SUDO} systemctl enable tailscaled &>/dev/null || true
		${SUDO} systemctl start tailscaled &>/dev/null || true
		if health_check_tailscaled; then
			log G "Service started and enabled"
		else
			log Y "Service not healthy after initial start; attempting fallback minimal unit"
			if command -v tailscaled &>/dev/null; then
				write_minimal_unit "$(command -v tailscaled)"
				${SUDO} systemctl restart tailscaled || true
				if health_check_tailscaled; then
					log G "Fallback unit started successfully"
				else
					log R "Fallback unit still unhealthy; collecting diagnostics"
					DIAG_LOG=$(mktemp /tmp/tailscaled-diag-XXXX.log)
					TMP_DIRS+=("$(dirname "${DIAG_LOG}")")
					(timeout 5s "${SUDO}" "$(command -v tailscaled)" --state=/var/lib/tailscale/tailscaled.state 2>&1 | tee "${DIAG_LOG}" >/dev/null) || true
					log R "Diagnostics captured in ${DIAG_LOG}"
				fi
			fi
		fi
	fi

	# Verify installation by checking versions
	if command -v tailscale &>/dev/null; then
		local client_version daemon_version
		client_version=$(tailscale version 2>/dev/null | head -1 | awk '{print $1}' || echo "unknown")
		if command -v tailscaled &>/dev/null && systemctl is-active --quiet tailscaled 2>/dev/null; then
			sleep 2
			# Try direct tailscaled version first (more reliable)
			daemon_version=$(${SUDO} tailscaled --version 2>/dev/null | head -1 | awk '{print $1}' || echo "unknown")
			# Fallback to tailscale status if direct call fails
			if [[ ${daemon_version} == "unknown" ]]; then
				daemon_version=$(tailscale status --json 2>/dev/null | grep -o '"Self":{[^}]*"TailscaleVersion":"[^"]*"' | sed 's/.*TailscaleVersion":"\([^"]*\)".*/\1/' || echo "unknown")
			fi
		fi
		if [[ -n ${client_version} && -n ${daemon_version} ]]; then
			echo -e "\n🎉 Installation completed!\n\nVersion verification:"
			echo -e "  Client (tailscale):  ${client_version}\n  Daemon (tailscaled): ${daemon_version}"
			[[ ${client_version} != "${daemon_version}" && ${client_version} != "unknown" && ${daemon_version} != "unknown" ]] &&
				log Y "Version mismatch detected! You may need to restart: ${SUDO}${SUDO:+ }systemctl restart tailscaled"
			echo ""
		else
			echo -e "\n🎉 Installation completed!\n"
		fi
	else
		echo -e "\n🎉 Installation completed!\n"
	fi

	echo -e "Quick Start:"
	echo -e "  tailscale up\n"
	echo -e "Amnezia-WG commands (awg = amnezia-wg):"
	echo -e "  tailscale awg set        # Configure obfuscation (auto-generate with Enter)"
	echo -e "  tailscale awg get        # Show current config"
	echo -e "  tailscale awg sync       # Sync config from other nodes"
	echo -e "  tailscale awg reset      # Disable obfuscation"
}

main "$@"
