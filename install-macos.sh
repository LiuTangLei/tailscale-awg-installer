#!/usr/bin/env bash
# macOS-only installer: replace official Tailscale with AWG v2/v3-enabled binaries
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
PRE_RELEASE=false
AWG_C_REMOVED_VERSION="1.98.1"
AWG_V3_MIN_VERSION="1.102.2"
LEGACY_CPS_COUNTER_DETECTED=false
REMOVE_EXISTING_APP=false
ROLLBACK_AVAILABLE=false
ROLLBACK_TS_PATH=""
ROLLBACK_TSD_PATH=""
ROLLBACK_DIR=""
ROLLBACK_TS_EXISTED=false
ROLLBACK_TSD_EXISTED=false
ROLLBACK_PLIST_EXISTED=false
ROLLBACK_SERVICE_WAS_LOADED=false
ROLLBACK_APP_STAGED=false
ROLLBACK_APP_ORIGINAL_PATH="/Applications/Tailscale.app"
ROLLBACK_APP_STAGED_PATH=""
ROLLBACK_APP_WAS_CASK=false
ROLLBACK_EXTENSION_WAS_DISABLED=false
ROLLBACK_CASK_RECEIPT_REMOVED=false
ROLLBACK_CASK_CLEANUP_ATTEMPTED=false
ROLLBACK_TS_COMMAND_WAS_SYMLINK=false
ROLLBACK_TS_COMMAND_LINK=""
TS_COMMAND_REPLACES_APP_LINK=false
ROLLBACK_TEMP_DIR=""
PRESERVE_ROLLBACK_TEMP=false
TS_COMMAND_PATH=""
VERIFIED_TS_SOURCE=""
VERIFIED_TSD_SOURCE=""
VERIFIED_TS_SHA256=""
VERIFIED_TSD_SHA256=""
EXPECTED_INSTALL_VERSION=""
TEMP_DIRS=()

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

