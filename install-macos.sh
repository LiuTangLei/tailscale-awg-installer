#!/usr/bin/env bash
# macOS-only installer: replace official Tailscale with Amnezia-WG-enabled binaries
# Automatically detects and handles conflicts with App Store/Standalone Tailscale variants.
# Uses CLI (utun) variant for maximum compatibility. Supports Intel & Apple Silicon.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash
#   # With mirror:
#   curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --mirror https://your-mirror-site.com
#   # Uninstall everything:
#   curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --uninstall

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

# Note: Configuration backup removed as App/CLI variants use incompatible formats
# Users will need to re-authenticate after switching to CLI version

# Function to check for App Store or Standalone Tailscale installation
check_app_conflict() {
	local has_app=false
	local app_type=""

	# Check for Homebrew Cask version
	if command -v brew >/dev/null 2>&1 && brew list --cask tailscale-app &>/dev/null; then
		has_app=true
		app_type="Homebrew Cask"
	fi

	# Check for Tailscale.app
	if [[ -d "/Applications/Tailscale.app" ]]; then
		has_app=true
		[[ -z ${app_type} ]] && app_type="Standalone"
	fi

	# Check for Mac App Store version (has different bundle structure)
	if [[ -d "/Applications/Tailscale.app" ]] &&
		grep -q "com.apple.AppStore" "/Applications/Tailscale.app/Contents/Info.plist" 2>/dev/null; then
		app_type="Mac App Store"
	fi

	# Check for running System Extensions (only enabled ones)
	if systemextensionsctl list 2>/dev/null | grep -i tailscale | grep -q "enabled" ||
		pgrep -f "io.tailscale.ipn.macsys.network-extension" >/dev/null 2>&1; then
		has_app=true
		[[ -z ${app_type} ]] && app_type="System Extension"
	fi

	if [[ ${has_app} == true ]]; then
		echo ""
		warn "⚠️  Detected existing Tailscale installation: ${app_type} variant"
		echo ""
		echo "The CLI version we're installing uses a different architecture (utun interface)"
		echo "and will conflict with the App version (System/Network Extension)."
		echo ""
		echo "To proceed, we need to:"
		echo "  • Remove the existing Tailscale.app"
		echo "  • Install the CLI version with Amnezia-WG support"
		echo "  • You'll need to re-authenticate after installation"
		echo ""

		local response
		if [[ ! -t 0 ]]; then
			# Running via pipe (curl | bash); read from controlling terminal to enable interaction
			read -r -p "Do you want to remove the existing Tailscale and install CLI version? [Y/n]: " response </dev/tty || response="Y"
		else
			read -r -p "Do you want to remove the existing Tailscale and install CLI version? [Y/n]: " response
		fi
		response=${response:-Y}

		case ${response} in
		[yY][eE][sS] | [yY])
			info "Proceeding with removal of existing Tailscale..."
			remove_existing_tailscale
			;;
		*)
			warn "User chose to keep existing App version. Continuing with CLI binary installation (may conflict)."
			echo "If you later see conflicts, rerun and choose Y or uninstall the App manually."
			;;
		esac
	fi
}

