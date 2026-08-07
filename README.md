# Tailscale with AmneziaWG v2 and v3

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20OpenWrt%20|%20Android%20|%20iOS-blue)](#platform-support)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](LICENSE)

This project installs a Tailscale fork with AmneziaWG obfuscation while retaining the official Tailscale and Headscale control-plane behavior. With every AWG field disabled it behaves like standard Tailscale.

Release `v1.102.2` and newer support both profiles:

- **AWG v3 (recommended)**: header protection, transport content padding, randomized timing ranges, junk traffic, CPS packets, and header/handshake masquerading.
- **AWG v2 (compatibility mode)**: the existing `jc`, `jmin`, `jmax`, `s1`-`s4`, `h1`-`h4`, and `i1`-`i5` profile format remains supported.

Languages: [English](README.md) | [中文](doc/README-zh.md) | [فارسی](doc/README-fa.md) | [Русский](doc/README-ru.md)

Historical AWG 1.5 notes: [doc/README-awg-v1.5.md](doc/README-awg-v1.5.md).

## Installation

The installers select the latest stable fork release by default. Where the platform installation model permits, they preserve the existing CLI/service state and AWG preferences, run a read-only migration check, install matching client/daemon binaries, and print version-aware v2/v3 guidance. They never generate or overwrite an AWG profile automatically. Switching macOS from Tailscale.app to the CLI/utun service still requires re-authentication because those installation models do not share state.

Before replacement, each desktop installer checks architecture and embedded version, and verifies GitHub's SHA-256 asset digest when trusted release metadata is directly reachable and publishes one. The binary-replacement transaction keeps recovery copies and preserves existing service configuration; incomplete rollback leaves those copies on disk instead of deleting them. Linux supports both systemd and OpenRC; Windows GUI installs require an exact official-version match.

On Linux, a distribution-package upgrade—and on macOS, a Homebrew formula upgrade—can restore the official binaries. If AWG commands disappear after a package update, rerun this installer and confirm `tailscale version` again.

| Platform | Command / Action |
| --- | --- |
| Linux | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` |
| macOS | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` |
| Windows (Admin PowerShell) | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` |
| OpenWrt | See [OpenWrt](#openwrt) |
| Android | Download the APK from [tailscale-android releases](https://github.com/LiuTangLei/tailscale-android/releases) |
| iOS | Experimental [AwgScale](https://github.com/LiuTangLei/AwgScale); ordinary signing supports app-only features, while system VPN requires TrollStore or Packet Tunnel entitlement |

To install a specific published release:

```bash
# Linux
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --version v1.102.2

# macOS
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --version v1.102.2
```

```powershell
# Windows, in an Administrator PowerShell
$code = (iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content
& ([scriptblock]::Create($code)) -Version v1.102.2
```

macOS uses CLI-only `tailscaled` with a utun interface. The installer asks before migrating an App Store/standalone Tailscale app and stages the App bundle for rollback; macOS cannot automatically re-enable a System/Network Extension that the user disabled during migration.

## Quick start

Log in using the normal control server:

```bash
# Official Tailscale
tailscale up

# Headscale
tailscale up --login-server https://your-headscale-domain
```

Generate a profile:

```bash
tailscale awg set
```

On `v1.102.2+`, the interactive generator offers:

1. **AWG v3** — recommended and selected when you press Enter.
2. **AWG v2** — select `2` for older peers and mobile/router clients that do not yet contain a v3-capable core.

The generated JSON is shown before it is applied. Keep that JSON as the source of truth. Apply it to the other participating nodes, or run `tailscale awg sync` from a compatible online peer.

```bash
tailscale awg get
tailscale awg validate # v1.102.2+
tailscale awg sync
tailscale awg reset
```

## Compatibility matrix

| Local/peer profile | Requirement | Result |
| --- | --- | --- |
| All AWG fields disabled | Any standard Tailscale/WireGuard peer | Standard WireGuard behavior |
| Only `jc`/`jmin`/`jmax` or `i1`-`i5` | May differ per node | Extra pre-handshake junk; standard peers ignore it |
| AWG v2 `s1`-`s4` and `h1`-`h4` | All communicating AWG peers use matching values | AWG v2 communication |
| AWG v3 | Every communicating peer has a v3-capable core and matching shared fields | AWG v3 communication |
| AWG v2 profile on `v1.102.2+` | Supported v2 fields | Supported; applying v2 clears stale v3-only state |

Do not enable a v3 profile on only one side. A v3-capable binary can run either v2 or v3, but communicating nodes must use compatible active profiles.

## What AWG v3 adds

AWG v3 retains all v2 fields and adds:

| JSON field | Purpose | Coordination |
| --- | --- | --- |
| `header_protection_key` | 32-byte key encoded as 64 hex characters for packet-header protection | Must match on communicating v3 nodes; non-zero key requires `s1`-`s4 >= 12` |
| `content_padding_addition` | Random transport-content padding range | May differ per node |
| `rekey_after_time` | Randomized rekey interval | Local timing; may differ |
| `rekey_timeout` | Randomized handshake retry timeout | Local timing; may differ |
| `reject_after_time` | Randomized session rejection limit | Local timing; may differ |
| `keepalive_timeout` | Randomized keepalive timeout | Local timing; may differ |
| `max_handshake_attempts` | Randomized handshake-attempt limit | Local behavior; may differ |

The v3 generator creates fresh ranges and a fresh header-protection key. Do not copy a fixed key from documentation; generate one profile and distribute its shared fields to the intended peers.

## AWG v2 compatibility

These v2 fields remain supported in `v1.102.2+`:

- `jc`, `jmin`, `jmax`: pre-handshake junk packet count and size.
- `s1`-`s4`: packet prefixes/padding; must match across communicating AWG peers.
- `h1`-`h4`: scalar values or `{ "min": ..., "max": ... }` ranges; effective ranges must not overlap and shared values must match.
- `i1`-`i5`: optional CPS packets; may differ per node.

Common CPS tags include:

- `<b 0xHEX>`: static bytes.
- `<r N>`: random bytes.
- `<rc N>`: random ASCII letters.
- `<rd N>`: random decimal digits.
- `<t>`: Unix timestamp.

> Compatibility: AmneziaWG removed the legacy CPS `<c>` counter in the `amneziawg-go v0.2.16` AWG 2 refactor; this fork inherited the change in `v1.98.1`, so remove that tag from old `i1`-`i5` values.

## Upgrade from older releases

1. Save the current version and profile:

   ```bash
   tailscale version
   tailscale awg get
   ```

2. Run the installer. Existing login state and preferences are preserved where the platform installation model permits it.
3. Decide whether to keep v2 or migrate the whole communicating group to v3.
4. For v3, upgrade every participating node to a v3-capable build, generate one v3 profile, then distribute/sync it.
5. Follow the restart prompt after `tailscale awg set` or `tailscale awg sync`; `v1.102.2` recommends restarting by default after either command.

Upgrading the binary alone does not convert an active v2 profile into v3.

## Docker Compose

The included [docker-compose.yml](docker-compose.yml) uses `ltlei/tailscale-awg:latest` and persists state in `./tailscale-state`.

When migrating from the older host bind mount `/var/lib/tailscale:/var/lib/tailscale`, stop every process using that state before copying it. Do not run a host daemon and the container from the same node state at the same time.

```bash
docker compose down
# If a host service also uses this directory, stop the matching one:
# systemd: sudo systemctl stop tailscaled
# OpenRC:  sudo rc-service tailscaled stop || sudo rc-service tailscale stop
mkdir -p ./tailscale-state
cp -a /var/lib/tailscale/. ./tailscale-state/
```

```bash
docker compose pull
docker compose up -d
docker compose exec tailscaled tailscale up
docker compose exec tailscaled tailscale awg set
```

For Headscale, replace the login command with `docker compose exec tailscaled tailscale up --login-server https://your-headscale-domain`.

Verify that the pulled image reports `v1.102.2` or newer before selecting v3:

```bash
docker compose exec tailscaled tailscale version
```

The Compose service/container is named `tailscaled`; the CLI binary inside it is `tailscale`:

```bash
docker exec -it tailscaled tailscale awg get
```

## OpenWrt

```bash
wget -O /usr/bin/install.sh https://raw.githubusercontent.com/LiuTangLei/openwrt-tailscale-awg/main/install_en.sh
chmod +x /usr/bin/install.sh
/usr/bin/install.sh
```

For restricted GitHub access:

```bash
wget -O /usr/bin/install.sh https://ghfast.top/https://raw.githubusercontent.com/LiuTangLei/openwrt-tailscale-awg/main/install.sh
chmod +x /usr/bin/install.sh
/usr/bin/install.sh
```

OpenWrt, Android, and iOS are released separately. Check the actual client/core version before syncing a v3 profile; use v2 when any participating client is not yet v3-capable.

## Mirrors

The Linux/macOS installers accept `--mirror PREFIX`; Windows accepts `-MirrorPrefix`:

```bash
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com
```

```powershell
$code = (iwr -useb https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content
& ([scriptblock]::Create($code)) -MirrorPrefix 'https://your-mirror-site.com'
```

## Troubleshooting

Check that the client and daemon are the same version:

```bash
tailscale version
tailscale awg get
tailscale awg validate # v1.102.2+
```

If `tailscale ping` works but normal traffic does not, remember that the default `tailscale ping` is a disco-layer check and does not pass through both TUN devices. Reset AWG and restore parameters progressively:

```bash
tailscale awg reset
tailscale awg set '{"jc":2,"jmin":64,"jmax":128}'
```

## Platform support

| Platform | Architecture | Installer/status |
| --- | --- | --- |
| Linux | x86_64, ARM64 | Installer in this repository |
| macOS | Intel, Apple Silicon | CLI/utun installer in this repository |
| Windows | x86_64, ARM64 | Administrator PowerShell installer |
| OpenWrt | Release-dependent | Separate installer repository |
| Android | Universal APK (ARM64, ARM, x86_64, x86) | Separate APK release |
| iOS | iPhone/iPad (iOS 15+) | Experimental separate client; system VPN requires TrollStore or Packet Tunnel entitlement |

## Links

- Tailscale fork releases: <https://github.com/LiuTangLei/tailscale/releases>
- Android APK: <https://github.com/LiuTangLei/tailscale-android/releases>
- iOS client: <https://github.com/LiuTangLei/AwgScale>
- Installer issues: <https://github.com/LiuTangLei/tailscale-awg-installer/issues>
- AmneziaWG upstream: <https://github.com/amnezia-vpn/amneziawg-go>

## License

BSD 3-Clause License, matching upstream Tailscale.
