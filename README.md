# Tailscale with AmneziaWG and QUIC

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20OpenWrt%20|%20Android%20|%20iOS-blue)](#platform-support)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](LICENSE)

This project installs a Tailscale fork with optional AmneziaWG or QUIC with built-in obfuscation while retaining the official Tailscale and Headscale control-plane behavior. The default remains native WireGuard; in native mode, disabling every AWG field restores standard WireGuard behavior. Upgrading does not automatically switch an existing node to QUIC.

QUIC with built-in obfuscation is supported starting with `v1.102.4`.

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
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --version v1.102.5-r1

# macOS
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --version v1.102.5-r1
```

```powershell
# Windows, in an Administrator PowerShell
$code = (iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content
& ([scriptblock]::Create($code)) -Version v1.102.5-r1
```

The Windows installer can run while the normal Tailscale service is active. It validates the service-owned process tree, then stops and restarts the service during the transactional update. Only an independent `tailscaled.exe` outside that process tree must be stopped manually.

macOS uses CLI-only `tailscaled` with a utun interface. The installer asks before migrating an App Store/standalone Tailscale app and stages the App bundle for rollback; macOS cannot automatically re-enable a System/Network Extension that the user disabled during migration.

## Mobile clients

Android and iOS are released separately: download the signed APK from [Android releases](https://github.com/LiuTangLei/tailscale-android/releases) or a preview IPA from [AwgScale releases](https://github.com/LiuTangLei/AwgScale/releases). iOS system VPN requires TrollStore or an appropriate signing/entitlement environment; the IPA is not Apple distribution-signed.

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

The interactive setup offers:

1. **AWG v3** — recommended AWG profile and selected when you press Enter.
2. **AWG v2** — select `2` for older compatible peers.
3. **QUIC** — select `3` for built-in obfuscation and automatic AWG clearing.

Selecting AWG or confirming `tailscale awg sync` while QUIC is active saves native mode with the chosen AWG profile, automatically restarts the local service, and verifies activation. No separate `transport native`, restart, then repeat-set sequence or second restart confirmation is needed. Keep an independent administration connection: changing the transport briefly disconnects VPN traffic.

The generated JSON is shown before it is applied. Keep that JSON as the source of truth. Apply it to the other participating nodes, or run `tailscale awg sync` from a compatible online peer.

```bash
tailscale awg get
tailscale awg validate # v1.102.2+
tailscale awg sync
tailscale awg reset
```

## QUIC transport and switching

HTTP/3 carries IP packets directly over authenticated QUIC DATAGRAMs; it is not WireGuard wrapped inside QUIC. It includes automatic node-key-based peer authentication, staged identity/profile management, bounded packet batching, direct authenticated receive delivery and shared receive-buffer improvements. These changes do not establish universal WireGuard throughput parity or make the traffic indistinguishable from a browser.

Upgrade every participating node before switching. Transport selection is node-wide: a QUIC node does not automatically fall back to native WG/AWG for an older peer. Selecting QUIC automatically clears the saved AWG profile; saving its JSON first is useful for later restoration, but a manual reset is no longer required. Clearing AWG can interrupt existing native AWG links, so keep another administration path.

```bash
tailscale awg status
# Optional: keep a copy of the existing AWG profile.
tailscale awg get
# Select QUIC with built-in obfuscation and automatically clear AWG.
tailscale awg set --yes quic
# The command restarts the local service and checks that QUIC is active.
tailscale awg status
tailscale awg doctor
```

With a CLI supporting `--no-restart` (including v1.104.1), for Docker or an isolated daemon that cannot safely restart the host's service, explicitly stage with `docker compose exec tailscaled tailscale awg set --no-restart --yes quic`, then run `docker compose restart tailscaled`. Other configuration commands accept `--no-restart` for the same purpose. A custom socket must never restart an unrelated host daemon. Preserve the **whole state directory**, including the managed transport identity and profile, not just `tailscaled.state`. The older fixed `ltlei/tailscale-awg:v1.102.4` image does not accept `--no-restart`; see the version-specific Docker instructions below.

An optional node-wide server declaration is staged with `tailscale awg server --yes on`. Only a non-server node dialing an authenticated declared server uses the Chromium-inspired H3 ClientHello; server-to-server and ordinary mesh connections retain standard TLS. It is not a full browser fingerprint clone and does not automatically open or change listening ports. The command restarts the local service when activation is required.

To return to AWG, use `tailscale awg set` (select v2/v3 or pass your saved JSON) or confirm a profile with `tailscale awg sync`; service restart and activation checks run automatically. `tailscale awg reset` selects standard native WG when leaving QUIC. `transport --yes native` selects native without generating an AWG profile. Failed restart/activation is reported as an error, not as successfully applied.

`tailscale awg set --yes quic` includes automatic activation. Scripts that intentionally defer activation must add `--no-restart`; that is the only staging-only choice. The older `transport --yes http3-ip` command selects and activates the same obfuscated QUIC implementation. Internal/JSON mode names are unchanged for compatibility; human-readable status uses QUIC.

## Compatibility matrix

| Local/peer profile | Requirement | Result |
| --- | --- | --- |
| Native mode, all AWG fields disabled | Any standard Tailscale/WireGuard peer | Standard WireGuard behavior |
| QUIC | Compatible QUIC builds on every communicating node; AWG automatically cleared | Direct QUIC-IP transport; no automatic WG fallback |
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
5. The current `tailscale awg set` and `tailscale awg sync` commands restart the local service when needed and verify activation after confirmation; use `--no-restart` only for deliberate staged changes.

Upgrading the binary alone does not convert an active v2 profile into v3.

## Docker Compose

The included [docker-compose.yml](docker-compose.yml) uses `ltlei/tailscale-awg:latest` and persists the complete state directory in `./tailscale-state`. To update, pull the image and recreate the container. **GitHub binaries and Docker images are released separately.** As of 2026-10-08, the GitHub `v1.104.1` release is available but the Docker Hub `ltlei/tailscale-awg:v1.104.1` tag does not exist. The remote Docker `latest` currently reports `1.102.4-73-t1f00235ed` and already supports `--no-restart`; its short version is not enough to distinguish it from the older fixed `v1.102.4` image. Do not infer the Docker version from the GitHub release or a locally cached `latest` image; check the container after pulling.

**Upgrade the image and Compose configuration together.** Keep the image's `containerboot` command; do not override it with `command: tailscaled ...`. The wrapper interprets `TS_STATE_DIR`, `TS_SOCKET`, `TS_AUTHKEY`, `TS_EXTRA_ARGS`, `TS_USERSPACE` and other supported `TS_*` variables. The supplied configuration uses ordinary bridge networking, `/dev/net/tun` and `NET_ADMIN`, without `privileged`, `SYS_ADMIN` or host networking. TUN routes exist inside the container network namespace; they are not automatically installed on the host. `TS_AUTH_ONCE=true` preserves an authenticated node across restarts; later login/up options are not automatically reapplied by that mode.

For unattended initial login, set `TS_AUTHKEY` via your private deployment environment and, for Headscale, `TS_EXTRA_ARGS=--login-server=https://your-headscale-domain --accept-routes`. Never commit an auth key. Without an auth key, complete login using the CLI below. `up --reset` preserves the separately managed AWG profile; use `tailscale awg reset` to disable it explicitly.

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
```

For Headscale, replace the login command with `docker compose exec tailscaled tailscale up --login-server https://your-headscale-domain`.

Check the client and daemon versions before configuring the transport:

```bash
docker compose exec tailscaled tailscale version
```

The Compose service/container is named `tailscaled`; the CLI binary inside it is `tailscale`:

```bash
docker exec -it tailscaled tailscale awg get
```

### Permissions and routing

The default TUN example adds only `NET_ADMIN` and retains Docker's default capabilities. `cap_drop: [ALL]` plus `NET_ADMIN` also passed our current-kernel test, but some older kernels/legacy iptables paths need `NET_RAW`; do not assume the stricter capability set works everywhere.

For a TUN exit node or subnet router, uncomment the IPv4/IPv6 forwarding `sysctls` in the Compose file and advertise the intended routes, for example `TS_EXTRA_ARGS=--advertise-exit-node` on initial login. Approve the exit node/routes in Tailscale's admin console or Headscale. With `TS_AUTH_ONCE=true` and an already authenticated node, explicitly apply the desired settings, such as `docker compose exec tailscaled tailscale set --advertise-exit-node`; changing the environment alone will not re-run `up`.

Use `network_mode: host` only when you intentionally need the daemon to manage the host network namespace, such as a host-integrated gateway. It is not required for ordinary direct WG/AWG traffic. With host networking, configure forwarding on the host rather than setting container-network `sysctls`, and do not add `privileged` or `SYS_ADMIN` merely for AWG.

### Userspace without extra capabilities

Save this as a **standalone** `compose.userspace.yml` instead of merging it over the TUN example:

```yaml
services:
  tailscaled:
    image: ltlei/tailscale-awg:latest
    container_name: tailscaled
    restart: unless-stopped
    cap_drop:
      - ALL
    volumes:
      - ./tailscale-state:/var/lib/tailscale
    environment:
      TS_STATE_DIR: /var/lib/tailscale
      TS_SOCKET: /var/run/tailscale/tailscaled.sock
      TS_USERSPACE: "true"
      TS_AUTH_ONCE: "true"
      TS_SOCKS5_SERVER: 0.0.0.0:1055
      TS_OUTBOUND_HTTP_PROXY_LISTEN: 0.0.0.0:1056
      # TS_AUTHKEY: ${TS_AUTHKEY}
    ports:
      - "127.0.0.1:1055:1055"
      - "127.0.0.1:1056:1056"
```

Start with `docker compose -f compose.userspace.yml up -d`; use the same `-f` option for subsequent commands. This mode needs no TUN device or added capability. Applications access the tailnet through SOCKS5/HTTP proxies on the published localhost ports, for example `curl --proxy socks5h://127.0.0.1:1055 http://<peer>:<port>/`. A sidecar can share `network_mode: service:tailscaled` and use these proxies at `127.0.0.1`; sharing the namespace alone does not create TUN routes in userspace mode. The host OS does not automatically gain tailnet routes.

### Apply AWG parameters with the installed CLI

Run `docker compose exec tailscaled tailscale version` and `docker compose exec tailscaled tailscale awg set --help` first. Replace `<JSON>` with your group's matching AWG parameters.

When **`awg set --help` lists `--no-restart`**, stage the configuration and then restart from the host. This includes v1.104.1 and the Docker `latest` verified above:

```bash
docker compose exec tailscaled tailscale awg set --no-restart '<JSON>'
docker compose restart tailscaled
```

For the **older fixed `ltlei/tailscale-awg:v1.102.4` image** (commit `63c1da827`), whose CLI does not support `--no-restart`:

```bash
docker compose exec tailscaled tailscale awg set '<JSON>'
docker compose restart tailscaled
```

Keep the image's `containerboot` and persist the **whole state directory**, including AWG/QUIC profiles and identities. Do not replace the entrypoint to work around configuration persistence.

Userspace supports direct AWG UDP when the network permits it. Both the published v1.102.4 image and v1.104.1 candidate binaries passed isolated userspace/TUN direct and forced-DERP tests with payload verification and restart persistence. This does not establish that v1.104.1 fixes a reporter's DERP-only WAN path. For that case, collect both peers' `tailscale version`, `tailscale netcheck`, `tailscale ping <peer>`, `tailscale ping --tsmp <peer>` and `tailscale awg validate`; check matching parameters, UDP/NAT, transparent proxies and policy routing. A disco ping alone does not verify the encrypted data path.

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

OpenWrt, Android, and iOS are released separately; use the platform-specific downloads linked above. Check the actual client/core version before syncing a v3 profile; use v2 when any participating client is not yet v3-capable. Do not enable QUIC on a group containing clients without compatible QUIC support.

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
