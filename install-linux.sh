#!/usr/bin/env bash
# Linux installer: replace official Tailscale with AWG v2/v3-enabled binaries
# Usage: curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash

set -euo pipefail

# Constants
readonly REPO="LiuTangLei/tailscale"
readonly INSTALL_DIR="/usr/local/bin"
readonly AWG_C_REMOVED_VERSION="1.98.1"
readonly AWG_V3_MIN_VERSION="1.102.2"

# Colors
# shellcheck disable=SC2034 # Expanded indirectly by log() via ${!1}.
readonly R='\033[31m' G='\033[32m' Y='\033[33m' B='\033[34m' N='\033[0m'
log() { echo -e "${!1}[${1}]${N} $2"; }

# Small helpers
has_cmd() { command -v "$1" &>/dev/null; }
systemd_available() {
	has_cmd systemctl || return 1
	# A systemctl binary can be present in containers, WSL, or OpenRC systems
	# without systemd being the active service manager.
	[[ -d /run/systemd/system ]] || return 1
	local init_name=""
	if [[ -r /proc/1/comm ]]; then
		read -r init_name </proc/1/comm || true
		[[ ${init_name} == "systemd" ]] || return 1
	fi
	systemctl show-environment >/dev/null 2>&1
}

has_unit() {
	systemd_available || return 1
	local load_state=""
	load_state=$(systemctl show -p LoadState "$1" 2>/dev/null || true)
	[[ ${load_state} == "LoadState=loaded" || ${load_state} == "LoadState=masked" ]]
}

openrc_available() {
	has_cmd rc-service && has_cmd rc-update && has_cmd rc-status &&
		{ [[ -r /run/openrc/softlevel ]] || [[ -r /lib/rc/init.d/softlevel ]]; } &&
		rc-status --runlevel >/dev/null 2>&1
}

openrc_service_name() {
	# Upstream packages have used both names. Prefer the daemon-named service
	# when both are present, matching cmd/tailscaled/tailscaled.openrc.
	if [[ -x /etc/init.d/tailscaled ]]; then
		printf '%s\n' "tailscaled"
	elif [[ -x /etc/init.d/tailscale ]]; then
		printf '%s\n' "tailscale"
	else
		return 1
	fi
}

has_openrc_service() { openrc_available && openrc_service_name >/dev/null; }

openrc_service_runlevels() {
	local service_name="$1" output=""
	if ! output=$(rc-update show 2>/dev/null); then
		return 2
	fi
	awk -v wanted="${service_name}" '
		$1 == wanted {
			for (i = 3; i <= NF; i++) {
				if (!seen[$i]++) print $i
			}
		}
	' <<<"${output}"
}

openrc_service_enabled() {
	local runlevels="" status=0
	if runlevels=$(openrc_service_runlevels "$1"); then
		if [[ -n ${runlevels} ]]; then
			return 0
		fi
		return 1
	else
		status=$?
		return "${status}"
	fi
}

remove_openrc_service_from_runlevels() {
	local service_name="$1" runlevels="" runlevel="" status=0 remove_failed=false
	if runlevels=$(openrc_service_runlevels "${service_name}"); then
		:
	else
		status=$?
		return "${status}"
	fi
	while IFS= read -r runlevel; do
		[[ -n ${runlevel} ]] || continue
		if ! ${SUDO} rc-update del "${service_name}" "${runlevel}"; then
			remove_failed=true
		fi
	done <<<"${runlevels}"
	[[ ${remove_failed} == false ]]
}

validate_existing_service_command() {
	local exec_start="" openrc_name=""
	if has_unit tailscaled.service; then
		exec_start=$(systemctl show -p ExecStart tailscaled 2>/dev/null | sed -n 's/.*path=\([^; ][^; ]*\).*/\1/p' | head -n1 || true)
		[[ -z ${exec_start} ]] && exec_start=$(systemctl cat tailscaled 2>/dev/null | grep '^ExecStart=' | sed 's/^ExecStart=\([^ ][^ ]*\).*/\1/' | head -n1 || true)
		if [[ -z ${exec_start} ]]; then
			log R "Could not determine tailscaled.service ExecStart safely; no packages were changed"
			return 1
		fi
		if [[ ${exec_start} != /* || ${exec_start##*/} != "tailscaled" ]]; then
			log R "tailscaled.service uses a custom wrapper (${exec_start}); no packages were changed"
			return 1
		fi
	elif has_openrc_service; then
		openrc_name=$(openrc_service_name) || return 1
		exec_start=$(awk -F= '$1 ~ /^[[:space:]]*command[[:space:]]*$/ { value = $0; sub(/^[^=]*=[[:space:]]*/, "", value); gsub(/"/, "", value); print value; exit }' "/etc/init.d/${openrc_name}" 2>/dev/null || true)
		if [[ -z ${exec_start} ]]; then
			log R "Could not determine OpenRC ${openrc_name} command safely; no packages were changed"
			return 1
		fi
		if [[ ${exec_start} != /* || ${exec_start##*/} != "tailscaled" ]]; then
			log R "OpenRC ${openrc_name} uses a custom wrapper (${exec_start}); no packages were changed"
			return 1
		fi
	fi
	return 0
}