# Function to remove existing Tailscale installations
remove_existing_tailscale() {
	info "Removing existing Tailscale installation..."

	# Force quit Tailscale app and ensure it's completely closed
	info "Stopping Tailscale application..."

	# Try graceful quit first
	osascript -e 'quit app "Tailscale"' 2>/dev/null || true
	sleep 3

	# Check if app is still running and force quit if needed
	if pgrep -f "Tailscale.app" >/dev/null 2>&1; then
		warn "Tailscale app still running, force quitting..."
		osascript -e 'tell application "Tailscale" to quit' 2>/dev/null || true
		sleep 2

		# If still running, use force quit
		if pgrep -f "Tailscale.app" >/dev/null 2>&1; then
			warn "Using force quit..."
			${SUDO} pkill -9 -f "Tailscale.app" 2>/dev/null || true
			sleep 2
		fi
	fi

	# Kill any remaining Tailscale processes
	info "Stopping all Tailscale processes..."
	${SUDO} pkill -f "tailscale\|Tailscale" 2>/dev/null || true
	sleep 2

	# Verify no Tailscale processes are running
	local remaining_procs
	remaining_procs=$(pgrep -f "tailscale\|Tailscale" 2>/dev/null || true)
	if [[ -n ${remaining_procs} ]]; then
		warn "Some Tailscale processes are still running, force killing..."
		echo "${remaining_procs}" | xargs "${SUDO}" kill -9 2>/dev/null || true
		sleep 2
	fi

	ok "All Tailscale processes stopped"

	# Remove system extensions first (critical for avoiding conflicts)
	info "Removing Tailscale system extensions..."
	local extension_found=false

	# Check if Tailscale system extension exists and is enabled
	if systemextensionsctl list 2>/dev/null | grep -i tailscale | grep -q "enabled"; then
		extension_found=true
		warn "Tailscale system extension detected - this requires manual removal"
		echo ""
		echo "Please follow these steps to remove the system extension:"
		echo "1. Open System Settings"
		echo "2. Go to General > Login Items & Extensions"
		echo "3. Click on 'Network Extensions'"
		echo "4. Find 'Tailscale Network Extension' and disable it"
		echo "5. Wait for it to be fully removed"
		echo ""

		local response
		# Check if we're running from a pipe (curl | bash)
		if [[ ! -t 0 ]]; then
			exec </dev/tty
		fi
		read -r -p "Press Enter after you've disabled the Tailscale Network Extension..." response

		# Verify removal
		local attempts=0
		while [[ ${attempts} -lt 30 ]]; do
			if ! systemextensionsctl list 2>/dev/null | grep -i tailscale | grep -q "enabled"; then
				ok "System extension successfully disabled"
				break
			fi
			echo -n "."
			sleep 2
			attempts=$((attempts + 1))
		done

		if [[ ${attempts} -eq 30 ]]; then
			warn "System extension still enabled. This may cause conflicts."
			echo "You may need to reboot your Mac to fully remove the extension."
		fi
	fi

	# Remove Tailscale.app with verification
	if [[ -d "/Applications/Tailscale.app" ]]; then
		info "Removing Tailscale.app..."

		# Try to remove the app
		if ${SUDO} rm -rf "/Applications/Tailscale.app" 2>/dev/null; then
			ok "Removed Tailscale.app"
		else
			warn "Failed to remove Tailscale.app on first attempt"

			# Check if any processes are still using the app
			local app_procs
			app_procs=$(lsof "/Applications/Tailscale.app" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u || true)
			if [[ -n ${app_procs} ]]; then
				warn "Found processes still using Tailscale.app, killing them..."
				echo "${app_procs}" | xargs "${SUDO}" kill -9 2>/dev/null || true
				sleep 2
			fi

			# Try again
			if ${SUDO} rm -rf "/Applications/Tailscale.app" 2>/dev/null; then
				ok "Removed Tailscale.app (second attempt)"
			else
				err "Failed to remove Tailscale.app even after stopping all processes"
				echo "You may need to manually delete /Applications/Tailscale.app"
				echo "or reboot your Mac and run the script again."
				return 1
			fi
		fi

		# Verify removal
		if [[ -d "/Applications/Tailscale.app" ]]; then
			warn "Tailscale.app directory still exists after deletion attempt"
		fi
	fi

	# Clean up system extension directories
	info "Cleaning up system extension remnants..."
	if [[ -d "/Library/SystemExtensions" ]]; then
		local ext_dirs
		ext_dirs=$(find /Library/SystemExtensions -name "*tailscale*" -type d 2>/dev/null || true)
		if [[ -n ${ext_dirs} ]]; then
			echo "${ext_dirs}" | while read -r dir; do
				if [[ -n ${dir} ]]; then
					${SUDO} rm -rf "${dir}" 2>/dev/null || true
					ok "Removed system extension directory: $(basename "${dir}")"
				fi
			done
		fi
	fi

	# Remove binaries from common locations
	for binary in tailscale tailscaled; do
		for path in "/usr/local/bin/${binary}" "/opt/homebrew/bin/${binary}"; do
			if [[ -f ${path} ]]; then
				${SUDO} rm -f "${path}"
				ok "Removed ${path}"
			fi
		done
	done

	# Remove LaunchDaemon if exists
	if [[ -f "/Library/LaunchDaemons/com.tailscale.tailscaled.plist" ]]; then
		${SUDO} launchctl unload "/Library/LaunchDaemons/com.tailscale.tailscaled.plist" 2>/dev/null || true
		${SUDO} rm -f "/Library/LaunchDaemons/com.tailscale.tailscaled.plist"
		ok "Removed LaunchDaemon"
	fi

	# Remove Homebrew Cask version if present
	if command -v brew >/dev/null 2>&1 && brew list --cask tailscale-app &>/dev/null; then
		info "Removing Homebrew Tailscale Cask..."
		brew uninstall --cask tailscale-app 2>/dev/null || {
			warn "Failed to uninstall Homebrew Cask version automatically"
			echo "You may need to run: brew uninstall --cask tailscale-app"
		}
	fi

	info "Existing Tailscale installation removed successfully"

	if [[ ${extension_found} == true ]]; then
		echo ""
		warn "IMPORTANT: A reboot is recommended to ensure complete system extension removal"
		echo "If you experience issues after installation, please reboot your Mac."
	fi

	echo "Waiting for system to stabilize..."
	sleep 5
}

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
	# Create LaunchDaemon plist if it doesn't exist
	if [[ ! -f "/Library/LaunchDaemons/com.tailscale.tailscaled.plist" ]]; then
		info "Creating LaunchDaemon configuration..."
		cat <<PLIST | ${SUDO} tee /Library/LaunchDaemons/com.tailscale.tailscaled.plist >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.tailscale.tailscaled</string>
    <key>ProgramArguments</key>
    <array>
        <string>${TSD_PATH}</string>
        <string>--state=/var/lib/tailscale/tailscaled.state</string>
        <string>--socket=/var/run/tailscaled.socket</string>
        <string>--port=41641</string>
        <string>--tun=utun</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/tailscaled.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/tailscaled.log</string>