cleanup() {
	local code=$?
	if [[ ${code} -ne 0 && ${ROLLBACK_AVAILABLE} == true ]]; then
		set +e
		warn "Installation did not complete; restoring the previous CLI/service installation"
		rollback_install
	fi
	local dir
	for dir in "${TEMP_DIRS[@]-}"; do
		if [[ ${PRESERVE_ROLLBACK_TEMP} == true && -n ${ROLLBACK_TEMP_DIR} && ${dir} == "${ROLLBACK_TEMP_DIR}" ]]; then
			continue
		fi
		[[ -n ${dir} && -d ${dir} ]] && rm -rf -- "${dir}"
	done
	exit "${code}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

check_root() {
	if [[ ${EUID} -eq 0 ]]; then
		SUDO=""
	elif command -v sudo >/dev/null 2>&1; then
		SUDO="sudo"
	else
		err "Administrator privileges are required and sudo is not installed"
		return 1
	fi
}

extract_release_tags_by_prerelease() {
	local prerelease_value="$1"
	awk -v wanted="${prerelease_value}" '
		{
			line = $0
			while (match(line, /"(tag_name|prerelease)"[[:space:]]*:[[:space:]]*("[^"]*"|true|false)/)) {
				token = substr(line, RSTART, RLENGTH)
				if (token ~ /^"tag_name"/) {
					value = token
					sub(/.*:[[:space:]]*"/, "", value)
					sub(/"$/, "", value)
					tag = value
				} else {
					value = token
					sub(/.*:[[:space:]]*/, "", value)
					if (tag != "" && value == wanted) print tag
					tag = ""
				}
				line = substr(line, RSTART + RLENGTH)
			}
		}
	'
}

version_parts() {
	local tag="$1"
	if [[ ${tag} =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
		printf '%s %s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
		return 0
	fi
	return 1
}

tag_is_newer_than() {
	local candidate="$1" current="$2"
	local c_major c_minor c_patch cur_major cur_minor cur_patch
	if ! read -r c_major c_minor c_patch < <(version_parts "${candidate}"); then return 1; fi
	if ! read -r cur_major cur_minor cur_patch < <(version_parts "${current}"); then return 0; fi
	if ((c_major != cur_major)); then ((c_major > cur_major)); return; fi
	if ((c_minor != cur_minor)); then ((c_minor > cur_minor)); return; fi
	((c_patch > cur_patch))
}

version_at_least() {
	local current="$1" minimum="$2"
	local cur_major cur_minor cur_patch min_major min_minor min_patch
	if ! read -r cur_major cur_minor cur_patch < <(version_parts "${current}"); then return 1; fi
	if ! read -r min_major min_minor min_patch < <(version_parts "${minimum}"); then return 1; fi
	if ((cur_major != min_major)); then ((cur_major > min_major)); return; fi
	if ((cur_minor != min_minor)); then ((cur_minor > min_minor)); return; fi
	((cur_patch >= min_patch))
}

official_version_from_tag() {
	local tag="$1"
	if [[ ${tag} =~ ^v?([0-9]+\.[0-9]+\.[0-9]+) ]]; then
		printf '%s\n' "${BASH_REMATCH[1]}"
		return 0
	fi
	return 1
}

select_highest_version_tag() {
	local best="" tag
	while IFS= read -r tag; do
		[[ -z ${tag} ]] && continue
		if [[ -z ${best} ]] || tag_is_newer_than "${tag}" "${best}"; then
			best="${tag}"
		fi
	done
	if [[ -n ${best} ]]; then
		printf '%s\n' "${best}"
	fi
	return 0
}

require_arg() {
	local option="$1" value="${2-}"
	if [[ -z ${value} || ${value} == --* ]]; then
		err "Missing value for ${option}"
		exit 1
	fi
}

# Read the existing profile before removing an App/CLI installation. This is a
# read-only migration check; no AWG preference is changed by the installer.
capture_awg_migration_state() {
	local tailscale_bin="" config=""
	tailscale_bin=$(type -P tailscale 2>/dev/null || true)
	[[ -n ${tailscale_bin} && ${tailscale_bin} == /* && -x ${tailscale_bin} ]] || return 0
	config=$("${tailscale_bin}" awg get 2>/dev/null || "${tailscale_bin}" amnezia-wg get 2>/dev/null || true)
	if [[ ${config} == *"<c>"* ]]; then
		LEGACY_CPS_COUNTER_DETECTED=true
	fi
}

show_awg_guidance() {
	local release_version="${VERSION}" supports_v3=false
	echo "🔧 Amnezia-WG Commands (awg = amnezia-wg):"
	if version_at_least "${release_version}" "${AWG_V3_MIN_VERSION}"; then
		supports_v3=true
		ok "AWG v3 is available; existing AWG v2 profiles remain supported."
		echo "  tailscale awg set               # Enter = generate AWG v3; choose 2 for AWG v2"
	else
		warn "This release predates AWG v3; install v${AWG_V3_MIN_VERSION} or newer for the v3 generator."
		echo "  tailscale awg set               # Configure the AWG version supported by this release"
	fi
	if [[ ${LEGACY_CPS_COUNTER_DETECTED} == true ]]; then
		if version_at_least "${release_version}" "${AWG_C_REMOVED_VERSION}"; then
			warn "Legacy CPS tag <c> was detected. It is unsupported by the selected release (v${AWG_C_REMOVED_VERSION}+); remove only <c> from i1-i5."
		else
			warn "Legacy CPS tag <c> was detected. This old release accepts it, but v${AWG_C_REMOVED_VERSION}+ does not."
		fi
	fi
	echo "  tailscale awg get               # Show the current profile and JSON"
	if [[ ${supports_v3} == true ]]; then
		echo "  tailscale awg validate          # Validate the current profile"
		echo "  tailscale awg sync              # Sync a compatible v2/v3 profile"
	else
		echo "  tailscale awg sync              # Sync a compatible AWG v2 profile"
	fi
	echo "  tailscale awg reset             # Disable AWG and use standard WireGuard"
}

# Note: Configuration backup removed as App/CLI variants use incompatible formats
# Users will need to re-authenticate after switching to CLI version

tailscale_system_extension_enabled() {
	if systemextensionsctl list 2>/dev/null | grep -i tailscale | grep -q "enabled"; then
		return 0
	fi
	return 1
}

tailscale_system_extension_pids() {
	/bin/ps -axo pid=,comm= 2>/dev/null | awk '
		{
			pid = $1
			$1 = ""
			sub(/^[[:space:]]+/, "")
			if (index($0, "/Library/SystemExtensions/") == 1 && index($0, "/io.tailscale.") > 0) print pid
		}
	' | sort -u
}

tailscale_system_extension_active() {
	if tailscale_system_extension_enabled; then
		return 0
	fi
	[[ -n $(tailscale_system_extension_pids || true) ]]
}

validate_tailscale_app_bundle_path() {
	if [[ -L ${ROLLBACK_APP_ORIGINAL_PATH} ]]; then
		err "${ROLLBACK_APP_ORIGINAL_PATH} is a symbolic link; refusing to follow or migrate an external App bundle"
		err "Replace it with a real App bundle, or remove the link explicitly, before retrying"
		return 1
	fi
}

# Function to check for App Store or Standalone Tailscale installation
check_app_conflict() {
	local has_app=false
	local app_type=""
	validate_tailscale_app_bundle_path || return 1

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
	if tailscale_system_extension_active; then
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
		echo "  • Temporarily move Tailscale.app aside while the CLI daemon is tested"
		echo "  • Install the CLI version with Amnezia-WG support"
		echo "  • You'll need to re-authenticate after installation"
		echo ""
		echo "If the CLI daemon fails, the installer can restore the App bundle."
		warn "Disabling a macOS System/Network Extension cannot be reversed automatically;"
		warn "after a rollback you may need to re-enable it in System Settings or reboot."
		echo ""

		local response
		if [[ ! -t 0 ]]; then
			# Running via pipe (curl | bash); read from controlling terminal to enable interaction
			if ! read -r -p "Do you want to remove the existing Tailscale and install CLI version? [y/N]: " response </dev/tty; then
				err "Cannot read confirmation from /dev/tty; no changes were made"
				return 1
			fi
		else
			read -r -p "Do you want to remove the existing Tailscale and install CLI version? [y/N]: " response
		fi
		response=${response:-N}

		case ${response} in
		[yY][eE][sS] | [yY])
			info "The App will be staged only after the new binaries pass validation"
			REMOVE_EXISTING_APP=true
			;;
		*)
			warn "Keeping Tailscale.app; CLI installation cancelled to avoid a network-extension conflict"
			return 1
			;;
		esac
	fi
}

# Return only processes whose executable identity is inside the App bundle.
# Do not match full command lines: backup/indexing tools may legitimately carry
# /Applications/Tailscale.app in an argument and must never be signalled.
tailscale_app_process_pids() {
	/bin/ps -axo pid=,comm= 2>/dev/null | awk -v prefix="${ROLLBACK_APP_ORIGINAL_PATH}/Contents/" '
		{
			pid = $1
			$1 = ""
			sub(/^[[:space:]]+/, "")
			if (index($0, prefix) == 1) print pid
		}
	' | sort -u
}

# Function to remove existing Tailscale installations
remove_existing_tailscale() {
	info "Removing existing Tailscale installation..."
	validate_tailscale_app_bundle_path || return 1

	# Force quit Tailscale app and ensure it's completely closed
	info "Stopping Tailscale application..."

	# Try graceful quit first
	osascript -e 'quit app "Tailscale"' 2>/dev/null || true
	sleep 3

	# Check only executable paths inside the bundle, never arbitrary command lines.
	local remaining_procs="" pid=""
	remaining_procs=$(tailscale_app_process_pids || true)
	if [[ -n ${remaining_procs} ]]; then
		warn "Tailscale app still running, force quitting..."
		osascript -e 'tell application "Tailscale" to quit' 2>/dev/null || true
		sleep 2
	fi

	remaining_procs=$(tailscale_app_process_pids || true)
	if [[ -n ${remaining_procs} ]]; then
		warn "Tailscale.app executables are still running; sending SIGTERM..."
		while IFS= read -r pid; do
			if [[ ${pid} =~ ^[0-9]+$ ]]; then
				${SUDO} kill -TERM "${pid}" 2>/dev/null || true
			fi
		done <<<"${remaining_procs}"
		sleep 2
	fi
	remaining_procs=$(tailscale_app_process_pids || true)
	if [[ -n ${remaining_procs} ]]; then
		warn "Tailscale.app executables ignored SIGTERM; sending SIGKILL..."
		while IFS= read -r pid; do
			if [[ ${pid} =~ ^[0-9]+$ ]]; then
				${SUDO} kill -KILL "${pid}" 2>/dev/null || true
			fi
		done <<<"${remaining_procs}"
		sleep 2
	fi
	remaining_procs=$(tailscale_app_process_pids || true)
	if [[ -n ${remaining_procs} ]]; then
		err "Tailscale processes are still running after SIGKILL; no App bundle was moved"
		return 1
	fi

	ok "All Tailscale.app processes stopped"

	# Remove system extensions first (critical for avoiding conflicts)
	info "Removing Tailscale system extensions..."
	local extension_found=false extension_was_enabled=false
	if tailscale_system_extension_enabled; then
		extension_was_enabled=true
	fi

	# Check if Tailscale system extension exists and is enabled
	if tailscale_system_extension_active; then
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
		# Check if we're running from a pipe (curl | bash). Do not silently
		# continue if there is no controlling terminal for the manual step.
		if [[ ! -t 0 ]]; then
			if ! read -r -p "Press Enter after you've disabled the Tailscale Network Extension..." response </dev/tty; then
				err "Cannot read confirmation from /dev/tty; installation stopped"
				return 1
			fi
		else
			read -r -p "Press Enter after you've disabled the Tailscale Network Extension..." response
		fi

		# Verify removal
		local attempts=0
		while [[ ${attempts} -lt 30 ]]; do
			if ! tailscale_system_extension_active; then
				ok "System extension successfully disabled"
				break
			fi
			echo -n "."
			sleep 2
			attempts=$((attempts + 1))
		done
		if [[ ${extension_was_enabled} == true ]] && ! tailscale_system_extension_enabled; then
			ROLLBACK_EXTENSION_WAS_DISABLED=true
		fi

		if [[ ${attempts} -eq 30 ]]; then
			err "System/Network Extension is still active; installation stopped to avoid a conflict"
			echo "Disable it or reboot macOS, then rerun the installer."
			return 1
		fi
	fi

	# Keep the Homebrew receipt until the new CLI daemon is healthy. That lets a
	# failed migration restore the App bundle without reconstructing cask state.
	if command -v brew >/dev/null 2>&1 && brew list --cask tailscale-app &>/dev/null; then
		ROLLBACK_APP_WAS_CASK=true
	fi

	# Stage the standalone/App Store bundle rather than deleting it. It stays in
	# the rollback directory until the replacement daemon passes its live check.
	if [[ -d ${ROLLBACK_APP_ORIGINAL_PATH} ]]; then
		if [[ -z ${ROLLBACK_DIR} || ! -d ${ROLLBACK_DIR} ]]; then
			err "Rollback directory is unavailable; refusing to move Tailscale.app"
			return 1
		fi
		ROLLBACK_APP_STAGED_PATH="${ROLLBACK_DIR}/Tailscale.app"
		info "Staging Tailscale.app for rollback..."
		if ! ${SUDO} mv "${ROLLBACK_APP_ORIGINAL_PATH}" "${ROLLBACK_APP_STAGED_PATH}"; then
			err "Could not stage Tailscale.app; no App bundle was deleted"
			return 1
		fi
		ROLLBACK_APP_STAGED=true
		if [[ -e ${ROLLBACK_APP_ORIGINAL_PATH} || ! -d ${ROLLBACK_APP_STAGED_PATH} ]]; then
			err "Tailscale.app staging could not be verified"
			return 1
		fi
		ok "Tailscale.app staged until the CLI daemon is healthy"
	fi

	info "Existing App installation is inactive and ready for rollback"

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
LAUNCHD_LABEL="com.tailscale.tailscaled"
LAUNCHD_PLIST="/Library/LaunchDaemons/${LAUNCHD_LABEL}.plist"
MIN_BINARY_SIZE=5242880

# Resolve the final file behind a command or launchd symlink without replacing
# the link itself. Homebrew relies on stable links in its bin directory; writing
# through the resolved target preserves that package-manager layout and makes
# rollback restore the same object that was replaced.
resolve_symlink_target() {
	local path="$1" link="" parent="" hops=0
	[[ -n ${path} ]] || return 1
	if [[ ${path} != /* ]]; then
		path="$(pwd -P)/${path}"
	fi
	while [[ -L ${path} ]]; do
		hops=$((hops + 1))
		if ((hops > 32)); then
			err "Too many symbolic links while resolving ${1}"
			return 1
		fi
		link=$(readlink "${path}") || return 1
		if [[ ${link} == /* ]]; then
			path="${link}"
		else
			parent=$(cd -P "$(dirname "${path}")" 2>/dev/null && pwd) || return 1
			path="${parent}/${link}"
		fi
	done
	parent=$(cd -P "$(dirname "${path}")" 2>/dev/null && pwd) || {
		printf '%s\n' "${path}"
		return 0
	}
	printf '%s/%s\n' "${parent}" "$(basename "${path}")"
}

validate_existing_native_target() {
	local target="$1" name="$2" file_type=""
	[[ -e ${target} ]] || return 0
	if [[ ! -f ${target} ]]; then
		err "Existing ${name} target is not a regular file: ${target}"
		return 1
	fi
	file_type=$(/usr/bin/file -b "${target}" 2>/dev/null || true)
	if [[ ! ${file_type} =~ Mach-O ]]; then
		err "Existing ${name} target is not a native Mach-O binary: ${target}"
		err "Custom command wrappers are never overwritten; move the wrapper out of PATH and retry"
		return 1
	fi
}

plist_daemon_path() {
	[[ -f ${LAUNCHD_PLIST} ]] || return 1
	# When both keys exist, launchd executes Program and treats
	# ProgramArguments[0] only as argv[0]. Fall back to argv[0] when Program is
	# omitted, matching launchd.plist semantics.
	/usr/libexec/PlistBuddy -c 'Print :Program' "${LAUNCHD_PLIST}" 2>/dev/null ||
		/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "${LAUNCHD_PLIST}" 2>/dev/null
}

# Determine install dir and current tailscaled path
detect_install_dir() {
	INSTALL_DIR="/usr/local/bin"

	local brew_prefix=""
	if command -v brew >/dev/null 2>&1; then
		brew_prefix=$(brew --prefix 2>/dev/null || true)
		if [[ -n ${brew_prefix} && -d "${brew_prefix}/bin" ]]; then
			INSTALL_DIR="${brew_prefix}/bin"
			return 0
		fi
	fi

	if [[ ${arch} == "arm64" && -d "/opt/homebrew/bin" ]]; then
		INSTALL_DIR="/opt/homebrew/bin"
	elif [[ -d "/usr/local/bin" ]]; then
		INSTALL_DIR="/usr/local/bin"
	elif [[ -d "/opt/homebrew/bin" ]]; then
		INSTALL_DIR="/opt/homebrew/bin"
	fi
}

detect_install_dir

resolve_install_targets() {
	local ts_entry="" tsd_entry="" plist_path="" resolved="" loaded_plist=""
	local loaded_program="" loaded_program_resolved="" plist_program_resolved=""
	validate_tailscale_app_bundle_path || return 1
	if service_is_loaded && [[ ! -f ${LAUNCHD_PLIST} ]]; then
		err "${LAUNCHD_LABEL} is loaded, but ${LAUNCHD_PLIST} is missing"
		err "Refusing to replace the daemon because its original launch arguments cannot be restored safely"
		return 1
	fi
	if service_is_loaded; then
		loaded_plist=$(launchd_job_plist_path || true)
		if [[ ${loaded_plist} != "${LAUNCHD_PLIST}" ]]; then
			err "${LAUNCHD_LABEL} was loaded from ${loaded_plist:-an unknown source}, not ${LAUNCHD_PLIST}"
			err "Refusing to replace it because the original launch job cannot be restored safely"
			return 1
		fi
	fi
	ts_entry=$(type -P tailscale 2>/dev/null || true)
	tsd_entry=$(type -P tailscaled 2>/dev/null || true)
	[[ -n ${ts_entry} && ( ${ts_entry} != /* || ! -x ${ts_entry} ) ]] && ts_entry=""
	[[ -n ${tsd_entry} && ( ${tsd_entry} != /* || ! -x ${tsd_entry} ) ]] && tsd_entry=""
	[[ -z ${ts_entry} ]] && ts_entry="${INSTALL_DIR}/tailscale"
	[[ -z ${tsd_entry} ]] && tsd_entry="${INSTALL_DIR}/tailscaled"

	if [[ -f "${LAUNCHD_PLIST}" ]]; then
		plist_path=$(plist_daemon_path || true)
		if [[ -z ${plist_path} ]]; then
			err "Could not read Program or ProgramArguments[0] from ${LAUNCHD_PLIST}"
			err "Refusing to rewrite an existing LaunchDaemon whose command cannot be restored safely"
			return 1
		fi
		if [[ ${plist_path} != /* || $(basename "${plist_path}") != "tailscaled" ]]; then
			err "Existing LaunchDaemon uses a wrapper instead of a tailscaled binary: ${plist_path}"
			err "Refusing to overwrite the wrapper; stop it and update ${LAUNCHD_PLIST} explicitly before retrying"
			return 1
		fi
		tsd_entry="${plist_path}"
		if service_is_loaded; then
			loaded_program=$(launchd_program_path || true)
			loaded_program_resolved=$(resolve_symlink_target "${loaded_program}" || true)
			plist_program_resolved=$(resolve_symlink_target "${plist_path}" || true)
			if [[ -z ${loaded_program_resolved} || ${loaded_program_resolved} != "${plist_program_resolved}" ]]; then
				err "The loaded launchd program (${loaded_program:-unknown}) does not match ${LAUNCHD_PLIST} (${plist_path})"
				err "Unload or repair the stale launch job before retrying"
				return 1
			fi
		fi
	fi
	resolved=$(resolve_symlink_target "${ts_entry}") || return 1
	if [[ ${resolved} == "${ROLLBACK_APP_ORIGINAL_PATH}/"* ]]; then
		if [[ ${REMOVE_EXISTING_APP} != true ]]; then
			err "The tailscale command resolves inside Tailscale.app, but App migration was not approved"
			return 1
		fi
		if [[ ! -L ${ts_entry} ]]; then
			err "The active tailscale executable is inside Tailscale.app rather than a replaceable command link"
			err "Remove that App directory from PATH and rerun the installer"
			return 1
		fi
		# Homebrew casks and standalone App installs commonly expose a command
		# symlink into Tailscale.app. Replace that link itself with the verified
		# CLI binary; never follow it and overwrite bytes inside the App bundle.
		warn "The tailscale command points inside Tailscale.app; the command link will be replaced during migration"
		TS_COMMAND_REPLACES_APP_LINK=true
		resolved="${ts_entry}"
	fi
	TS_PATH="${resolved}"
	TS_COMMAND_PATH="${ts_entry}"
	resolved=$(resolve_symlink_target "${tsd_entry}") || return 1
	if [[ ${resolved} == "${ROLLBACK_APP_ORIGINAL_PATH}/"* ]]; then
		warn "Ignoring tailscaled service binary inside Tailscale.app because the App bundle will be migrated"
		tsd_entry="${INSTALL_DIR}/tailscaled"
		resolved=$(resolve_symlink_target "${tsd_entry}") || return 1
		if [[ ${resolved} == "${ROLLBACK_APP_ORIGINAL_PATH}/"* ]]; then
			err "The fallback tailscaled command also resolves inside Tailscale.app; refusing to overwrite the App bundle"
			return 1
		fi
	fi
	TSD_PATH="${resolved}"
	TSD_LAUNCH_PATH="${tsd_entry}"
	export TS_PATH TS_COMMAND_PATH TSD_PATH TSD_LAUNCH_PATH
	if [[ ${ts_entry} != "${TS_PATH}" ]]; then
		info "tailscale command link: ${ts_entry} -> ${TS_PATH}"
	else
		info "tailscale -> ${TS_PATH}"
	fi
	if [[ ${TSD_LAUNCH_PATH} != "${TSD_PATH}" ]]; then
		info "tailscaled service link: ${TSD_LAUNCH_PATH} -> ${TSD_PATH}"
	else
		info "tailscaled -> ${TSD_PATH}"
	fi
}

ensure_tailscaled_is_managed() {
	local pids="" launchd_pid="" pid=""
	pids=$(running_tailscaled_pids)
	[[ -z ${pids} ]] && return 0
	if ! service_is_loaded; then
		err "A manually started tailscaled process is running outside ${LAUNCHD_LABEL}"
		err "Stop it yourself before retrying; the installer cannot reconstruct its arguments during rollback"
		return 1
	fi
	launchd_pid=$(launchd_tailscaled_pid || true)
	if [[ ! ${launchd_pid} =~ ^[0-9]+$ ]]; then
		err "tailscaled is running, but ${LAUNCHD_LABEL} does not report its PID"
		err "Stop the unmanaged process yourself before retrying"
		return 1
	fi
	while IFS= read -r pid; do
		[[ -z ${pid} ]] && continue
		if [[ ${pid} != "${launchd_pid}" ]]; then
			err "An additional unmanaged tailscaled process is running (PID ${pid})"
			err "Stop it yourself before retrying; only the launchd-managed daemon can be rolled back safely"
			return 1
		fi
	done <<<"${pids}"
}

service_is_loaded() {
	# Prefer system-domain checks for LaunchDaemons and fall back to local list.
	if launchctl print "system/${LAUNCHD_LABEL}" >/dev/null 2>&1 ||
		${SUDO} launchctl print "system/${LAUNCHD_LABEL}" >/dev/null 2>&1; then
		return 0
	fi
	if ${SUDO} launchctl list 2>/dev/null | grep -q "${LAUNCHD_LABEL}"; then
		return 0
	fi
	return 1
}

launchd_service_details() {
	launchctl print "system/${LAUNCHD_LABEL}" 2>/dev/null ||
		${SUDO} launchctl print "system/${LAUNCHD_LABEL}" 2>/dev/null
}

launchd_job_plist_path() {
	launchd_service_details | awk '$1 == "path" && $2 == "=" {print $3; exit}'
}

launchd_tailscaled_pid() {
	launchd_service_details | awk '$1 == "pid" && $2 == "=" {print $3; exit}'
}

launchd_program_path() {
	launchd_service_details | awk '$1 == "program" && $2 == "=" {$1=$2=""; sub(/^[[:space:]]+/, ""); print; exit}'
}

launchdaemon_matches_target() {
	local configured="" resolved=""
	configured=$(plist_daemon_path || true)
	[[ -n ${configured} ]] || return 1
	resolved=$(resolve_symlink_target "${configured}") || return 1
	[[ ${resolved} == "${TSD_PATH}" ]]
}

running_tailscaled_pids() {
	pgrep -x tailscaled 2>/dev/null || true
}

wait_for_tailscaled_stopped() {
	local attempts=0 max_attempts="${1:-10}"
	while [[ ${attempts} -lt ${max_attempts} ]]; do
		if [[ -z $(running_tailscaled_pids) ]] && ! service_is_loaded; then
			return 0
		fi
		sleep 1
		attempts=$((attempts + 1))
	done
	return 1
}

wait_for_tailscaled_started() {
	local attempts=0 max_attempts="${1:-10}" pid="" program="" resolved=""
	while [[ ${attempts} -lt ${max_attempts} ]]; do
		pid=$(launchd_tailscaled_pid || true)
		program=$(launchd_program_path || true)
		resolved=""
		if [[ -n ${program} ]]; then
			resolved=$(resolve_symlink_target "${program}" || true)
		fi
		if [[ ${pid} =~ ^[0-9]+$ ]] && ps -p "${pid}" -o pid= >/dev/null 2>&1 && [[ ${resolved} == "${TSD_PATH}" ]]; then
			return 0
		fi
		sleep 1
		attempts=$((attempts + 1))
	done
	return 1
}

stop_service() {
	if [[ -f "${LAUNCHD_PLIST}" ]] || service_is_loaded; then
		info "Stopping tailscaled (launchctl bootout/unload)..."
		${SUDO} launchctl bootout "system/${LAUNCHD_LABEL}" 2>/dev/null || true
		${SUDO} launchctl bootout system "${LAUNCHD_PLIST}" 2>/dev/null || true
		${SUDO} launchctl unload "${LAUNCHD_PLIST}" 2>/dev/null || true
	fi

	if wait_for_tailscaled_stopped 5; then
		return 0
	fi

	warn "tailscaled is still running after launchctl stop; sending SIGTERM..."
	${SUDO} pkill -TERM -x tailscaled 2>/dev/null || true
	if wait_for_tailscaled_stopped 5; then
		return 0
	fi

	warn "tailscaled did not exit cleanly; force killing stale daemon..."
	${SUDO} pkill -KILL -x tailscaled 2>/dev/null || true
	if wait_for_tailscaled_stopped 5; then
		ok "Stopped old tailscaled process"
		return 0
	fi

	err "Unable to unload the launchd job and stop tailscaled. Please reboot macOS and rerun the installer."
	return 1
}

write_launchdaemon_plist() {
	info "Writing LaunchDaemon configuration..."
	if ! cat <<PLIST | ${SUDO} tee "${LAUNCHD_PLIST}" >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.tailscale.tailscaled</string>
    <key>ProgramArguments</key>
    <array>
        <string>${TSD_LAUNCH_PATH}</string>
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
	then
		err "Could not write ${LAUNCHD_PLIST}"
		return 1
	fi
	if ! ${SUDO} chown root:wheel "${LAUNCHD_PLIST}" 2>/dev/null; then
		err "Could not set ownership on ${LAUNCHD_PLIST}"
		return 1
	fi
	if ! ${SUDO} chmod 0644 "${LAUNCHD_PLIST}"; then
		err "Could not set permissions on ${LAUNCHD_PLIST}"
		return 1
	fi
	ok "Wrote LaunchDaemon configuration"
}

load_service() {
	info "Starting tailscaled (launchctl bootstrap/load)..."
	if ! ${SUDO} launchctl bootstrap system "${LAUNCHD_PLIST}" 2>/dev/null; then
		${SUDO} launchctl load -w "${LAUNCHD_PLIST}" 2>/dev/null || return 1
	fi
	${SUDO} launchctl kickstart -k "system/${LAUNCHD_LABEL}" 2>/dev/null || true
}

rollback_install() {
	[[ ${ROLLBACK_AVAILABLE} == true ]] || return 0
	local rollback_failed=false service_stopped=false core_restore_failed=false current_link=""
	if stop_service; then
		service_stopped=true
	else
		err "Could not stop the replacement daemon during rollback"
		err "Skipping binary and LaunchDaemon restoration while tailscaled may still be running"
		rollback_failed=true
	fi
	if [[ ${service_stopped} == true ]]; then
		if [[ ${TS_COMMAND_REPLACES_APP_LINK} == true && -L ${ROLLBACK_TS_PATH} &&
			$(readlink "${ROLLBACK_TS_PATH}" 2>/dev/null || true) == "${ROLLBACK_TS_COMMAND_LINK}" ]]; then
			# The migration never detached the original App command link, so there
			# is no client binary change to restore at this path.
			:
		elif [[ ${ROLLBACK_TS_EXISTED} == true ]]; then
			if ! ${SUDO} install -m 0755 "${ROLLBACK_DIR}/tailscale" "${ROLLBACK_TS_PATH}" ||
				! cmp -s "${ROLLBACK_DIR}/tailscale" "${ROLLBACK_TS_PATH}"; then
				err "Could not restore the previous tailscale binary"
				rollback_failed=true
				core_restore_failed=true
			fi
		else
			if ! ${SUDO} rm -f -- "${ROLLBACK_TS_PATH}" || [[ -e ${ROLLBACK_TS_PATH} ]]; then
				err "Could not remove the newly installed tailscale binary"
				rollback_failed=true
				core_restore_failed=true
			fi
		fi
		if [[ ${ROLLBACK_TSD_EXISTED} == true ]]; then
			if ! ${SUDO} install -m 0755 "${ROLLBACK_DIR}/tailscaled" "${ROLLBACK_TSD_PATH}" ||
				! cmp -s "${ROLLBACK_DIR}/tailscaled" "${ROLLBACK_TSD_PATH}"; then
				err "Could not restore the previous tailscaled binary"
				rollback_failed=true
				core_restore_failed=true
			fi
		else
			if ! ${SUDO} rm -f -- "${ROLLBACK_TSD_PATH}" || [[ -e ${ROLLBACK_TSD_PATH} ]]; then
				err "Could not remove the newly installed tailscaled binary"
				rollback_failed=true
				core_restore_failed=true
			fi
		fi
		if [[ ${ROLLBACK_TS_COMMAND_WAS_SYMLINK} == true && -n ${TS_COMMAND_PATH} ]]; then
			current_link=$(readlink "${TS_COMMAND_PATH}" 2>/dev/null || true)
			if [[ ${current_link} != "${ROLLBACK_TS_COMMAND_LINK}" ]]; then
				if ! ${SUDO} rm -f -- "${TS_COMMAND_PATH}" ||
					! ${SUDO} ln -s "${ROLLBACK_TS_COMMAND_LINK}" "${TS_COMMAND_PATH}"; then
					err "Could not restore the previous tailscale command symlink"
					rollback_failed=true
					core_restore_failed=true
				fi
			fi
		fi
		if [[ ${ROLLBACK_PLIST_EXISTED} == true ]]; then
			if ! ${SUDO} cp -p "${ROLLBACK_DIR}/tailscaled.plist" "${LAUNCHD_PLIST}" ||
				! cmp -s "${ROLLBACK_DIR}/tailscaled.plist" "${LAUNCHD_PLIST}"; then
				err "Could not restore the previous LaunchDaemon plist"
				rollback_failed=true
				core_restore_failed=true
			fi
		else
			if ! ${SUDO} rm -f -- "${LAUNCHD_PLIST}" || [[ -e ${LAUNCHD_PLIST} ]]; then
				err "Could not remove the replacement LaunchDaemon plist"
				rollback_failed=true
				core_restore_failed=true
			fi
		fi
	fi

	# App bundle recovery is independent of daemon restoration. It is safe to put
	# the inactive bundle back even when the replacement daemon could not stop.
	if [[ ${ROLLBACK_APP_STAGED} == true && -n ${ROLLBACK_APP_STAGED_PATH} ]]; then
		if [[ -e ${ROLLBACK_APP_ORIGINAL_PATH} ]]; then
			err "Cannot restore Tailscale.app because ${ROLLBACK_APP_ORIGINAL_PATH} already exists"
			rollback_failed=true
		elif ${SUDO} mv "${ROLLBACK_APP_STAGED_PATH}" "${ROLLBACK_APP_ORIGINAL_PATH}" &&
			[[ -d ${ROLLBACK_APP_ORIGINAL_PATH} ]]; then
			ROLLBACK_APP_STAGED=false
			ok "Restored Tailscale.app"
		else
			err "Could not restore Tailscale.app from ${ROLLBACK_APP_STAGED_PATH}"
			rollback_failed=true
		fi
	fi
	if [[ ${service_stopped} == true && ${core_restore_failed} == false && ${ROLLBACK_SERVICE_WAS_LOADED} == true ]]; then
		if ! load_service || ! wait_for_tailscaled_started 10; then
			err "The previous LaunchDaemon could not be restarted"
			rollback_failed=true
		fi
	elif [[ ${service_stopped} == true && ${core_restore_failed} == true && ${ROLLBACK_SERVICE_WAS_LOADED} == true ]]; then
		warn "The previous LaunchDaemon was not restarted because its files were not fully restored"
	fi
	if [[ ${ROLLBACK_EXTENSION_WAS_DISABLED} == true ]]; then
		warn "macOS cannot automatically re-enable the System/Network Extension disabled during migration."
		warn "Open Tailscale.app and System Settings to re-enable it, or reboot if macOS requests it."
	fi
	if [[ ${ROLLBACK_CASK_RECEIPT_REMOVED} == true ]]; then
		warn "Tailscale.app was restored, but the Homebrew cask receipt cannot be recreated automatically."
		warn "Use Homebrew to reinstall/repair tailscale-app if you want it managed as a cask again."
	elif [[ ${ROLLBACK_CASK_CLEANUP_ATTEMPTED} == true ]]; then
		warn "Homebrew cask cleanup was interrupted or failed; verify its state with: brew list --cask tailscale-app"
	fi
	if [[ ${rollback_failed} == true ]]; then
		PRESERVE_ROLLBACK_TEMP=true
		err "Rollback was incomplete; recovery files are preserved in ${ROLLBACK_DIR}"
	fi
	ROLLBACK_AVAILABLE=false
}

reinstall_verified_binaries() {
	local actual_ts="" actual_tsd="" ts_version="" tsd_version="" current_link="" daemon_version=""
	if [[ -z ${VERIFIED_TS_SOURCE} || -z ${VERIFIED_TSD_SOURCE} ||
		! -f ${VERIFIED_TS_SOURCE} || ! -f ${VERIFIED_TSD_SOURCE} ]]; then
		err "Verified download sources are unavailable after Homebrew cleanup"
		return 1
	fi
	actual_ts=$(shasum -a 256 "${VERIFIED_TS_SOURCE}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
	actual_tsd=$(shasum -a 256 "${VERIFIED_TSD_SOURCE}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
	if [[ ${actual_ts} != "${VERIFIED_TS_SHA256}" || ${actual_tsd} != "${VERIFIED_TSD_SHA256}" ]]; then
		err "Verified download sources changed during App migration"
		return 1
	fi
	${SUDO} install -m 0755 "${VERIFIED_TS_SOURCE}" "${TS_PATH}" || return 1
	${SUDO} install -m 0755 "${VERIFIED_TSD_SOURCE}" "${TSD_PATH}" || return 1
	if [[ ${ROLLBACK_TS_COMMAND_WAS_SYMLINK} == true && ${TS_COMMAND_REPLACES_APP_LINK} != true ]]; then
		current_link=$(readlink "${TS_COMMAND_PATH}" 2>/dev/null || true)
		if [[ -z ${current_link} && ! -e ${TS_COMMAND_PATH} ]]; then
			${SUDO} ln -s "${ROLLBACK_TS_COMMAND_LINK}" "${TS_COMMAND_PATH}" || return 1
			current_link=$(readlink "${TS_COMMAND_PATH}" 2>/dev/null || true)
		fi
		if [[ ${current_link} != "${ROLLBACK_TS_COMMAND_LINK}" ]]; then
			err "Homebrew cleanup changed the tailscale command symlink unexpectedly"
			return 1
		fi
	fi
	if ! cmp -s "${VERIFIED_TS_SOURCE}" "${TS_PATH}" || ! cmp -s "${VERIFIED_TSD_SOURCE}" "${TSD_PATH}"; then
		err "Installed binaries differ from the verified downloads after Homebrew cleanup"
		return 1
	fi
	ts_version=$(binary_version "${TS_PATH}" tailscale | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
	tsd_version=$(binary_version "${TSD_PATH}" tailscaled | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
	if [[ ${ts_version} != "${EXPECTED_INSTALL_VERSION}" || ${tsd_version} != "${EXPECTED_INSTALL_VERSION}" ]]; then
		err "Binary version changed during Homebrew cask cleanup"
		return 1
	fi
	if ! wait_for_tailscaled_started 10; then
		err "The launchd daemon stopped during Homebrew cask cleanup"
		return 1
	fi
	daemon_version=$(live_daemon_version || true)
	if [[ ${daemon_version} != "${EXPECTED_INSTALL_VERSION}" ]]; then
		err "Live daemon verification failed after Homebrew cask cleanup"
		return 1
	fi
}

finalize_app_migration() {
	if [[ ${ROLLBACK_APP_WAS_CASK} == true ]]; then
		info "Removing the inactive Homebrew cask receipt..."
		ROLLBACK_CASK_CLEANUP_ATTEMPTED=true
		brew uninstall --cask --force tailscale-app 2>/dev/null || true
		if brew list --cask tailscale-app &>/dev/null; then
			err "Homebrew cask cleanup failed; restoring the previous App/CLI installation"
			return 1
		fi
		ROLLBACK_APP_WAS_CASK=false
		ROLLBACK_CASK_RECEIPT_REMOVED=true
		# The cask uninstall stanza deletes /usr/local/bin/tailscale. Restore both
		# authenticated AWG binaries and recheck the live daemon before committing
		# the App migration.
		if ! reinstall_verified_binaries; then
			err "Could not restore verified AWG binaries after Homebrew cask cleanup"
			return 1
		fi
		ok "Homebrew cask removed and AWG binaries reverified"
	fi
	# All failure-prone migration work is complete. From this point the verified
	# CLI installation is the committed state; an interrupt during App deletion
	# must not roll the binaries back while restoring a partially deleted bundle.
	ROLLBACK_AVAILABLE=false
	if [[ ${ROLLBACK_APP_STAGED} == true && -n ${ROLLBACK_APP_STAGED_PATH} ]]; then
		info "The CLI daemon is healthy; removing the staged Tailscale.app bundle..."
		ROLLBACK_APP_STAGED=false
		PRESERVE_ROLLBACK_TEMP=true
		if ${SUDO} rm -rf -- "${ROLLBACK_APP_STAGED_PATH}" && [[ ! -e ${ROLLBACK_APP_STAGED_PATH} ]]; then
			PRESERVE_ROLLBACK_TEMP=false
		else
			warn "Remaining inactive App bundle data is preserved at ${ROLLBACK_APP_STAGED_PATH}; it may be incomplete"
		fi
	fi
}

live_version_mismatch_detected() {
	local tailscale_bin="${TS_PATH-}" status_output=""
	if [[ ! -x "${tailscale_bin}" ]]; then
		tailscale_bin=$(type -P tailscale 2>/dev/null || true)
	fi
	[[ -z ${tailscale_bin} ]] && return 1

	status_output=$("${tailscale_bin}" status 2>&1 || true)
	if printf '%s\n' "${status_output}" | grep -q 'client version .* != tailscaled server version'; then
		printf '%s\n' "${status_output}" | grep 'client version .* != tailscaled server version' | head -n1
		return 0
	fi
	return 1
}

live_daemon_version() {
	local output=""
	[[ -x ${TS_PATH-} ]] || return 1
	output=$("${TS_PATH}" version --daemon 2>/dev/null) || return 1
	printf '%s\n' "${output}" | awk '/^Daemon:/ {print $2; exit}' | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1
}

start_service() {
	local live_mismatch="" expected_version="" daemon_version=""

	stop_service || return 1

	# Ensure directories exist
	if ! ${SUDO} mkdir -p /var/lib/tailscale /var/run; then
		err "Could not create tailscaled state/runtime directories"
		return 1
	fi
	if [[ ! -f "${LAUNCHD_PLIST}" ]] || ! launchdaemon_matches_target; then
		if [[ -f "${LAUNCHD_PLIST}" ]]; then
			warn "Existing LaunchDaemon points to a different or missing daemon; rewriting it for ${TSD_LAUNCH_PATH}"
		fi
		if ! write_launchdaemon_plist; then
			return 1
		fi
	else
		info "Preserving existing LaunchDaemon configuration"
	fi

	if ! load_service; then
		warn "tailscaled service may not have started properly"
		echo "You can manually start it with: sudo launchctl bootstrap system ${LAUNCHD_PLIST}"
		return 1
	fi

	# Verify service is running
	if wait_for_tailscaled_started 10; then
		ok "tailscaled service started successfully"
	else
		warn "tailscaled service may not have started properly"
		echo "You can manually start it with: sudo launchctl bootstrap system ${LAUNCHD_PLIST}"
		echo "Or reboot your Mac and retry if the daemon is still using the old binary."
		return 1
	fi

	if live_mismatch=$(live_version_mismatch_detected); then
		warn "Live client/daemon version mismatch detected: ${live_mismatch}"
		info "Retrying tailscaled restart once..."
		stop_service || return 1
		load_service || return 1
		if ! wait_for_tailscaled_started 10; then
			err "tailscaled did not start after retry. Please reboot macOS and rerun the installer."
			return 1
		fi
		if live_mismatch=$(live_version_mismatch_detected); then
			err "Live daemon still reports an old version: ${live_mismatch}"
			echo "Please reboot macOS to clear the old daemon process, then run 'tailscale status' again."
			return 1
		fi
		ok "Live client and daemon versions no longer report a mismatch"
	fi

	expected_version=$(official_version_from_tag "${VERSION}" || true)
	daemon_version=$(live_daemon_version || true)
	if [[ -z ${expected_version} || ${daemon_version} != "${expected_version}" ]]; then
		err "Live daemon version check failed: expected ${expected_version:-unknown}, got ${daemon_version:-unknown}"
		return 1
	fi
	ok "Live launchd daemon verified at version ${daemon_version}"
}

download_file() {
	local url="$1" output="$2"
	curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 "${url}" -o "${output}"
}

verify_downloaded_binary() {
	local binary_path="$1" binary_name="$2" file_size file_type
	if [[ ! -f "${binary_path}" ]]; then
		err "Downloaded ${binary_name} binary not found"
		return 1
	fi

	file_size=$(wc -c <"${binary_path}" | tr -d '[:space:]')
	if [[ -z ${file_size} || ${file_size} -lt ${MIN_BINARY_SIZE} ]]; then
		err "Downloaded ${binary_name} binary is too small (${file_size:-0} bytes)"
		return 1
	fi

	if command -v file >/dev/null 2>&1; then
		file_type=$(file "${binary_path}" 2>/dev/null || true)
		if [[ ! ${file_type} =~ Mach-O ]]; then
			err "Downloaded ${binary_name} is not a Mach-O executable: ${file_type:-unknown}"
			return 1
		fi
		case ${arch} in
		amd64)
			if [[ ! ${file_type} =~ x86_64 ]]; then
				err "Downloaded ${binary_name} binary is not Intel/x86_64: ${file_type}"
				return 1
			fi
			;;
		arm64)
			if [[ ! ${file_type} =~ arm64 ]]; then
				err "Downloaded ${binary_name} binary is not Apple Silicon/arm64: ${file_type}"
				return 1
			fi
			;;
		esac
	fi
}

release_asset_sha256() {
	local metadata="$1" wanted="$2"
	printf '%s\n' "${metadata}" | awk -v wanted="${wanted}" '
		match($0, /"name"[[:space:]]*:[[:space:]]*"[^"]*"/) {
			value = substr($0, RSTART, RLENGTH)
			sub(/^[^:]*:[[:space:]]*"/, "", value)
			sub(/"$/, "", value)
			asset = value
		}
		match($0, /"digest"[[:space:]]*:[[:space:]]*"sha256:[0-9a-fA-F]+"/) {
			value = substr($0, RSTART, RLENGTH)
			sub(/^.*sha256:/, "", value)
			sub(/"$/, "", value)
			if (asset == wanted) {
				print tolower(value)
				exit
			}
		}
	'
}

fetch_api_url() {
	local api_url="$1" response=""
	response=$(curl -fsSL --max-time 20 "${api_url}" 2>/dev/null || true)
	if [[ -z ${response} && -n ${MIRROR_PREFIX} ]]; then
		response=$(curl -fsSL --max-time 20 "${MIRROR_PREFIX}/${api_url}" 2>/dev/null || true)
	fi
	[[ -n ${response} ]] || return 1
	printf '%s\n' "${response}"
}

fetch_release_metadata() {
	curl -fsSL --max-time 20 "https://api.github.com/repos/${REPO}/releases/tags/${VERSION}" 2>/dev/null
}

verify_release_digest() {
	local file="$1" asset="$2" metadata="$3" expected="" actual=""
	expected=$(release_asset_sha256 "${metadata}" "${asset}" || true)
	if [[ -z ${expected} ]]; then
		warn "No GitHub SHA-256 digest is published for ${asset}; falling back to Mach-O, architecture, and version validation"
		return 0
	fi
	actual=$(shasum -a 256 "${file}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
	if [[ ${actual} != "${expected}" ]]; then
		err "SHA-256 mismatch for ${asset}"
		return 1
	fi
	ok "SHA-256 verified: ${asset}"
}

binary_version() {
	local binary_path="$1" binary_name="$2" version=""
	case ${binary_name} in
	tailscale)
		version=$("${binary_path}" version 2>/dev/null | head -n1 || true)
		;;
	tailscaled)
		version=$("${binary_path}" --version 2>/dev/null | head -n1 || true)
		;;
	esac
	printf '%s\n' "${version:-unknown}"
}

install_binaries() {
	if [[ ${VERSION} == "latest" ]]; then
		info "Fetching latest release tag..."
		local tag
		if [[ ${PRE_RELEASE} == true ]]; then
			local response
			response=$(fetch_api_url "https://api.github.com/repos/${REPO}/releases?per_page=100")
			tag=$(printf '%s\n' "${response}" | extract_release_tags_by_prerelease "true" | select_highest_version_tag)
			if [[ -z ${tag} ]]; then
				warn "No pre-release found, falling back to latest stable"
				tag=$(printf '%s\n' "${response}" | extract_release_tags_by_prerelease "false" | select_highest_version_tag)
			fi
		else
			tag=$(fetch_api_url "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -n1 || true)
		fi
		[[ -z ${tag} ]] && {
			err "Failed to resolve latest release"
			exit 1
		}
		VERSION="${tag}"
		if [[ ${PRE_RELEASE} == true ]]; then
			info "Latest version (pre-release): ${VERSION}"
		else
			info "Latest version: ${VERSION}"
		fi
	fi

	local base_url="https://github.com/${REPO}/releases/download/${VERSION}"
	if [[ -n ${MIRROR_PREFIX} ]]; then
		base_url="${MIRROR_PREFIX}/https://github.com/${REPO}/releases/download/${VERSION}"
		info "Using mirror for downloads: ${MIRROR_PREFIX}"
	fi

	local ts="tailscale-${platform}"
	local tsd="tailscaled-${platform}"
	local tmp metadata="" expected_version="" ts_version="" tsd_version=""
	tmp=$(mktemp -d)
	TEMP_DIRS+=("${tmp}")
	info "Downloading ${ts}"
	download_file "${base_url}/${ts}" "${tmp}/tailscale"
	info "Downloading ${tsd}"
	download_file "${base_url}/${tsd}" "${tmp}/tailscaled"
	verify_downloaded_binary "${tmp}/tailscale" tailscale
	verify_downloaded_binary "${tmp}/tailscaled" tailscaled

	# Never execute downloaded code before checking a digest from GitHub's
	# directly reached release metadata when the release provides one.
	metadata=$(fetch_release_metadata || true)
	if [[ -n ${metadata} ]]; then
		verify_release_digest "${tmp}/tailscale" "${ts}" "${metadata}"
		verify_release_digest "${tmp}/tailscaled" "${tsd}" "${metadata}"
	else
		warn "Direct GitHub release metadata is unavailable; falling back to Mach-O, architecture, and version validation"
	fi
	chmod +x "${tmp}/tailscale" "${tmp}/tailscaled"

	expected_version=$(official_version_from_tag "${VERSION}")
	ts_version=$(binary_version "${tmp}/tailscale" tailscale | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
	tsd_version=$(binary_version "${tmp}/tailscaled" tailscaled | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
	if [[ -z ${expected_version} || ${ts_version} != "${expected_version}" || ${tsd_version} != "${expected_version}" ]]; then
		err "Downloaded binary version mismatch: expected ${expected_version:-unknown}, tailscale=${ts_version:-unknown}, tailscaled=${tsd_version:-unknown}"
		return 1
	fi
	VERIFIED_TS_SOURCE="${tmp}/tailscale"
	VERIFIED_TSD_SOURCE="${tmp}/tailscaled"
	VERIFIED_TS_SHA256=$(shasum -a 256 "${VERIFIED_TS_SOURCE}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
	VERIFIED_TSD_SHA256=$(shasum -a 256 "${VERIFIED_TSD_SOURCE}" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
	EXPECTED_INSTALL_VERSION="${expected_version}"

	ok "Downloaded binaries passed Mach-O, architecture, and version validation"

	resolve_install_targets
	if ! validate_existing_native_target "${TS_PATH}" tailscale || ! validate_existing_native_target "${TSD_PATH}" tailscaled; then
		return 1
	fi
	ensure_tailscaled_is_managed

	local backup_dir="${tmp}/backup"
	mkdir -p "${backup_dir}"
	ROLLBACK_TS_PATH="${TS_PATH}"
	ROLLBACK_TSD_PATH="${TSD_PATH}"
	ROLLBACK_DIR="${backup_dir}"
	ROLLBACK_TEMP_DIR="${tmp}"
	PRESERVE_ROLLBACK_TEMP=false
	ROLLBACK_TS_EXISTED=false
	ROLLBACK_TSD_EXISTED=false
	ROLLBACK_PLIST_EXISTED=false
	ROLLBACK_SERVICE_WAS_LOADED=false
	ROLLBACK_APP_STAGED=false
	ROLLBACK_APP_STAGED_PATH=""
	ROLLBACK_APP_WAS_CASK=false
	ROLLBACK_EXTENSION_WAS_DISABLED=false
	ROLLBACK_CASK_RECEIPT_REMOVED=false
	ROLLBACK_CASK_CLEANUP_ATTEMPTED=false
	ROLLBACK_TS_COMMAND_WAS_SYMLINK=false
	ROLLBACK_TS_COMMAND_LINK=""
	TS_COMMAND_REPLACES_APP_LINK=false
	if [[ -L ${TS_COMMAND_PATH} ]]; then
		ROLLBACK_TS_COMMAND_LINK=$(readlink "${TS_COMMAND_PATH}")
		ROLLBACK_TS_COMMAND_WAS_SYMLINK=true
		if [[ $(resolve_symlink_target "${TS_COMMAND_PATH}" || true) == "${ROLLBACK_APP_ORIGINAL_PATH}/"* ]]; then
			TS_COMMAND_REPLACES_APP_LINK=true
		fi
	fi
	if [[ -e ${TS_PATH} ]]; then
		${SUDO} cp -p "${TS_PATH}" "${backup_dir}/tailscale"
		ROLLBACK_TS_EXISTED=true
	fi
	if [[ -e ${TSD_PATH} ]]; then
		${SUDO} cp -p "${TSD_PATH}" "${backup_dir}/tailscaled"
		ROLLBACK_TSD_EXISTED=true
	fi
	if [[ -f ${LAUNCHD_PLIST} ]]; then
		${SUDO} cp -p "${LAUNCHD_PLIST}" "${backup_dir}/tailscaled.plist"
		ROLLBACK_PLIST_EXISTED=true
	fi
	if service_is_loaded; then
		ROLLBACK_SERVICE_WAS_LOADED=true
	fi
	ROLLBACK_AVAILABLE=true

	if ! stop_service; then
		err "Unable to stop the existing tailscaled service; no binaries were replaced"
		rollback_install
		return 1
	fi
	if [[ ${TS_COMMAND_REPLACES_APP_LINK} == true && -L ${TS_PATH} ]]; then
		if ! ${SUDO} rm -f -- "${TS_PATH}" || [[ -e ${TS_PATH} || -L ${TS_PATH} ]]; then
			err "Could not detach the tailscale command link from Tailscale.app"
			rollback_install
			return 1
		fi
	fi

	${SUDO} mkdir -p "$(dirname "${TS_PATH}")" "$(dirname "${TSD_PATH}")"
	info "Installing to ${TS_PATH}"
	if ! ${SUDO} install -m 0755 "${tmp}/tailscale" "${TS_PATH}"; then
		err "Failed to install tailscale; restoring the previous installation"
		rollback_install
		return 1
	fi
	info "Installing to ${TSD_PATH}"
	if ! ${SUDO} install -m 0755 "${tmp}/tailscaled" "${TSD_PATH}"; then
		err "Failed to install tailscaled; restoring the previous installation"
		rollback_install
		return 1
	fi

	ts_version=$(binary_version "${TS_PATH}" tailscale | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
	tsd_version=$(binary_version "${TSD_PATH}" tailscaled | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
	if [[ ${ts_version} != "${expected_version}" || ${tsd_version} != "${expected_version}" ]]; then
		err "Installed binary version mismatch; restoring the previous installation"
		rollback_install
		return 1
	fi

	if [[ ${REMOVE_EXISTING_APP} == true ]] && ! remove_existing_tailscale; then
		err "The conflicting App installation could not be removed; restoring CLI binaries"
		rollback_install
		return 1
	fi

	ok "Binaries installed and verified: tailscale=${ts_version}, tailscaled=${tsd_version}"
}

# Comprehensive uninstall function
uninstall_all() {
	warn "Uninstalling Tailscale (all variants and configurations)..."
	validate_tailscale_app_bundle_path || return 1

	# Log out while the local API is still reachable. A disconnected or already
	# logged-out node is harmless here, so these control-plane calls are best effort.
	if command -v tailscale &>/dev/null && tailscale status &>/dev/null; then
		tailscale logout 2>/dev/null || tailscale down 2>/dev/null || true
	fi

	# Stop services first
	if ! stop_service; then
		err "Could not stop tailscaled; uninstall aborted before removing binaries, the App, or state"
		return 1
	fi
	osascript -e 'quit app "Tailscale"' 2>/dev/null || true
	sleep 2
	if [[ -n $(tailscale_app_process_pids || true) ]]; then
		err "Tailscale.app is still running; quit it and rerun --uninstall"
		return 1
	fi

	local cleanup_failed=false
	local extension_pending=false

	# Let Homebrew remove its receipts before cleaning any leftovers manually.
	if command -v brew &>/dev/null; then
		if brew list --formula tailscale &>/dev/null; then
			info "Removing Homebrew Tailscale..."
			if ! brew uninstall tailscale || brew list --formula tailscale &>/dev/null; then
				err "Homebrew could not remove the tailscale formula cleanly"
				cleanup_failed=true
			fi
		fi

		if brew list --cask tailscale-app &>/dev/null; then
			info "Removing Homebrew Tailscale Cask..."
			if ! brew uninstall --cask tailscale-app || brew list --cask tailscale-app &>/dev/null; then
				err "Homebrew could not remove the tailscale-app cask cleanly"
				cleanup_failed=true
			fi
		fi
	fi
	if [[ ${cleanup_failed} == true ]]; then
		err "Homebrew removal failed; manual App/binary/state removal was not attempted"
		return 1
	fi

	# Remove Standalone Tailscale.app if present
	if [[ -d "/Applications/Tailscale.app" || -L "/Applications/Tailscale.app" ]]; then
		info "Removing Tailscale.app..."
		if ${SUDO} rm -rf -- "/Applications/Tailscale.app"; then
			ok "Removed Tailscale.app"
		else
			err "Could not remove Tailscale.app"
			cleanup_failed=true
		fi
	fi

	# System extensions are managed by macOS/SIP and must not be removed by
	# deleting /Library/SystemExtensions directly.
	if systemextensionsctl list 2>/dev/null | grep -i tailscale | grep -q "enabled"; then
		warn "A Tailscale system extension is still enabled. Disable it in System Settings and reboot if macOS requests it."
		extension_pending=true
	fi

	# Remove binaries from common locations
	for binary in tailscale tailscaled; do
		for path in "/usr/local/bin/${binary}" "/opt/homebrew/bin/${binary}"; do
			if [[ -e ${path} || -L ${path} ]]; then
				if ${SUDO} rm -f -- "${path}"; then
					ok "Removed ${path}"
				else
					err "Could not remove ${path}"
					cleanup_failed=true
				fi
			fi
		done
	done

	# Remove LaunchDaemon plist
	if [[ -e ${LAUNCHD_PLIST} || -L ${LAUNCHD_PLIST} ]]; then
		info "Removing LaunchDaemon..."
		if ${SUDO} rm -f -- "${LAUNCHD_PLIST}"; then
			ok "Removed LaunchDaemon plist"
		else
			err "Could not remove LaunchDaemon plist"
			cleanup_failed=true
		fi
	fi

	# Remove state and configuration directories
	for dir in "/var/lib/tailscale" "/Library/Tailscale" "/var/run/tailscale"; do
		if [[ -e ${dir} || -L ${dir} ]]; then
			if ${SUDO} rm -rf -- "${dir}"; then
				ok "Removed directory ${dir}"
			else
				err "Could not remove directory ${dir}"
				cleanup_failed=true
			fi
		fi
	done

	# Remove user preference files
	for user_dir in /Users/*/Library/Preferences/com.tailscale.ipn.macos.plist; do
		if [[ -e ${user_dir} || -L ${user_dir} ]]; then
			if ${SUDO} rm -f -- "${user_dir}"; then
				ok "Removed user preferences ${user_dir}"
			else
				err "Could not remove user preferences ${user_dir}"
				cleanup_failed=true
			fi
		fi
	done

	if [[ ${cleanup_failed} == true ]]; then
		err "Tailscale uninstall is incomplete; review the errors above and remove the remaining artifacts manually"
		return 1
	fi

	if [[ ${extension_pending} == true ]]; then
		warn "Tailscale files were removed, but macOS still reports a Tailscale system extension pending manual disable/reboot"
	else
		ok "Tailscale uninstalled (artifacts removed)"
	fi
	echo ""
	echo "Note: If you had custom network configurations, please review them manually."
	echo "A reboot may be required for complete cleanup of system extensions and network interfaces."
}

usage() {
	echo ""
	ok "Installation completed successfully! 🎉"
	echo ""
	echo "  tailscale up                    # Connect to your network (re-auth required)"
	show_awg_guidance
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
	echo "🔧 macOS Installer (Amnezia-WG v2/v3)"

	# Parse arguments
	local ACTION="install"
	while [[ $# -gt 0 ]]; do
		case $1 in
		--mirror)
			require_arg "$1" "${2-}"
			MIRROR_PREFIX="${2%/}"
			info "Using mirror: ${MIRROR_PREFIX}"
			shift 2
			;;
		--version)
			require_arg "$1" "${2-}"
			VERSION="$2"
			shift 2
			;;
		--pre-release)
			PRE_RELEASE=true
			shift
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
  --version TAG      Use specific GitHub release tag (e.g. v1.102.2)
  --pre-release     Install the latest pre-release version from GitHub
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
			err "Unknown option: $1"
			return 1
			;;
		esac
		done
	if [[ ${ACTION} != "uninstall" && ${VERSION} != "latest" ]] && ! official_version_from_tag "${VERSION}" >/dev/null; then
		err "Invalid release tag: ${VERSION}; expected vMAJOR.MINOR.PATCH"
		return 1
	fi
	if [[ $(uname -s) != "Darwin" ]]; then
		err "This installer only supports macOS; no packages, binaries, Apps, or state were changed"
		return 1
	fi
	validate_tailscale_app_bundle_path || return 1

	check_root
	capture_awg_migration_state

	if [[ ${ACTION} == "uninstall" ]]; then
		uninstall_all
		return
	fi
	# Refuse to install a conflicting CLI service unless the user explicitly
	# approves migration away from Tailscale.app.
	if ! check_app_conflict; then
		exit 1
	fi

	install_binaries
	if ! start_service; then
		err "tailscaled failed to start; restoring the previous CLI/service installation"
		rollback_install
		exit 1
	fi
	if ! finalize_app_migration; then
		err "App migration could not be finalized; restoring the previous installation"
		rollback_install
		exit 1
	fi
	ROLLBACK_AVAILABLE=false
	usage
}

main "$@"