running_tailscaled_pids() {
	if has_cmd pgrep; then
		${SUDO} pgrep -x tailscaled 2>/dev/null || true
		return 0
	fi
	if has_cmd pidof; then
		${SUDO} pidof tailscaled 2>/dev/null | tr ' ' '\n' || true
		return 0
	fi
	local comm_file="" comm="" pid=""
	for comm_file in /proc/[0-9]*/comm; do
		[[ -r ${comm_file} ]] || continue
		read -r comm <"${comm_file}" || continue
		if [[ ${comm} == "tailscaled" ]]; then
			pid=${comm_file#/proc/}
			printf '%s\n' "${pid%/comm}"
		fi
	done
}

tailscaled_process_running() {
	[[ -n $(running_tailscaled_pids) ]]
}

wait_for_tailscaled_exit() {
	local attempts=0 max_attempts="${1:-10}"
	while ((attempts < max_attempts)); do
		if ! tailscaled_process_running; then
			return 0
		fi
		sleep 1
		attempts=$((attempts + 1))
	done
	return 1
}

terminate_unmanaged_tailscaled() {
	local pids="" pid=""
	pids=$(running_tailscaled_pids)
	[[ -z ${pids} ]] && return 0
	log Y "Stopping unmanaged tailscaled process(es): $(printf '%s' "${pids}" | tr '\n' ' ')"
	while IFS= read -r pid; do
		[[ ${pid} =~ ^[0-9]+$ ]] || continue
		${SUDO} kill -TERM "${pid}" 2>/dev/null || true
	done <<<"${pids}"
	if wait_for_tailscaled_exit 10; then
		return 0
	fi
	log Y "tailscaled did not exit after SIGTERM; sending SIGKILL"
	pids=$(running_tailscaled_pids)
	while IFS= read -r pid; do
		[[ ${pid} =~ ^[0-9]+$ ]] || continue
		${SUDO} kill -KILL "${pid}" 2>/dev/null || true
	done <<<"${pids}"
	wait_for_tailscaled_exit 5
}

tailscaled_service_active() {
	local openrc_name=""
	if has_unit tailscaled.service; then
		systemctl is-active --quiet tailscaled 2>/dev/null
	elif has_openrc_service; then
		openrc_name=$(openrc_service_name) || return 1
		rc-service "${openrc_name}" status >/dev/null 2>&1
	else
		tailscaled_process_running
	fi
}

managed_tailscaled_pid() {
	local pid="" openrc_name="" pidfile=""
	if has_unit tailscaled.service; then
		pid=$(systemctl show -p MainPID tailscaled 2>/dev/null | sed -n 's/^MainPID=//p' | head -n1 || true)
	elif has_openrc_service; then
		openrc_name=$(openrc_service_name) || return 1
		pidfile=$(awk -F= '$1 ~ /^[[:space:]]*pidfile[[:space:]]*$/ { value = $0; sub(/^[^=]*=[[:space:]]*/, "", value); gsub(/"/, "", value); print value; exit }' "/etc/init.d/${openrc_name}" 2>/dev/null || true)
		[[ ${pidfile} == /* && -f ${pidfile} ]] || return 1
		pid=$(${SUDO} sed -n '1p' "${pidfile}" 2>/dev/null || true)
	else
		return 1
	fi
	[[ ${pid} =~ ^[0-9]+$ && ${pid} -gt 0 ]] || return 1
	printf '%s\n' "${pid}"
}

validate_managed_process_set() {
	local pids="" managed_pid="" pid="" found_managed=false
	pids=$(running_tailscaled_pids)
	[[ -z ${pids} ]] && return 0
	if ! tailscaled_service_active; then
		log R "An unmanaged tailscaled process is running; no packages or binaries were changed"
		return 1
	fi
	managed_pid=$(managed_tailscaled_pid || true)
	if [[ -z ${managed_pid} ]]; then
		log R "Could not identify the active service's tailscaled PID safely; no changes were made"
		return 1
	fi
	while IFS= read -r pid; do
		[[ ${pid} =~ ^[0-9]+$ ]] || continue
		if [[ ${pid} == "${managed_pid}" ]]; then
			found_managed=true
		else
			log R "Extra unmanaged tailscaled PID ${pid} was detected beside service PID ${managed_pid}; no changes were made"
			return 1
		fi
	done <<<"${pids}"
	if [[ ${found_managed} != true ]]; then
		log R "The service MainPID ${managed_pid} does not match any running tailscaled process; no changes were made"
		return 1
	fi
	return 0
}

tailscaled_service_enabled() {
	local openrc_name="" state=""
	if has_unit tailscaled.service; then
		state=$(systemctl is-enabled tailscaled 2>/dev/null || true)
		case "${state}" in
		enabled | enabled-runtime | linked | linked-runtime | alias) return 0 ;;
		disabled | static | masked | masked-runtime | indirect | generated | transient) return 1 ;;
		*) return 2 ;;
		esac
	elif has_openrc_service; then
		openrc_name=$(openrc_service_name) || return 1
		openrc_service_enabled "${openrc_name}"
	else
		return 1
	fi
}

set_tailscaled_service_enabled() {
	local enabled="$1" openrc_name="" manager="" enabled_status=0
	if has_unit tailscaled.service; then
		manager="systemd"
	elif has_openrc_service; then
		manager="openrc"
		openrc_name=$(openrc_service_name) || return 1
	else
		return 0
	fi

	if tailscaled_service_enabled; then
		enabled_status=0
	else
		enabled_status=$?
	fi
	if [[ ${enabled_status} -eq 2 ]]; then
		log R "Could not inspect whether tailscaled is enabled"
		return 1
	fi
	if [[ ${enabled} == true && ${enabled_status} -eq 0 ]] || [[ ${enabled} != true && ${enabled_status} -eq 1 ]]; then
		return 0
	fi

	if [[ ${manager} == "systemd" ]]; then
		if [[ ${enabled} == true ]]; then
			${SUDO} systemctl enable tailscaled
		else
			${SUDO} systemctl disable tailscaled
		fi
	elif [[ ${enabled} == true ]]; then
		${SUDO} rc-update add "${openrc_name}" default
	else
		remove_openrc_service_from_runlevels "${openrc_name}"
	fi
}

# Extract official Tailscale version from fork tag (e.g., 1.90.6 from v1.90.6-awg2.0-1)
extract_official_version() {
	local tag="$1"
	if [[ ${tag} =~ ^v?([0-9]+\.[0-9]+\.[0-9]+) ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	fi
	return 1
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
		log R "Missing value for ${option}"
		exit 1
	fi
}

# Write a minimal/fallback systemd unit without overwriting existing config.
systemd_unit_file_present() {
	local unit_file=""
	for unit_file in \
		/etc/systemd/system/tailscaled.service \
		/run/systemd/system/tailscaled.service \
		/lib/systemd/system/tailscaled.service \
		/usr/lib/systemd/system/tailscaled.service; do
		if [[ -e ${unit_file} || -L ${unit_file} ]]; then
			return 0
		fi
	done
	return 1
}

write_minimal_unit() {
	local td_bin="$1"
	if [[ -e /etc/systemd/system/tailscaled.service || -L /etc/systemd/system/tailscaled.service ]]; then
		log R "Refusing to overwrite existing unrecognized unit: /etc/systemd/system/tailscaled.service"
		return 1
	fi
	if ! cat <<UNIT | ${SUDO} tee /etc/systemd/system/tailscaled.service >/dev/null
[Unit]
Description=Tailscale node agent (fallback minimal unit)
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=${td_bin} --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=41641
ExecStopPost=${td_bin} --cleanup
Restart=on-failure
RuntimeDirectory=tailscale
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SYS_MODULE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SYS_MODULE
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT
	then
		return 1
	fi
	${SUDO} systemctl daemon-reload
}

# Write a minimal OpenRC service only when the official package could not
# provide one. Existing OpenRC configuration is never overwritten.
write_minimal_openrc_service() {
	local td_bin="$1"
	if [[ -e /etc/init.d/tailscaled || -L /etc/init.d/tailscaled ]]; then
		log R "Refusing to overwrite existing unrecognized OpenRC service: /etc/init.d/tailscaled"
		return 1
	fi
	if ! cat <<UNIT | ${SUDO} tee /etc/init.d/tailscaled >/dev/null
#!/sbin/openrc-run
name="tailscaled"
description="Tailscale node agent (fallback minimal service)"
command="${td_bin}"
command_args="--state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock --port=41641"
command_background=true
pidfile="/run/tailscaled.pid"
start_stop_daemon_args="-1 /var/log/tailscaled.log -2 /var/log/tailscaled.log"

depend() {
    need net
}

start_pre() {
    mkdir -p /var/lib/tailscale /var/run/tailscale
    \${command} --cleanup || true
}

stop_post() {
    \${command} --cleanup || true
}
UNIT
	then
		return 1
	fi
	${SUDO} chmod 0755 /etc/init.d/tailscaled
}

stop_disable_tailscaled() {
	local openrc_name="" managed_service=false
	if has_unit tailscaled.service; then
		managed_service=true
		if ! ${SUDO} systemctl stop tailscaled; then
			log R "systemd could not stop tailscaled"
			return 1
		fi
		if [[ ${ACTION} == "uninstall" ]]; then
			if ! set_tailscaled_service_enabled false; then
				log R "systemd could not disable tailscaled safely"
				return 1
			fi
		fi
	elif has_openrc_service; then
		managed_service=true
		openrc_name=$(openrc_service_name) || return 1
		if ! ${SUDO} rc-service "${openrc_name}" stop >/dev/null 2>&1; then
			# OpenRC can report an error for an already-stopped service. Only
			# accept it when there is no daemon left to protect.
			if tailscaled_process_running; then
				log R "OpenRC could not stop ${openrc_name}"
				return 1
			fi
		fi
		if [[ ${ACTION} == "uninstall" ]]; then
			if ! set_tailscaled_service_enabled false; then
				log R "OpenRC could not remove ${openrc_name} from its runlevels safely"
				return 1
			fi
		fi
	fi
	if [[ ${managed_service} != true ]] && tailscaled_process_running; then
		if [[ ${ACTION} != "uninstall" ]]; then
			log R "An unmanaged tailscaled process is running; refusing to stop an invocation that rollback cannot reconstruct"
			return 1
		fi
	fi
	if tailscaled_process_running && ! terminate_unmanaged_tailscaled; then
		log R "tailscaled is still running; refusing to replace its binary"
		return 1
	fi
	if tailscaled_process_running; then
		log R "tailscaled is still running; refusing to replace its binary"
		return 1
	fi
	return 0
}

start_tailscaled_service() {
	local enable_service="${1:-true}" openrc_name=""
	if ! ensure_dirs; then
		log R "Failed to create tailscaled state/runtime directories"
		return 1
	fi
	if has_unit tailscaled.service; then
		if ! ${SUDO} systemctl daemon-reload; then return 1; fi
		if [[ ${enable_service} == true ]] && ! set_tailscaled_service_enabled true; then
			log R "Failed to enable tailscaled with systemd"
			return 1
		fi
		if ! ${SUDO} systemctl restart tailscaled; then
			log R "Failed to restart tailscaled with systemd"
			return 1
		fi
	elif has_openrc_service; then
		openrc_name=$(openrc_service_name) || return 1
		if [[ ${enable_service} == true ]] && ! set_tailscaled_service_enabled true; then
			log R "Failed to enable ${openrc_name} with OpenRC"
			return 1
		fi
		if ! ${SUDO} rc-service "${openrc_name}" restart >/dev/null 2>&1 && ! ${SUDO} rc-service "${openrc_name}" start; then
			log R "Failed to start ${openrc_name} with OpenRC"
			return 1
		fi
	else
		log R "No supported service manager was found (systemd or OpenRC)"
		return 1
	fi
	local attempts=0
	while ((attempts < 10)); do
		if tailscaled_service_active && tailscaled_process_running; then
			return 0
		fi
		sleep 1
		attempts=$((attempts + 1))
	done
	log R "tailscaled did not reach a running service state"
	return 1
}

# Global variables
DISTRO="" PACKAGE_MANAGER="" SUDO="" RELEASE_TAG="latest" MIRROR_PREFIX="" ACTION="install" OFFICIAL_VERSION="" PRE_RELEASE=false
LEGACY_CPS_COUNTER_DETECTED=false
TMP_DIRS=()
CURL_HTTP1_FLAG=""
ROLLBACK_AVAILABLE=false ROLLBACK_TS_PATH="" ROLLBACK_TD_PATH="" ROLLBACK_BACKUP_DIR=""
ROLLBACK_TS_EXISTED=false ROLLBACK_TD_EXISTED=false ROLLBACK_SERVICE_WAS_ACTIVE=false ROLLBACK_SERVICE_WAS_ENABLED=false ROLLBACK_SERVICE_FILE=""
INSTALLED_TS_PATH="" INSTALLED_TD_PATH=""
PRESERVE_TMP_DIR=""
STAGED_RELEASE_DIR="" STAGED_TS_PATH="" STAGED_TD_PATH=""
STAGED_TS_SHA256="" STAGED_TD_SHA256=""

# Detect if curl supports --http1.1 (old curl like 7.29.0 on CentOS 7 doesn't)
if command -v curl &>/dev/null; then
	if curl --help 2>&1 | grep -q -- '--http1\.1'; then
		CURL_HTTP1_FLAG='--http1.1'
	fi
fi

# Robust cleanup (single trap, additive)
cleanup() {
	local code=$?
	if [[ ${code} -ne 0 && ${ROLLBACK_AVAILABLE} == true ]]; then
		set +e
		log Y "Installation did not complete; restoring the previous binaries and service state"
		rollback_installed_binaries
	fi
	for d in "${TMP_DIRS[@]-}"; do
		if [[ -n ${PRESERVE_TMP_DIR} && ${d} == "${PRESERVE_TMP_DIR}" ]]; then
			log Y "Preserving incomplete rollback files in ${d}"
			continue
		fi
		[[ -n ${d} && -d ${d} ]] && rm -rf -- "${d}"
	done
	exit "${code}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

classify_distribution() {
	local distro_tokens=" $1 $2 "
	case "${distro_tokens}" in
	*" debian "* | *" ubuntu "*)
		DISTRO="debian"
		PACKAGE_MANAGER="apt-get"
		;;
	*" opensuse "* | *" suse "* | *" sles "*)
		DISTRO="suse"
		PACKAGE_MANAGER="zypper"
		;;
	*" fedora "* | *" rhel "* | *" centos "*)
		DISTRO="redhat"
		if command -v dnf &>/dev/null; then
			PACKAGE_MANAGER="dnf"
		elif command -v yum &>/dev/null; then
			PACKAGE_MANAGER="yum"
		else
			PACKAGE_MANAGER=""
		fi
		;;
	*" arch "*)
		DISTRO="arch"
		PACKAGE_MANAGER="pacman"
		;;
	*" alpine "*)
		DISTRO="alpine"
		PACKAGE_MANAGER="apk"
		;;
	*) return 1 ;;
	esac
}

# Detect distribution and package manager
detect_system() {
	local os_id="" os_like=""
	if [[ ${EUID} -eq 0 ]]; then
		SUDO=""
	elif has_cmd sudo; then
		SUDO="sudo"
	else
		log R "Root privileges are required and sudo is not installed"
		exit 1
	fi

	DISTRO="unknown"
	PACKAGE_MANAGER=""
	if [[ -f /etc/os-release ]]; then
		# shellcheck source=/dev/null
		source /etc/os-release
		os_id="${ID:-}"
		os_like="${ID_LIKE:-}"
		classify_distribution "${os_id}" "${os_like}" || true
	fi
	# ID_LIKE is absent or incomplete on some derivatives. Fall back to the
	# native package database/manager pair instead of treating a supported
	# derivative as an unknown manual installation.
	if [[ ${DISTRO} == "unknown" ]]; then
		if command -v dpkg-query &>/dev/null && command -v apt-get &>/dev/null; then
			DISTRO="debian"
			PACKAGE_MANAGER="apt-get"
		elif command -v zypper &>/dev/null && command -v rpm &>/dev/null; then
			DISTRO="suse"
			PACKAGE_MANAGER="zypper"
		elif command -v dnf &>/dev/null && command -v rpm &>/dev/null; then
			DISTRO="redhat"
			PACKAGE_MANAGER="dnf"
		elif command -v yum &>/dev/null && command -v rpm &>/dev/null; then
			DISTRO="redhat"
			PACKAGE_MANAGER="yum"
		elif command -v pacman &>/dev/null; then
			DISTRO="arch"
			PACKAGE_MANAGER="pacman"
		elif command -v apk &>/dev/null; then
			DISTRO="alpine"
			PACKAGE_MANAGER="apk"
		fi
	fi

	log B "Platform: linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
	log B "Distribution: ${DISTRO}${PACKAGE_MANAGER:+ (${PACKAGE_MANAGER})}"
}

# Verify the downloaded file structure without executing untrusted bytes.
verify_binary() {
	local file="$1" name="$2" min_size="${3:-1048576}" # Default minimum 1MB

	# Check file exists
	if [[ ! -f ${file} ]]; then
		log R "Binary ${name} not found: ${file}"
		return 1
	fi

	# Check file is not empty
	if [[ ! -s ${file} ]]; then
		log R "Binary ${name} is empty"
		return 1
	fi

	# Check file size is reasonable
	local file_size
	file_size=$(stat -c%s "${file}" 2>/dev/null || stat -f%z "${file}" 2>/dev/null || echo "0")
	if [[ ${file_size} -lt ${min_size} ]]; then
		log R "Binary ${name} too small: ${file_size} bytes (expected >${min_size})"
		return 1
	fi

	# Check ELF magic number (first 4 bytes: 0x7f 'E' 'L' 'F')
	if ! head -c4 "${file}" 2>/dev/null | grep -q $'\x7fELF'; then
		log R "Binary ${name} is not a valid ELF file"
		return 1
	fi

	# Make executable
	chmod +x "${file}" 2>/dev/null || {
		log R "Cannot make ${name} executable"
		return 1
	}

	# Check architecture without starting the downloaded program. Version
	# execution happens only after the release digest has been checked.
	if command -v file &>/dev/null; then
		local file_type current_arch
		file_type=$(file -b "${file}" 2>/dev/null || true)
		current_arch=$(uname -m)
		if [[ ! ${file_type} =~ ELF.*executable ]]; then
			log R "Binary ${name} is not an ELF executable: ${file_type:-unknown}"
			return 1
		fi
		if [[ ${current_arch} == "x86_64" && ! ${file_type} =~ (x86-64|x86_64|amd64) ]]; then
			log R "Architecture mismatch: ${name} is not x86_64"
			return 1
		elif [[ ${current_arch} == "aarch64" && ! ${file_type} =~ (aarch64|ARM.*64) ]]; then
			log R "Architecture mismatch: ${name} is not ARM64"
			return 1
		fi
	fi

	return 0
}

binary_version() {
	local file="$1" name="$2" output=""
	case "${name}" in
	tailscale) output=$("${file}" version 2>/dev/null || true) ;;
	tailscaled) output=$("${file}" --version 2>/dev/null || true) ;;
	esac
	printf '%s\n' "${output}" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1
}

verify_binary_version() {
	local file="$1" name="$2" expected="$3" actual=""
	actual=$(binary_version "${file}" "${name}" || true)
	if [[ -z ${actual} || ${actual} != "${expected}" ]]; then
		log R "Binary ${name} version mismatch: expected ${expected}, got ${actual:-unknown}"
		return 1
	fi
}

sha256_file() {
	local file="$1"
	if has_cmd sha256sum; then
		sha256sum "${file}" | awk '{print $1}'
	elif has_cmd shasum; then
		shasum -a 256 "${file}" | awk '{print $1}'
	elif has_cmd openssl; then
		openssl dgst -sha256 "${file}" | awk '{print $NF}'
	else
		return 1
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
	if has_cmd curl; then
		response=$(curl -fsSL ${CURL_HTTP1_FLAG:+${CURL_HTTP1_FLAG}} --max-time 20 "${api_url}" 2>/dev/null || true)
		if [[ -z ${response} && -n ${MIRROR_PREFIX} ]]; then
			response=$(curl -fsSL ${CURL_HTTP1_FLAG:+${CURL_HTTP1_FLAG}} --max-time 20 "${MIRROR_PREFIX}/${api_url}" 2>/dev/null || true)
		fi
	elif has_cmd wget; then
		response=$(wget -qO- --timeout=20 "${api_url}" 2>/dev/null || true)
		if [[ -z ${response} && -n ${MIRROR_PREFIX} ]]; then
			response=$(wget -qO- --timeout=20 "${MIRROR_PREFIX}/${api_url}" 2>/dev/null || true)
		fi
	fi
	[[ -n ${response} ]] || return 1
	printf '%s\n' "${response}"
}

fetch_release_metadata() {
	local api_url="https://api.github.com/repos/${REPO}/releases/tags/${RELEASE_TAG}"
	if has_cmd curl; then
		curl -fsSL ${CURL_HTTP1_FLAG:+${CURL_HTTP1_FLAG}} --max-time 20 "${api_url}" 2>/dev/null
	elif has_cmd wget; then
		wget -qO- --timeout=20 "${api_url}" 2>/dev/null
	else
		return 1
	fi
}

verify_release_digest() {
	local file="$1" asset="$2" metadata="$3" expected="" actual=""
	expected=$(release_asset_sha256 "${metadata}" "${asset}" || true)
	if [[ -z ${expected} ]]; then
		log Y "No GitHub SHA-256 digest is published for ${asset}; relying on format and version validation"
		return 0
	fi
	actual=$(sha256_file "${file}" || true)
	if [[ -z ${actual} ]]; then
		log R "Cannot verify ${asset}: no SHA-256 tool is available"
		return 1
	fi
	actual=$(printf '%s' "${actual}" | tr '[:upper:]' '[:lower:]')
	if [[ ${actual} != "${expected}" ]]; then
		log R "SHA-256 mismatch for ${asset}"
		return 1
	fi
	log G "SHA-256 verified: ${asset}"
}

# Smart download with fallbacks and integrity verification
smart_download() {
	local url="$1" output="$2" min_size="${3:-1048576}" # Default minimum 1MB
	local download_success=false

	# Remove any partial/existing file first
	[[ -f ${output} ]] && rm -f "${output}"

	# Try curl first (with proper error checking)
	if command -v curl &>/dev/null; then
		if curl -fsSL ${CURL_HTTP1_FLAG:+${CURL_HTTP1_FLAG}} --max-time 60 --retry 2 "${url}" -o "${output}" 2>&1; then
			download_success=true
		fi
	fi

	# Fallback to wget if curl failed or unavailable
	if [[ ${download_success} == false ]] && command -v wget &>/dev/null; then
		rm -f "${output}" 2>/dev/null || true
		if wget -q --show-progress --timeout=60 --tries=2 -O "${output}" "${url}" 2>&1; then
			download_success=true
		fi
	fi

	# Verify download succeeded
	if [[ ${download_success} == false ]]; then
		log R "Download failed: ${url}"
		return 1
	fi

	# Verify file exists and has minimum size
	if [[ ! -f ${output} ]]; then
		log R "Downloaded file not found: ${output}"
		return 1
	fi

	local file_size
	file_size=$(stat -c%s "${output}" 2>/dev/null || stat -f%z "${output}" 2>/dev/null || echo "0")
	if [[ ${file_size} -lt ${min_size} ]]; then
		log R "Downloaded file too small: ${file_size} bytes (expected >${min_size})"
		rm -f "${output}"
		return 1
	fi

	return 0
}

# Install official Tailscale if missing
install_tailscale() {
	local target_version="$1" # Optional: specific version to install
	local installed_ts="" installed_td=""
	installed_ts=$(type -P tailscale 2>/dev/null || true)
	installed_td=$(type -P tailscaled 2>/dev/null || true)

	if [[ ${installed_ts} == /* && -x ${installed_ts} ]]; then
		log B "Tailscale found"
		# Existing service/binary state is the rollback baseline. Do not let a
		# package-manager alignment step overwrite an older fork before its
		# binaries have been backed up; the validated pair below can be installed
		# directly over any compatible official/fork package layout.
		if [[ -n ${target_version} ]]; then
			local installed_version
			installed_version=$("${installed_ts}" version 2>/dev/null | head -1 | awk '{print $1}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "")
			if [[ -n ${installed_version} && ${installed_version} != "${target_version}" ]]; then
				log Y "Installed Tailscale version (${installed_version}) differs from fork base version (${target_version})"
				log Y "Preserving the current package/service baseline and replacing only the validated binaries"
			fi
		fi
		return
	fi
	if [[ ${installed_td} == /* && -x ${installed_td} ]] || has_unit tailscaled.service || has_openrc_service; then
		log Y "An existing tailscaled binary/service was found without an active tailscale command"
		log Y "Preserving that rollback baseline; the validated client/daemon pair will repair it directly"
		return 0
	fi

	log Y "Installing official Tailscale via upstream script..."
	if command -v curl &>/dev/null; then
		if ! curl -fsSL https://tailscale.com/install.sh | sh 2>/dev/null; then
			log R "Official installer failed; will fallback to direct binary replacement"
			return
		fi
	elif command -v wget &>/dev/null; then
		if ! wget -qO- https://tailscale.com/install.sh | sh 2>/dev/null; then
			log R "Official installer failed; will fallback to direct binary replacement"
			return
		fi
	else
		log R "Neither curl nor wget available to fetch official installer; fallback to direct binary replacement"
		return
	fi

	log G "Official Tailscale installed"

	# After installation, verify and adjust version if needed
	if [[ -n ${target_version} ]]; then
		local installed_version
		installed_ts=$(type -P tailscale 2>/dev/null || true)
		if [[ ${installed_ts} == /* && -x ${installed_ts} ]]; then
			installed_version=$("${installed_ts}" version 2>/dev/null | head -1 | awk '{print $1}' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "")
		else
			log Y "Official package did not expose an absolute tailscale executable; continuing with validated fork binaries"
			return 0
		fi
		if [[ -n ${installed_version} && ${installed_version} != "${target_version}" ]]; then
			log Y "Official installer installed ${installed_version}, but fork needs ${target_version}"
			reinstall_specific_version "${target_version}"
		fi
	fi
}

# Reinstall specific Tailscale version via package manager (with patch-level fallback)
reinstall_specific_version() {
	local version="$1"
	[[ -z ${version} ]] && return

	# Build list of versions to try: exact version first, then lower patch versions
	local versions_to_try=("${version}")
	if [[ ${version} =~ ^([0-9]+\.[0-9]+)\.([0-9]+)$ ]]; then
		local major_minor="${BASH_REMATCH[1]}"
		local patch="${BASH_REMATCH[2]}"
		local p
		for ((p = patch - 1; p >= 0; p--)); do
			versions_to_try+=("${major_minor}.${p}")
		done
	fi

	log B "Installing Tailscale ${version} via package manager..."
	local installed=false
	for try_ver in "${versions_to_try[@]}"; do
		if [[ ${try_ver} != "${version}" ]]; then
			log Y "Exact version ${version} not available, trying ${try_ver}..."
		fi
		case "${DISTRO}" in
		debian)
			${SUDO} apt-get update &>/dev/null || true
			if ${SUDO} apt-get install -y --allow-downgrades tailscale="${try_ver}" 2>/dev/null; then
				installed=true
			fi
			;;
		redhat)
			if command -v dnf &>/dev/null; then
				${SUDO} dnf install -y tailscale-"${try_ver}" 2>/dev/null && installed=true
			elif command -v yum &>/dev/null; then
				${SUDO} yum install -y tailscale-"${try_ver}" 2>/dev/null && installed=true
			fi
			;;
		suse)
			${SUDO} zypper --non-interactive install --force tailscale="${try_ver}" 2>/dev/null && installed=true
			;;
		# arch, alpine use rolling/latest, version pinning not typically supported
		*)
			log Y "Version pinning not supported for ${DISTRO}, using installed version"
			return
			;;
		esac
		if [[ ${installed} == true ]]; then
			if [[ ${try_ver} != "${version}" ]]; then
				log G "Installed Tailscale ${try_ver} (closest match to ${version})"
			fi
			return 0
		fi
	done
	log Y "Failed to install Tailscale ${version} (or any lower patch version), continuing with installed version"
}

# Get latest version from GitHub API and extract official version
get_version() {
	if [[ ${RELEASE_TAG} != "latest" ]]; then
		# User specified a version tag via --version parameter
		# RELEASE_TAG is already set by user, just extract official version.
		if ! OFFICIAL_VERSION=$(extract_official_version "${RELEASE_TAG}"); then
			log R "Invalid release tag: ${RELEASE_TAG}; expected vMAJOR.MINOR.PATCH" >&2
			return 1
		fi
		log B "Using version: ${RELEASE_TAG} (official base: v${OFFICIAL_VERSION})" >&2
		return
	fi

	local tag_name=""
	if [[ ${PRE_RELEASE} == true ]]; then
		local api_url="https://api.github.com/repos/${REPO}/releases?per_page=100"
		local response=""
		if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
			log R "curl or wget required to fetch version" >&2
			exit 1
		fi
		response=$(fetch_api_url "${api_url}" || true)
		if [[ -z ${response} ]]; then
			log R "Failed to query GitHub releases" >&2
			exit 1
		fi
		tag_name=$(printf '%s\n' "${response}" | extract_release_tags_by_prerelease "true" | select_highest_version_tag)
		if [[ -z ${tag_name} ]]; then
			log Y "No pre-release found, falling back to latest stable" >&2
			tag_name=$(printf '%s\n' "${response}" | extract_release_tags_by_prerelease "false" | select_highest_version_tag)
		fi
	else
		local api_url="https://api.github.com/repos/${REPO}/releases/latest"
		if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
			log R "curl or wget required to fetch version" >&2
			exit 1
		fi
		tag_name=$(fetch_api_url "${api_url}" | grep '"tag_name":' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' | head -1 || true)
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
resolve_install_target() {
	local entry_path="$1" resolved=""
	if [[ ! -L ${entry_path} ]]; then
		printf '%s\n' "${entry_path}"
		return 0
	fi
	# Replacing a symlink with `install` turns it into a regular file and breaks
	# package-manager ownership. Update its existing referent instead so both a
	# successful install and rollback preserve the link topology.
	if [[ ! -e ${entry_path} ]]; then
		log R "Refusing to replace dangling symlink: ${entry_path}" >&2
		return 1
	fi
	resolved=$(readlink -f "${entry_path}" 2>/dev/null || true)
	if [[ -z ${resolved} || ! -f ${resolved} ]]; then
		log R "Cannot resolve install target symlink: ${entry_path}" >&2
		return 1
	fi
	log B "Preserving symlink ${entry_path} -> ${resolved}" >&2
	printf '%s\n' "${resolved}"
}

validate_existing_native_target() {
	local target="$1" name="$2"
	[[ -e ${target} ]] || return 0
	if [[ ! -f ${target} ]]; then
		log R "Existing ${name} target is not a regular file: ${target}"
		return 1
	fi
	if ! head -c4 "${target}" 2>/dev/null | grep -q $'\x7fELF'; then
		log R "Existing ${name} target is not a native ELF binary: ${target}"
		log R "Custom command wrappers are never overwritten; move the wrapper out of PATH and retry"
		return 1
	fi
}

restore_binary_pair() {
	local ts_path="$1" td_path="$2" backup_dir="$3" ts_existed="$4" td_existed="$5"
	local restore_ok=true
	if [[ ${ts_existed} == true ]]; then
		if ! ${SUDO} cp -p "${backup_dir}/tailscale" "${ts_path}" || ! ${SUDO} cmp -s "${backup_dir}/tailscale" "${ts_path}"; then
			log R "Failed to restore tailscale to ${ts_path}"
			restore_ok=false
		fi
	else
		if ! ${SUDO} rm -f -- "${ts_path}" || [[ -e ${ts_path} || -L ${ts_path} ]]; then
			log R "Failed to remove newly installed tailscale at ${ts_path}"
			restore_ok=false
		fi
	fi
	if [[ ${td_existed} == true ]]; then
		if ! ${SUDO} cp -p "${backup_dir}/tailscaled" "${td_path}" || ! ${SUDO} cmp -s "${backup_dir}/tailscaled" "${td_path}"; then
			log R "Failed to restore tailscaled to ${td_path}"
			restore_ok=false
		fi
	else
		if ! ${SUDO} rm -f -- "${td_path}" || [[ -e ${td_path} || -L ${td_path} ]]; then
			log R "Failed to remove newly installed tailscaled at ${td_path}"
			restore_ok=false
		fi
	fi
	[[ ${restore_ok} == true ]]
}

rollback_installed_binaries() {
	[[ ${ROLLBACK_AVAILABLE} == true ]] || return 0
	local rollback_ok=true stopped=true restored=false
	if ! stop_disable_tailscaled; then
		log R "Rollback could not stop tailscaled; binaries were not overwritten again"
		rollback_ok=false
		stopped=false
	fi
	if [[ ${stopped} == true ]]; then
		if restore_binary_pair "${ROLLBACK_TS_PATH}" "${ROLLBACK_TD_PATH}" "${ROLLBACK_BACKUP_DIR}" "${ROLLBACK_TS_EXISTED}" "${ROLLBACK_TD_EXISTED}"; then
			restored=true
		else
			rollback_ok=false
		fi
	fi
	if [[ ${stopped} == true && -n ${ROLLBACK_SERVICE_FILE} ]]; then
		# Remove enablement links/runlevel entries before deleting a service file
		# that was created only for this failed installation.
		if ! set_tailscaled_service_enabled false; then
			rollback_ok=false
		elif ! ${SUDO} rm -f -- "${ROLLBACK_SERVICE_FILE}"; then
			rollback_ok=false
		elif systemd_available && ! ${SUDO} systemctl daemon-reload; then
			rollback_ok=false
		fi
	fi
	if [[ ${restored} == true && ${ROLLBACK_SERVICE_WAS_ACTIVE} == true ]]; then
		if ! start_tailscaled_service false; then
			log R "The previous service could not be restarted"
			rollback_ok=false
		fi
	fi
	if [[ ${stopped} == true && ${ROLLBACK_SERVICE_WAS_ENABLED} != true ]]; then
		if ! set_tailscaled_service_enabled false; then rollback_ok=false; fi
	fi
	ROLLBACK_AVAILABLE=false
	if [[ ${rollback_ok} != true ]]; then
		PRESERVE_TMP_DIR=$(dirname "${ROLLBACK_BACKUP_DIR}")
		log R "Rollback was incomplete. Backup files were preserved at ${ROLLBACK_BACKUP_DIR}"
		return 1
	fi
	return 0
}

stage_release_binaries() {
	local arch platform base_url tmp_dir ts_asset td_asset metadata=""
	local ts_sha256="" td_sha256=""
	arch=$(uname -m)
	case "${arch}" in
	x86_64 | amd64) platform="linux-amd64" ;;
	aarch64 | arm64) platform="linux-arm64" ;;
	*)
		log R "Unsupported architecture: ${arch}"
		return 1
		;;
	esac

	base_url="https://github.com/${REPO}/releases/download/${RELEASE_TAG}"
	[[ -n ${MIRROR_PREFIX} ]] && base_url="${MIRROR_PREFIX}/${base_url}"
	ts_asset="tailscale-${platform}"
	td_asset="tailscaled-${platform}"

	if ! tmp_dir=$(mktemp -d); then
		log R "Failed to create a temporary release staging directory"
		return 1
	fi
	TMP_DIRS+=("${tmp_dir}")

	log B "Downloading Amnezia-WG binaries..."

	# Download binaries with integrity checks (minimum 5MB for tailscale binaries)
	if ! smart_download "${base_url}/${ts_asset}" "${tmp_dir}/tailscale" 5242880; then
		log R "Failed to download tailscale binary"
		return 1
	fi

	if ! smart_download "${base_url}/${td_asset}" "${tmp_dir}/tailscaled" 5242880; then
		log R "Failed to download tailscaled binary"
		return 1
	fi

	log B "Verifying binary integrity..."

	# Verify both binaries (minimum 5MB)
	if ! verify_binary "${tmp_dir}/tailscale" "tailscale" 5242880; then
		log R "tailscale binary validation failed"
		return 1
	fi

	if ! verify_binary "${tmp_dir}/tailscaled" "tailscaled" 5242880; then
		log R "tailscaled binary validation failed"
		return 1
	fi
	# A downloaded program must not run before its trusted GitHub digest is
	# checked. Older releases without a published digest retain the explicit
	# format/version fallback for backward compatibility.
	metadata=$(fetch_release_metadata || true)
	if [[ -n ${metadata} ]]; then
		if ! verify_release_digest "${tmp_dir}/tailscale" "${ts_asset}" "${metadata}"; then
			return 1
		fi
		if ! verify_release_digest "${tmp_dir}/tailscaled" "${td_asset}" "${metadata}"; then
			return 1
		fi
	else
		log Y "GitHub release metadata is unavailable directly; relying on format and version validation"
	fi
	if ! verify_binary_version "${tmp_dir}/tailscale" "tailscale" "${OFFICIAL_VERSION}"; then
		return 1
	fi
	if ! verify_binary_version "${tmp_dir}/tailscaled" "tailscaled" "${OFFICIAL_VERSION}"; then
		return 1
	fi

	# Lock the exact bytes that passed validation. The package installation may
	# run privileged scripts, so install_binaries rechecks these digests before
	# consuming the staged files.
	ts_sha256=$(sha256_file "${tmp_dir}/tailscale" || true)
	td_sha256=$(sha256_file "${tmp_dir}/tailscaled" || true)
	if [[ ! ${ts_sha256} =~ ^[0-9a-fA-F]{64}$ || ! ${td_sha256} =~ ^[0-9a-fA-F]{64}$ ]]; then
		log R "Cannot lock staged binaries: no working SHA-256 tool is available"
		return 1
	fi
	STAGED_RELEASE_DIR="${tmp_dir}"
	STAGED_TS_PATH="${tmp_dir}/tailscale"
	STAGED_TD_PATH="${tmp_dir}/tailscaled"
	STAGED_TS_SHA256=$(printf '%s' "${ts_sha256}" | tr '[:upper:]' '[:lower:]')
	STAGED_TD_SHA256=$(printf '%s' "${td_sha256}" | tr '[:upper:]' '[:lower:]')

	log G "Release binaries validated and staged"
}

verify_staged_release_unchanged() {
	local ts_sha256="" td_sha256=""
	if [[ -z ${STAGED_RELEASE_DIR} || -z ${STAGED_TS_PATH} || -z ${STAGED_TD_PATH} ||
		-z ${STAGED_TS_SHA256} || -z ${STAGED_TD_SHA256} ||
		! -d ${STAGED_RELEASE_DIR} || ! -f ${STAGED_TS_PATH} || ! -f ${STAGED_TD_PATH} ]]; then
		log R "Validated release binaries are not available in the staging directory"
		return 1
	fi
	ts_sha256=$(sha256_file "${STAGED_TS_PATH}" || true)
	td_sha256=$(sha256_file "${STAGED_TD_PATH}" || true)
	ts_sha256=$(printf '%s' "${ts_sha256}" | tr '[:upper:]' '[:lower:]')
	td_sha256=$(printf '%s' "${td_sha256}" | tr '[:upper:]' '[:lower:]')
	if [[ ${ts_sha256} != "${STAGED_TS_SHA256}" || ${td_sha256} != "${STAGED_TD_SHA256}" ]]; then
		log R "Staged release binaries changed after validation; refusing to install them"
		return 1
	fi
}

install_binaries() {
	local tmp_dir="${STAGED_RELEASE_DIR}"
	if ! verify_staged_release_unchanged; then
		return 1
	fi

	# Determine the two active install targets. Do not overwrite unrelated copies
	# in every common directory; package managers and custom installations may own them.
	local ts_path td_path ts_entry_path td_entry_path exec_start=""
	ts_entry_path=$(type -P tailscale 2>/dev/null || true)
	td_entry_path=$(type -P tailscaled 2>/dev/null || true)
	[[ ${ts_entry_path} == /* ]] || ts_entry_path="${INSTALL_DIR}/tailscale"
	[[ ${td_entry_path} == /* ]] || td_entry_path="${INSTALL_DIR}/tailscaled"

	# Extract the daemon path from the active service definition when possible.
	if has_unit tailscaled.service; then
		# Try multiple parsing methods for compatibility
		# Method 1: Parse systemctl show output (structured format)
		exec_start=$(systemctl show -p ExecStart tailscaled 2>/dev/null | sed -n 's/.*path=\([^; ][^; ]*\).*/\1/p' | head -1 || true)
		# Method 2: Alternative systemctl show parsing
		[[ -z ${exec_start} ]] && exec_start=$(systemctl show -p ExecStart tailscaled 2>/dev/null | sed -E 's/^ExecStart=[{ ]*path=([^ ;]+).*/\1/' || true)
		# Method 3: Parse unit file directly
		[[ -z ${exec_start} ]] && exec_start=$(systemctl cat tailscaled 2>/dev/null | grep '^ExecStart=' | sed 's/^ExecStart=\([^ ][^ ]*\).*/\1/' | head -1 || true)
		# Method 4: Extract from systemctl status (fallback)
		[[ -z ${exec_start} ]] && exec_start=$(systemctl status tailscaled 2>/dev/null | grep -o '/[^ ]\+/tailscaled' | head -1 || true)
		if [[ -z ${exec_start} ]]; then
			log R "Could not determine tailscaled.service ExecStart safely; refusing to guess a replacement target"
			return 1
		else
			if [[ ${exec_start} != /* || ${exec_start##*/} != "tailscaled" ]]; then
				log R "tailscaled.service uses a custom wrapper (${exec_start}); refusing to overwrite it"
				return 1
			fi
			if [[ ! -x ${exec_start} ]]; then
				log R "tailscaled.service daemon is not executable: ${exec_start}"
				return 1
			fi
			td_entry_path="${exec_start}"
			log B "Detected tailscaled path from systemd: ${td_entry_path}"
		fi
	elif has_openrc_service; then
		local openrc_name=""
		openrc_name=$(openrc_service_name) || return 1
		exec_start=$(awk -F= '$1 ~ /^[[:space:]]*command[[:space:]]*$/ { value = $0; sub(/^[^=]*=[[:space:]]*/, "", value); gsub(/"/, "", value); print value; exit }' "/etc/init.d/${openrc_name}" 2>/dev/null || true)
		if [[ -z ${exec_start} ]]; then
			log R "Could not determine OpenRC ${openrc_name} command safely; refusing to guess a replacement target"
			return 1
		else
			if [[ ${exec_start} != /* || ${exec_start##*/} != "tailscaled" ]]; then
				log R "OpenRC ${openrc_name} uses a custom wrapper (${exec_start}); refusing to overwrite it"
				return 1
			fi
			if [[ ! -x ${exec_start} ]]; then
				log R "OpenRC tailscaled daemon is not executable: ${exec_start}"
				return 1
			fi
			td_entry_path="${exec_start}"
			log B "Detected tailscaled path from OpenRC: ${td_entry_path}"
		fi
	fi

	if ! systemd_available && ! openrc_available; then
		log R "No supported service manager was found (systemd or OpenRC); no binaries were replaced"
		return 1
	fi
	if ! validate_managed_process_set; then
		return 1
	fi
	ts_path=$(resolve_install_target "${ts_entry_path}") || return 1
	td_path=$(resolve_install_target "${td_entry_path}") || return 1
	if ! validate_existing_native_target "${ts_path}" tailscale || ! validate_existing_native_target "${td_path}" tailscaled; then
		return 1
	fi
	if ! ${SUDO} mkdir -p "$(dirname "${ts_path}")" "$(dirname "${td_path}")"; then
		log R "Failed to create binary installation directories"
		return 1
	fi

	local backup_dir="${tmp_dir}/backup" service_was_active=false service_was_enabled=false ts_existed=false td_existed=false
	if ! mkdir -p "${backup_dir}"; then
		log R "Failed to create the rollback backup directory; no binaries were replaced"
		return 1
	fi
	if [[ -e ${ts_path} ]]; then
		if ! ${SUDO} cp -p "${ts_path}" "${backup_dir}/tailscale" ||
			! ${SUDO} cmp -s "${ts_path}" "${backup_dir}/tailscale"; then
			log R "Failed to create a verified tailscale backup; no binaries were replaced"
			return 1
		fi
		ts_existed=true
	fi
	if [[ -e ${td_path} ]]; then
		if ! ${SUDO} cp -p "${td_path}" "${backup_dir}/tailscaled" ||
			! ${SUDO} cmp -s "${td_path}" "${backup_dir}/tailscaled"; then
			log R "Failed to create a verified tailscaled backup; no binaries were replaced"
			return 1
		fi
		td_existed=true
	fi
	if tailscaled_service_active; then
		service_was_active=true
	fi
	local service_enabled_status=0
	if tailscaled_service_enabled; then
		service_was_enabled=true
	else
		service_enabled_status=$?
		if [[ ${service_enabled_status} -eq 2 ]]; then
			log R "Could not inspect whether the existing tailscaled service is enabled; no binaries were replaced"
			return 1
		fi
	fi
	ROLLBACK_TS_PATH="${ts_path}"
	ROLLBACK_TD_PATH="${td_path}"
	ROLLBACK_BACKUP_DIR="${backup_dir}"
	ROLLBACK_TS_EXISTED="${ts_existed}"
	ROLLBACK_TD_EXISTED="${td_existed}"
	ROLLBACK_SERVICE_WAS_ACTIVE="${service_was_active}"
	ROLLBACK_SERVICE_WAS_ENABLED="${service_was_enabled}"
	ROLLBACK_SERVICE_FILE=""
	ROLLBACK_AVAILABLE=true
	if ! stop_disable_tailscaled; then
		log R "Unable to stop the existing tailscaled service; restoring its previous state"
		rollback_installed_binaries
		return 1
	fi

	local install_ok=true
	if ! ${SUDO} install -m 755 "${STAGED_TS_PATH}" "${ts_path}"; then
		install_ok=false
	fi
	if [[ ${install_ok} == true ]] && ! ${SUDO} install -m 755 "${STAGED_TD_PATH}" "${td_path}"; then
		install_ok=false
	fi
	if [[ ${install_ok} == true ]] &&
		(! verify_binary_version "${ts_path}" "tailscale" "${OFFICIAL_VERSION}" ||
			! verify_binary_version "${td_path}" "tailscaled" "${OFFICIAL_VERSION}"); then
		install_ok=false
	fi

	if [[ ${install_ok} != true ]]; then
		log R "Binary replacement failed; restoring the previous installation"
		rollback_installed_binaries
		return 1
	fi

	log G "Binaries installed: ${ts_path}, ${td_path}"

	# Create a service definition only when the platform has no existing one.
	local service_definition_ok=true
	if systemd_available && ! has_unit tailscaled.service; then
		# Reload once in case a package installed a unit that systemd has not yet
		# noticed. Never shadow an existing but unrecognized service definition.
		if ! ${SUDO} systemctl daemon-reload; then
			service_definition_ok=false
		elif has_unit tailscaled.service; then
			:
		elif systemd_unit_file_present; then
			log R "An existing tailscaled.service could not be loaded; refusing to overwrite it"
			service_definition_ok=false
		else
			log Y "Creating minimal systemd unit for tailscaled (fallback)"
			ROLLBACK_SERVICE_FILE="/etc/systemd/system/tailscaled.service"
			if ! write_minimal_unit "${td_path}"; then
				service_definition_ok=false
			fi
		fi
	elif openrc_available && ! has_openrc_service; then
		log Y "Creating minimal OpenRC service for tailscaled (fallback)"
		ROLLBACK_SERVICE_FILE="/etc/init.d/tailscaled"
		if write_minimal_openrc_service "${td_path}"; then
			:
		else
			service_definition_ok=false
		fi
	fi
	if [[ ${service_definition_ok} != true ]]; then
		log R "Service setup failed; restoring the previous installation"
		rollback_installed_binaries
		return 1
	fi
	INSTALLED_TS_PATH="${ts_path}"
	INSTALLED_TD_PATH="${td_path}"
}

debian_tailscale_package_installed() {
	command -v dpkg-query &>/dev/null &&
		dpkg-query -W -f='${Status}' tailscale 2>/dev/null | grep -q 'install ok installed'
}

rpm_tailscale_package_installed() {
	command -v rpm &>/dev/null && rpm -q tailscale &>/dev/null
}

arch_tailscale_package_installed() {
	command -v pacman &>/dev/null && pacman -Q tailscale &>/dev/null
}

alpine_tailscale_package_installed() {
	command -v apk &>/dev/null && apk info -e tailscale &>/dev/null
}

remove_installed_tailscale_packages() {
	local removal_failed=false rpm_manager=""
	if debian_tailscale_package_installed; then
		if ! command -v apt-get &>/dev/null; then
			log R "The installed Debian tailscale package was detected, but apt-get is unavailable"
			removal_failed=true
		elif ! ${SUDO} apt-get remove -y tailscale || debian_tailscale_package_installed; then
			log R "The Debian tailscale package could not be removed cleanly"
			removal_failed=true
		fi
	fi

	if rpm_tailscale_package_installed; then
		if [[ ${DISTRO} == "suse" ]] && command -v zypper &>/dev/null; then
			rpm_manager="zypper"
		elif command -v dnf &>/dev/null; then
			rpm_manager="dnf"
		elif command -v yum &>/dev/null; then
			rpm_manager="yum"
		elif command -v zypper &>/dev/null; then
			rpm_manager="zypper"
		fi
		case "${rpm_manager}" in
		zypper)
			if ! ${SUDO} zypper --non-interactive remove tailscale || rpm_tailscale_package_installed; then
				log R "The RPM tailscale package could not be removed cleanly with zypper"
				removal_failed=true
			fi
			;;
		dnf | yum)
			if ! ${SUDO} "${rpm_manager}" remove -y tailscale || rpm_tailscale_package_installed; then
				log R "The RPM tailscale package could not be removed cleanly with ${rpm_manager}"
				removal_failed=true
			fi
			;;
		*)
			log R "An installed RPM tailscale package was detected, but no supported RPM package manager is available"
			removal_failed=true
			;;
		esac
	fi

	if arch_tailscale_package_installed; then
		if ! ${SUDO} pacman -R --noconfirm tailscale || arch_tailscale_package_installed; then
			log R "The Arch tailscale package could not be removed cleanly"
			removal_failed=true
		fi
	fi

	if alpine_tailscale_package_installed; then
		if ! ${SUDO} apk del tailscale || alpine_tailscale_package_installed; then
			log R "The Alpine tailscale package could not be removed cleanly"
			removal_failed=true
		fi
	fi

	[[ ${removal_failed} == false ]]
}

