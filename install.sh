#!/bin/sh
# Portable entry point; ASUS firmware does not require Bash.
set -eu
umask 077

die() { printf '%s\n' "Tailscale installer: $*" >&2; exit 1; }
usage() {
    cat <<'EOF'
Usage: /bin/sh install.sh [OPTIONS]
Detect ASUS stock/Merlin, Linux or macOS and run its installer.

ASUS:        --no-menu       Install without opening the management menu
Linux/macOS: --version TAG, --pre-release, --mirror PREFIX, --uninstall
All:         --help, -h

ASUS requires ARM64/ARMv7 and uses automatic download mirrors.
Stock firmware needs an existing fwtool custom-init or Entware startup hook.
EOF
}

for option do
    case "$option" in --help|-h) usage; exit 0;; esac
done

case "$(uname -s)" in
    Linux)
        if [ -d /jffs ] && type nvram >/dev/null 2>&1 &&
           [ -n "$(nvram get productid 2>/dev/null)" ]; then
            platform=asus
        else
            platform=linux
        fi;;
    Darwin) platform=macos;;
    *) die 'supported systems: ASUS stock/Merlin, Linux and macOS';;
esac

if [ "$platform" = asus ]; then
    for option do
        case "$option" in
            --no-menu) ;;
            *) die "ASUS supports --no-menu; manage updates, rollback and uninstall through its menu ($option is not supported)";;
        esac
    done
    url=https://github.com/LiuTangLei/openwrt-tailscale-awg/releases/latest/download/install-asus.sh
    interpreter=/bin/sh
    shebang='#!/bin/sh'
    sources='https://gh-proxy.org https://ghfast.top direct'
else
    type bash >/dev/null 2>&1 || die 'Bash is required on Linux/macOS'
    url=https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-$platform.sh
    interpreter=bash
    shebang='#!/usr/bin/env bash'
    sources='direct https://gh-proxy.org https://ghfast.top'
    # Keep the native installer arguments intact, including a custom mirror.
    want_mirror=false
    for option do
        if [ "$want_mirror" = true ]; then
            case "$option" in
                https://*) sources="${option%/} $sources";;
                *) die '--mirror requires an HTTPS prefix';;
            esac
            want_mirror=false
        elif [ "$option" = --mirror ]; then
            want_mirror=true
        fi
    done
    [ "$want_mirror" = false ] || die '--mirror requires an HTTPS prefix'
fi
type curl >/dev/null 2>&1 || die 'curl is required'

work=${TMPDIR:-/tmp}/tailscale-awg-install.$$
mkdir "$work" || die 'cannot create a private temporary directory'
trap 'rm -rf "$work"' 0
trap 'exit 130' INT
trap 'exit 143' TERM HUP

for source in $sources; do
    case "$source" in direct) target=$url;; *) target=$source/$url;; esac
    rm -f "$work/install.part"
    if ! curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --connect-timeout 5 --max-time 30 "$target" -o "$work/install.part"; then
        continue
    fi
    first_line=''
    IFS= read -r first_line <"$work/install.part" || true
    if [ "$first_line" != "$shebang" ] || ! "$interpreter" -n "$work/install.part"; then
        printf '%s\n' 'Tailscale installer: invalid mirror response; trying another source' >&2
        continue
    fi
    mv "$work/install.part" "$work/install.sh"
    # Run once. A backend failure must never trigger a second installation.
    "$interpreter" "$work/install.sh" "$@"
    exit $?
done
die 'could not download the installer; no installation was started'
