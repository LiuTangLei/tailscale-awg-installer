# Tailscale with AmneziaWG and QUIC

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20OpenWrt%20|%20Android%20|%20iOS-blue)](#platform-support)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](LICENSE)

This project installs a Tailscale fork with optional AmneziaWG or QUIC with built-in obfuscation while retaining the official Tailscale and Headscale control-plane behavior. The default remains native WireGuard; in native mode, disabling every AWG field restores standard WireGuard behavior. Upgrading does not automatically switch an existing node to QUIC.

**Latest integrated release: [v1.102.4](https://github.com/LiuTangLei/tailscale/releases/tag/v1.102.4), corrected and republished on 2026-09-17.** This release keeps the upstream 1.102.4 base, unifies AWG / QUIC selection, and fixes restricted-path QUIC handshakes and early-packet loss during simultaneous connections. Upgrade the CLI and daemon together. QUIC uses the built-in HTTP/3 obfuscation; it is one user-facing option, not a separate H3 choice. Mobile/router releases remain separate.

**Already installed 1.102.4? Check the long version.** The current build is `1.102.4-73-t1f00235ed` and includes automatic verified activation. Earlier `t63c1da827`, `te2474993a` and `t98abfff62` builds do not contain the complete activation flow. Rerun the installer below, or pull and recreate Docker containers, to replace an older same-name build. The release name remains v1.102.4; r1/r2 are no longer separate binary download choices.

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
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --version v1.102.4

# macOS
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --version v1.102.4
```

```powershell
# Windows, in an Administrator PowerShell
$code = (iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content
& ([scriptblock]::Create($code)) -Version v1.102.4
```

The Windows installer can run while the normal Tailscale service is active. It validates the service-owned process tree, then stops and restarts the service during the transactional update. Only an independent `tailscaled.exe` outside that process tree must be stopped manually.

macOS uses CLI-only `tailscaled` with a utun interface. The installer asks before migrating an App Store/standalone Tailscale app and stages the App bundle for rollback; macOS cannot automatically re-enable a System/Network Extension that the user disabled during migration.

## Mobile QUIC previews — 1.102.4

[Android 1.102.4 preview](https://github.com/LiuTangLei/tailscale-android/releases/tag/v1.102.4)
and [AwgScale iOS 1.102.4 preview](https://github.com/LiuTangLei/AwgScale/releases/tag/v1.102.4)
use the same corrected core (`1f00235ed2ce`) as the desktop release. Each exposes
one QUIC choice and activates changes by restarting its actual backend; the
interface verifies the running mode instead of accepting a pending selection.

**Android:** 52 unit tests and an isolated emulator's real VPN upload/download
and QUIC/AWG switching tests passed. Downloads include a development-signed test
APK and an unsigned optimized release APK. The original release-signing
credentials are not configured; the test signer is different from v1.102.2 and
cannot provide an in-place update. Do not uninstall a production installation
to try the preview. A new production-signed update is still pending.

**iOS:** an ad-hoc/TrollStore-oriented IPA (version 1.102.4, build 11) is available,
with 97 simulator tests and device compilation passed. It is not Apple
distribution-signed. Real-device system VPN/QUIC validation remains pending;
installation still requires an appropriate signing/entitlement environment.
These mobile releases are marked prerelease, without replacing the previous
stable mobile releases.

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

In the corrected `v1.102.4` build, the interactive setup offers:

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

## QUIC transport and switching (corrected v1.102.4)

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

For Docker or an isolated daemon that cannot safely restart the host's service, explicitly stage with `docker compose exec tailscaled tailscale awg set --no-restart --yes quic`, then run `docker compose restart tailscaled`. Other configuration commands accept `--no-restart` for the same purpose. A custom socket must never restart an unrelated host daemon. Preserve the **whole state directory**, including the managed transport identity and profile, not just `tailscaled.state`.

An optional node-wide server declaration is staged with `tailscale awg server --yes on`. Only a non-server node dialing an authenticated declared server uses the Chromium-inspired H3 ClientHello; server-to-server and ordinary mesh connections retain standard TLS. It is not a full browser fingerprint clone and does not automatically open or change listening ports. The command restarts the local service when activation is required.

To return to AWG, use `tailscale awg set` (select v2/v3 or pass your saved JSON) or confirm a profile with `tailscale awg sync`; service restart and activation checks run automatically. `tailscale awg reset` selects standard native WG when leaving QUIC. `transport --yes native` selects native without generating an AWG profile. Failed restart/activation is reported as an error, not as successfully applied.

`tailscale awg set --yes quic` includes automatic activation. Scripts that intentionally defer activation must add `--no-restart`; that is the only staging-only choice. The older `transport --yes http3-ip` command selects and activates the same obfuscated QUIC implementation. Internal/JSON mode names are unchanged for compatibility; human-readable status uses QUIC.

### QUIC connectivity fixes

Managed QUIC now starts with 1200-byte UDP payloads rather than assuming the path accepts a 1400-byte Initial. This avoids an authenticated-handshake black hole on smaller-MTU paths; the inner IP MTU and large-packet fragmentation remain unchanged. When both peers connect simultaneously, one authenticated losing connection can drain briefly instead of dropping its early IP packets; the selected primary, peer authorization and restart semantics are unchanged.

Forced-DERP and required-direct tests verify application bytes through simultaneous startup, idle recovery, rebind, and normal/abrupt peer restarts. These controlled tests are not a guarantee for every real NAT/relay or a new WireGuard throughput-parity claim. Upgrade both ends, and check `tailscale awg status`: a desired QUIC mode with `Pending restart: yes` is not an active QUIC connection. The ordinary version still starts with `1.102.4`; the current build's long version includes `t1f00235ed`.

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

The included [docker-compose.yml](docker-compose.yml) uses `ltlei/tailscale-awg:latest` and persists the complete state directory in `./tailscale-state`. Use `ltlei/tailscale-awg:v1.102.4` for the corrected release. Its tag was intentionally updated on 2026-09-17, so run `docker compose pull` and recreate the container even when the existing tag is already `v1.102.4`. Both `v1.102.4` and `latest` resolve to the verified multi-platform digest `sha256:a4af941a384527367249f0675f85e662106b33b870fdf6d8386b918af9e3a9a9`. The legacy r1 Docker alias also redirects to the corrected image; it is no longer recommended as an installation choice.

**Upgrade the image and Compose configuration together.** Keep the image's `containerboot` command; do not override it with `command: tailscaled ...`. The wrapper interprets `TS_STATE_DIR`, `TS_SOCKET`, `TS_AUTHKEY`, `TS_EXTRA_ARGS`, `TS_USERSPACE` and other supported `TS_*` variables. The supplied configuration uses persistent state and kernel networking. `TS_AUTH_ONCE=true` preserves an authenticated node across restarts; later login/up options are not automatically reapplied by that mode.

For unattended initial login, set `TS_AUTHKEY` via your private deployment environment and, for Headscale, `TS_EXTRA_ARGS=--login-server=https://your-headscale-domain --accept-routes`. Never commit an auth key. Without an auth key, complete login using the CLI below. The fixed CLI/image in v1.102.4 and the restored wrapper are both needed to resolve [issue #18](https://github.com/LiuTangLei/tailscale-awg-installer/issues/18): older `tailscale up` calls could overwrite a saved AWG profile during restart. `up --reset` now preserves the separately managed AWG profile too; use `tailscale awg reset` to disable it explicitly.

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

Verify that both the client and daemon report `1.102.4` or newer before relying on the Docker fix or enabling H3:

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

OpenWrt, Android, and iOS are released separately. Android/iOS 1.102.4 QUIC previews are available as described above; this desktop/Docker release does not itself bundle them or publish a new router package. Check the actual client/core version before syncing a v3 profile; use v2 when any participating client is not yet v3-capable. Do not enable QUIC on a group containing clients without compatible QUIC support.

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