# Comprehensive uninstall (remove packages, binaries, configs, state)
uninstall_all() {
	log Y "Uninstalling Tailscale (packages, binaries, config, state)..."

	# Log out while the local API is still reachable. A disconnected or already
	# logged-out node is harmless here, so these control-plane calls are best effort.
	if command -v tailscale &>/dev/null && tailscale status &>/dev/null; then
		tailscale logout 2>/dev/null || tailscale down 2>/dev/null || true
	fi

	# Stop & disable if present
	if ! stop_disable_tailscaled; then
		log R "Could not stop tailscaled; uninstall aborted before removing binaries or state"
		return 1
	fi
	log G "Service tailscaled stopped/disabled"

	local cleanup_failed=false

	# (Legacy) attempt to clean any ignore/lock patterns if they exist (harmless)
	if [[ -f /etc/pacman.conf ]]; then
		if ! ${SUDO} sed -i '/^IgnorePkg/ { s/ tailscale//; s/tailscale //; }' /etc/pacman.conf 2>/dev/null; then
			log R "Could not remove the legacy tailscale IgnorePkg entry"
			cleanup_failed=true
		fi
	fi

	# Remove package-manager ownership before touching files manually. If this
	# fails, stop here instead of leaving an installed package with missing files.
	if ! remove_installed_tailscale_packages; then
		log R "Package removal failed; manual artifact/state removal was not attempted"
		return 1
	fi

	# Remove binaries, systemd units, state & config files
	for b in /usr/local/bin/tailscale{,d} /usr/bin/tailscale{,d} /usr/sbin/tailscale{,d}; do
		if [[ -e ${b} || -L ${b} ]]; then
			if ${SUDO} rm -f -- "${b}"; then
				log G "Removed ${b}"
			else
				log R "Could not remove ${b}"
				cleanup_failed=true
			fi
		fi
	done
	for u in /etc/systemd/system/tailscaled.service /lib/systemd/system/tailscaled.service /usr/lib/systemd/system/tailscaled.service; do
		if [[ -e ${u} || -L ${u} ]]; then
			if ${SUDO} rm -f -- "${u}"; then
				log G "Removed unit ${u}"
			else
				log R "Could not remove unit ${u}"
				cleanup_failed=true
			fi
		fi
	done
	if systemd_available && ! ${SUDO} systemctl daemon-reload; then
		log R "systemd could not reload its unit files"
		cleanup_failed=true
	fi
	local openrc_file="" openrc_name=""
	for openrc_name in tailscaled tailscale; do
		openrc_file="/etc/init.d/${openrc_name}"
		if [[ -e ${openrc_file} || -L ${openrc_file} ]]; then
			if openrc_available; then
				if ! remove_openrc_service_from_runlevels "${openrc_name}"; then
					log R "Could not remove ${openrc_name} from its OpenRC runlevels"
					cleanup_failed=true
				fi
			fi
			if ${SUDO} rm -f -- "${openrc_file}"; then
				log G "Removed OpenRC service ${openrc_file}"
			else
				log R "Could not remove OpenRC service ${openrc_file}"
				cleanup_failed=true
			fi
		fi
	done
	for d in /var/lib/tailscale /var/run/tailscale /run/tailscale; do
		if [[ -e ${d} || -L ${d} ]]; then
			if ${SUDO} rm -rf -- "${d}"; then
				log G "Removed dir ${d}"
			else
				log R "Could not remove dir ${d}"
				cleanup_failed=true
			fi
		fi
	done
	for f in /etc/default/tailscaled /etc/sysconfig/tailscaled /etc/apt/sources.list.d/tailscale.list /usr/share/keyrings/tailscale-archive-keyring.gpg /etc/yum.repos.d/tailscale.repo /etc/zypp/repos.d/tailscale.repo; do
		if [[ -e ${f} || -L ${f} ]]; then
			if ${SUDO} rm -f -- "${f}"; then
				log G "Removed file ${f}"
			else
				log R "Could not remove file ${f}"
				cleanup_failed=true
			fi
		fi
	done

	if [[ ${cleanup_failed} == true ]]; then
		log R "Tailscale uninstall is incomplete; review the errors above and remove the remaining artifacts manually"
		return 1
	fi
	log G "Tailscale uninstalled (artifacts removed)"
	echo -e "\nIf you had iptables/routes modifications manually, review them. Reboot recommended for full cleanup of kernel modules (if any)."
}