</dict>
</plist>
PLIST
		ok "Created LaunchDaemon configuration"
	fi

	# Ensure directories exist
	${SUDO} mkdir -p /var/lib/tailscale /var/run

	# Ensure service is stopped before starting (force restart)
	if launchctl list | grep -q com.tailscale.tailscaled 2>/dev/null; then
		info "Ensuring tailscaled is stopped before restart..."
		${SUDO} launchctl unload /Library/LaunchDaemons/com.tailscale.tailscaled.plist 2>/dev/null || true
		sleep 1
	fi

	info "Starting tailscaled (launchctl load)..."
	${SUDO} launchctl load /Library/LaunchDaemons/com.tailscale.tailscaled.plist 2>/dev/null || true

	# Wait a moment for service to start
	sleep 2

	# Verify service is running
	if pgrep -f tailscaled >/dev/null 2>&1; then
		ok "tailscaled service started successfully"
	else
		warn "tailscaled service may not have started properly"
		echo "You can manually start it with: sudo launchctl load /Library/LaunchDaemons/com.tailscale.tailscaled.plist"
	fi
}

install_official_if_missing() {
	if ! command -v tailscale >/dev/null 2>&1; then
		warn "Tailscale not found. Installing via Homebrew..."
		if command -v brew >/dev/null 2>&1; then
			info "Installing Tailscale via Homebrew..."
			brew install tailscale || {
				err "Failed to install Tailscale via Homebrew"
				exit 1
			}
		else
			err "Homebrew not found. Please install Tailscale manually:"
			echo "  1. Download from https://tailscale.com/download/mac"
			echo "  2. Or install Homebrew: https://brew.sh"
			exit 1
		fi
	else
		info "Tailscale found; will replace binaries with Amnezia-WG versions"
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

	# Verify installation
	info "Verifying installation..."
	if command -v tailscale >/dev/null 2>&1 && command -v tailscaled >/dev/null 2>&1; then
		local ts_version tsd_version
		ts_version=$(tailscale version --client 2>/dev/null | head -n1 || echo "unknown")
		tsd_version=$(tailscaled --version 2>/dev/null | head -n1 || echo "unknown")
		ok "Installation verified:"
		echo "  tailscale:  ${ts_version}"
		echo "  tailscaled: ${tsd_version}"

		# Check version consistency
		if [[ ${ts_version} != "unknown" && ${tsd_version} != "unknown" ]]; then
			if [[ ${ts_version} == "${tsd_version}" ]]; then
				ok "Client and daemon versions match"
			else
				warn "Version mismatch detected:"
				echo "  Client: ${ts_version}"
				echo "  Daemon: ${tsd_version}"
			fi
		fi
	else
		warn "Installation verification failed - binaries may not be in PATH"
	fi
}

# Comprehensive uninstall function
uninstall_all() {
	warn "Uninstalling Tailscale (all variants and configurations)..."

	# Stop services first
	stop_service

	# tailscale logout (ignore errors)
	if command -v tailscale &>/dev/null; then
		tailscale status &>/dev/null && tailscale logout 2>/dev/null || true
		tailscale down 2>/dev/null || true
	fi

	# Remove Standalone Tailscale.app if present
	if [[ -d "/Applications/Tailscale.app" ]]; then
		info "Removing Tailscale.app..."
		${SUDO} rm -rf "/Applications/Tailscale.app" && ok "Removed Tailscale.app" || true
	fi

	# Remove System Extensions
	if [[ -d "/Library/SystemExtensions" ]]; then
		local sys_ext_dirs
		sys_ext_dirs=$(find /Library/SystemExtensions -name "*tailscale*" -type d 2>/dev/null || true)
		if [[ -n ${sys_ext_dirs} ]]; then
			info "Removing Tailscale System Extensions..."
			echo "${sys_ext_dirs}" | while read -r dir; do
				[[ -n ${dir} && -d ${dir} ]] && ${SUDO} rm -rf "${dir}" && ok "Removed ${dir}" || true
			done
		fi
	fi

	# Remove binaries from common locations
	for binary in tailscale tailscaled; do
		for path in "/usr/local/bin/${binary}" "/opt/homebrew/bin/${binary}"; do
			if [[ -f ${path} ]]; then
				${SUDO} rm -f "${path}" && ok "Removed ${path}" || true
			fi
		done
	done

	# Remove LaunchDaemon plist
	if [[ -f "/Library/LaunchDaemons/com.tailscale.tailscaled.plist" ]]; then
		info "Removing LaunchDaemon..."
		${SUDO} rm -f "/Library/LaunchDaemons/com.tailscale.tailscaled.plist" && ok "Removed LaunchDaemon plist" || true
	fi

	# Remove state and configuration directories
	for dir in "/var/lib/tailscale" "/Library/Tailscale" "/var/run/tailscale"; do
		if [[ -d ${dir} ]]; then
			${SUDO} rm -rf "${dir}" && ok "Removed directory ${dir}" || true
		fi
	done

	# Remove user preference files
	for user_dir in /Users/*/Library/Preferences/com.tailscale.ipn.macos.plist; do
		if [[ -f ${user_dir} ]]; then
			rm -f "${user_dir}" && ok "Removed user preferences ${user_dir}" || true
		fi
	done

	# Remove Homebrew installation if present
	if command -v brew &>/dev/null; then
		# Remove Formula version
		if brew list 2>/dev/null | grep -q "tailscale"; then
			info "Removing Homebrew Tailscale..."
			brew uninstall tailscale 2>/dev/null || true
		fi

		# Remove Cask version
		if brew list --cask tailscale-app &>/dev/null; then
			info "Removing Homebrew Tailscale Cask..."
			brew uninstall --cask tailscale-app 2>/dev/null || true
		fi
	fi

	ok "Tailscale uninstalled (all variants and artifacts removed)"
	echo ""
	echo "Note: If you had custom network configurations, please review them manually."
	echo "A reboot may be required for complete cleanup of system extensions and network interfaces."
}

usage() {
	echo ""
	ok "Installation completed successfully! 🎉"
	echo ""
	echo "🔧 Amnezia-WG Commands (awg = amnezia-wg):"
	echo "  tailscale up                    # Connect to your network (re-auth required)"
	echo "  tailscale awg set               # Configure obfuscation (auto-generate with Enter)"
	echo "  tailscale awg get               # Show current config"
	echo "  tailscale awg sync              # Sync config from other nodes"
	echo "  tailscale awg reset             # Disable obfuscation"
	echo ""
	echo "💡 Troubleshooting:"
	echo "  • If commands not found, restart your terminal or run:"
	echo "    export PATH=\"${INSTALL_DIR}:\$PATH\""
	echo "  • Check that client and daemon versions match with 'tailscale version'"
	echo ""
	echo "🗑  Uninstall:"
	echo "  curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --uninstall"
	echo ""
}

main() {
	echo "🔧 macOS Installer (Amnezia-WG 2.0)"

	# Parse arguments
	local ACTION="install"
	while [[ $# -gt 0 ]]; do
		case $1 in
		--mirror)
			MIRROR_PREFIX="$2"
			info "Using mirror: ${MIRROR_PREFIX}"
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
  --mirror PREFIX    Use GitHub mirror with specified prefix
  --uninstall       Remove Tailscale (all variants, binaries, config, state) and exit
  --help, -h        Show this help

Examples:
  # Install with Amnezia-WG support:
  curl -fsSL URL | bash

  # Install with mirror:
  curl -fsSL URL | bash -s -- --mirror https://your-mirror-site.com

  # Uninstall everything:
  curl -fsSL URL | bash -s -- --uninstall

Note: This installer uses the CLI-only variant of Tailscale to avoid
System Extension limitations on macOS.
EOF
			exit 0
			;;
		*)
			warn "Unknown option: $1"
			shift
			;;
		esac
	done

	check_root

	if [[ ${ACTION} == "uninstall" ]]; then
		uninstall_all
		exit 0
	fi

	# Check for conflicting Tailscale installations
	check_app_conflict

	install_official_if_missing
	install_binaries
	start_service
	usage
}

main "$@"