# Ensure required runtime/state directories exist (some minimal Debian/containers may not have them recreated automatically)
ensure_dirs() {
	if ! ${SUDO} mkdir -p /var/lib/tailscale; then return 1; fi
	if ! ${SUDO} chmod 700 /var/lib/tailscale; then return 1; fi
	# /var/run is typically a symlink to /run, so only create /run/tailscale
	${SUDO} mkdir -p /run/tailscale
}

# Health check with retries for tailscaled service / socket
health_check_tailscaled() {
	local attempts=0 max=8
	while ((attempts < max)); do
		if tailscaled_service_active && tailscaled_process_running; then
			if [[ -x ${INSTALLED_TS_PATH} ]] && "${INSTALLED_TS_PATH}" status >/dev/null 2>&1; then
				return 0
			fi
			if [[ -S /var/run/tailscale/tailscaled.sock || -S /run/tailscale/tailscaled.sock ]]; then
				return 0
			fi
		fi
		sleep 1
		attempts=$((attempts + 1))
	done
	return 1
}

collect_tailscaled_diagnostics() {
	local diag_log
	# BusyBox mktemp (Alpine) requires the template to end in XXXXXX.
	diag_log=$(mktemp /tmp/tailscaled-diag-XXXXXX)
	{
		echo "Tailscale installer diagnostics"
		date -u 2>/dev/null || true
		if has_unit tailscaled.service; then
			${SUDO} systemctl status tailscaled --no-pager 2>&1 || true
			${SUDO} journalctl -u tailscaled -n 100 --no-pager 2>&1 || true
		elif has_openrc_service; then
			local openrc_name=""
			openrc_name=$(openrc_service_name || true)
			[[ -n ${openrc_name} ]] && ${SUDO} rc-service "${openrc_name}" status 2>&1 || true
			${SUDO} tail -n 100 /var/log/tailscaled.log 2>&1 || true
		fi
	} >"${diag_log}"
	printf '%s\n' "${diag_log}"
}

# Read the current profile before replacing binaries. This is a read-only
# migration check; the installer never rewrites AWG preferences automatically.
capture_awg_migration_state() {
	local config="" tailscale_bin=""
	tailscale_bin=$(type -P tailscale 2>/dev/null || true)
	[[ ${tailscale_bin} == /* && -x ${tailscale_bin} ]] || return 0
	config=$("${tailscale_bin}" awg get 2>/dev/null || "${tailscale_bin}" amnezia-wg get 2>/dev/null || true)
	if [[ ${config} == *"<c>"* ]]; then
		LEGACY_CPS_COUNTER_DETECTED=true
	fi
}

show_awg_guidance() {
	local release_version="${OFFICIAL_VERSION:-${RELEASE_TAG}}" supports_v3=false
	echo -e "Amnezia-WG commands (awg = amnezia-wg):"
	if version_at_least "${release_version}" "${AWG_V3_MIN_VERSION}"; then
		supports_v3=true
		log G "AWG v3 is available; existing AWG v2 profiles remain supported."
		echo -e "  tailscale awg set        # Enter = generate AWG v3; choose 2 for AWG v2"
	else
		log Y "This release predates AWG v3; install v${AWG_V3_MIN_VERSION} or newer for the v3 generator."
		echo -e "  tailscale awg set        # Configure the AWG version supported by this release"
	fi
	if [[ ${LEGACY_CPS_COUNTER_DETECTED} == true ]]; then
		if version_at_least "${release_version}" "${AWG_C_REMOVED_VERSION}"; then
			log Y "Legacy CPS tag <c> was detected; v${AWG_C_REMOVED_VERSION}+ rejects it, so remove only <c> from i1-i5."
		else
			log Y "Legacy CPS tag <c> was detected. This old release accepts it, but v${AWG_C_REMOVED_VERSION}+ does not."
		fi
	fi
	echo -e "  tailscale awg get        # Show the current profile and JSON"
	if [[ ${supports_v3} == true ]]; then
		echo -e "  tailscale awg validate   # Validate the current profile"
		echo -e "  tailscale awg sync       # Sync a compatible v2/v3 profile from an online peer"
	else
		echo -e "  tailscale awg sync       # Sync a compatible AWG v2 profile from an online peer"
	fi
	echo -e "  tailscale awg reset      # Disable AWG and use standard WireGuard"
}

# Main installation process
main() {
	echo "🔧 Tailscale Amnezia-WG v2/v3 Installer"

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--version)
			require_arg "$1" "${2-}"
			RELEASE_TAG="$2"
			shift 2
			;;
		--pre-release)
			PRE_RELEASE=true
			shift
			;;
		--mirror)
			require_arg "$1" "${2-}"
			MIRROR_PREFIX="${2%/}"
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
  --version TAG       Use specific GitHub release tag (e.g. v1.102.2)
  --pre-release      Install the latest pre-release version from GitHub
  --uninstall        Remove Tailscale (packages, binaries, config, state) and exit
  --help, -h         Show this help
EOF
			exit 0
			;;
		*)
			log R "Unknown option: $1"
			return 1
			;;
		esac
		done
	if [[ ${ACTION} != "uninstall" && ${RELEASE_TAG} != "latest" ]] && ! extract_official_version "${RELEASE_TAG}" >/dev/null; then
		log R "Invalid release tag: ${RELEASE_TAG}; expected vMAJOR.MINOR.PATCH"
		return 1
	fi
	if [[ $(uname -s) != "Linux" ]]; then
		log R "This installer only supports Linux; no packages, binaries, or state were changed"
		return 1
	fi

	detect_system
	capture_awg_migration_state

	if [[ ${ACTION} == "uninstall" ]]; then
		uninstall_all
		return
	fi
	# Refuse before installing curl or changing the official Tailscale package.
	# A systemctl/rc-service executable alone is insufficient; the helpers also
	# verify that the corresponding init system is actually active.
	if ! systemd_available && ! openrc_available; then
		log R "No active supported service manager was found (systemd or OpenRC); no packages or binaries were changed"
		return 1
	fi
	if ! validate_existing_service_command; then
		return 1
	fi
	if ! validate_managed_process_set; then
		return 1
	fi

	# Ensure we have curl or wget before using official installer
	if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
		log Y "Attempting to install curl (network tool)..."
		case "${DISTRO}" in
		debian) ${SUDO} apt-get update &>/dev/null && ${SUDO} apt-get install -y curl &>/dev/null || true ;;
		redhat) ${SUDO} "${PACKAGE_MANAGER}" install -y curl &>/dev/null || true ;;
		arch) ${SUDO} pacman -Sy --noconfirm curl &>/dev/null || true ;;
		alpine) ${SUDO} apk add --update curl &>/dev/null || true ;;
		suse) ${SUDO} zypper install -y curl &>/dev/null || true ;;
		esac
	fi

	get_version
	if ! stage_release_binaries; then
		return 1
	fi
	install_tailscale "${OFFICIAL_VERSION}"
	if ! install_binaries; then
		return 1
	fi

	if ! start_tailscaled_service; then
		log R "Failed to start tailscaled; restoring the previous installation"
		rollback_installed_binaries
		return 1
	fi
	if health_check_tailscaled; then
		log G "Service started and enabled"
	else
		local diag_log
		diag_log=$(collect_tailscaled_diagnostics)
		log R "Service did not become healthy; diagnostics saved to ${diag_log}"
		rollback_installed_binaries
		return 1
	fi

	# Verify installation by checking versions
	if [[ -x ${INSTALLED_TS_PATH} && -x ${INSTALLED_TD_PATH} ]]; then
		local client_version="unknown" daemon_version="unknown" restart_hint=""
		client_version=$(binary_version "${INSTALLED_TS_PATH}" tailscale || true)
		[[ -z ${client_version} ]] && client_version="unknown"
		if tailscaled_service_active; then
			sleep 2
			# Prefer the live daemon's self-reported version. Fall back to the
			# exact service binary path instead of a stale PATH shadow copy.
			daemon_version=$("${INSTALLED_TS_PATH}" status --json 2>/dev/null | grep -o '"Self":{[^}]*"TailscaleVersion":"[^"]*"' | sed 's/.*TailscaleVersion":"\([^"]*\)".*/\1/' || true)
			[[ -z ${daemon_version} ]] && daemon_version="unknown"
			if [[ ${daemon_version} == "unknown" ]]; then
				daemon_version=$(binary_version "${INSTALLED_TD_PATH}" tailscaled || true)
				[[ -z ${daemon_version} ]] && daemon_version="unknown"
			fi
		fi
		echo -e "\n🎉 Installation completed!\n\nVersion verification:"
		echo -e "  Client (tailscale):  ${client_version}\n  Daemon (tailscaled): ${daemon_version}"
		if [[ ${client_version} != "${daemon_version}" && ${client_version} != "unknown" && ${daemon_version} != "unknown" ]]; then
			if has_unit tailscaled.service; then
				restart_hint="${SUDO}${SUDO:+ }systemctl restart tailscaled"
			else
				local openrc_name=""
				openrc_name=$(openrc_service_name || true)
				restart_hint="${SUDO}${SUDO:+ }rc-service ${openrc_name:-tailscaled} restart"
			fi
			log R "Version mismatch detected; run: ${restart_hint}"
			rollback_installed_binaries
			return 1
		fi
		echo ""
	else
		echo -e "\n🎉 Installation completed!\n"
	fi
	ROLLBACK_AVAILABLE=false

	echo -e "Quick Start:"
	echo -e "  tailscale up\n"
	show_awg_guidance
}

main "$@"
