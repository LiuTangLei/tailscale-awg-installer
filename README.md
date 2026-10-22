# Tailscale + AmneziaWG / QUIC

[中文](doc/README-zh.md) · [فارسی](doc/README-fa.md) · [Русский](doc/README-ru.md) · [Releases](https://github.com/LiuTangLei/tailscale/releases/latest)

A Tailscale fork with AmneziaWG and obfuscated QUIC transports. It works with the official Tailscale control plane and Headscale, and behaves like standard Tailscale until you choose another transport.

[![Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=release)](https://github.com/LiuTangLei/tailscale/releases/latest) [![Docker](https://img.shields.io/docker/v/ltlei/tailscale-awg?sort=semver&label=docker)](https://hub.docker.com/r/ltlei/tailscale-awg/tags)

Version numbers follow upstream: fork `vX.Y.Z` is based on Tailscale `vX.Y.Z`.

## Features

- **Three node-wide transports**: standard WireGuard (default), AWG v3 / v2, and QUIC.
- **AWG v3**: header protection, payload padding and randomized timing. AWG v2 remains available for older peers.
- **QUIC**: HTTP/3 over TLS with tuned BBRv3. Peers trust each other by node key automatically, so there are no parameters to sync.
- **0-RTT reconnects** between v1.104.2+ nodes, with single-use tickets and a full-handshake fallback. QUIC peers on v1.104.1 stay compatible.
- **Better under reordering**: reordered QUIC packets are no longer dropped as duplicates.
- **Optional server role**: `tailscale awg server on` makes clients use a Chromium-style TLS ClientHello when they connect to this node.
- **One-command switching** with automatic restart, plus `tailscale awg doctor` for diagnostics.
- **Safe upgrades**: installers check SHA-256 digests, roll back on failure and keep the active transport.

## Install

| Platform | Install / download | Version |
| --- | --- | --- |
| Linux | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` | [![release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=)](https://github.com/LiuTangLei/tailscale/releases/latest) |
| macOS | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` | [![release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=)](https://github.com/LiuTangLei/tailscale/releases/latest) |
| Windows (Admin PowerShell) | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` | [![release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=)](https://github.com/LiuTangLei/tailscale/releases/latest) |
| Docker | `ltlei/tailscale-awg:latest` ([see below](#docker)) | [![docker](https://img.shields.io/docker/v/ltlei/tailscale-awg?sort=semver&label=)](https://hub.docker.com/r/ltlei/tailscale-awg/tags) |
| OpenWrt | [Installer, packages and feed](https://github.com/LiuTangLei/openwrt-tailscale-awg) | [![openwrt](https://img.shields.io/github/v/release/LiuTangLei/openwrt-tailscale-awg?label=)](https://github.com/LiuTangLei/openwrt-tailscale-awg/releases/latest) |
| Android | [Signed APK](https://github.com/LiuTangLei/tailscale-android/releases/latest) | [![android](https://img.shields.io/github/v/release/LiuTangLei/tailscale-android?label=)](https://github.com/LiuTangLei/tailscale-android/releases/latest) |
| iOS | [AwgScale IPA](https://github.com/LiuTangLei/AwgScale/releases/latest) | [![ios](https://img.shields.io/github/v/release/LiuTangLei/AwgScale?include_prereleases&label=)](https://github.com/LiuTangLei/AwgScale/releases) |

- Prefer to install by hand? See the [manual installation guide](doc/manual-install.md) for Linux, macOS, Windows, OpenWrt and mobile.
- Desktop installers install the latest release on x86_64 / ARM64. Add `--version <tag>` (Windows: `-Version <tag>`) to pin a release. On Linux / macOS, `--uninstall` removes it.
- macOS uses the CLI/utun daemon; moving from Tailscale.app requires signing in again.
- The Windows GUI must match the fork's base Tailscale version.
- iOS needs TrollStore or a Packet Tunnel entitlement; the IPA is not App Store signed.
- A system package update may restore official binaries. Rerun the installer if `tailscale awg` disappears.

## GitHub mirrors

If GitHub is slow or blocked, put a mirror prefix in front of the script URL and pass the same prefix to the installer. Linux and macOS use `--mirror`; Windows uses `-MirrorPrefix` or the `MIRROR_PREFIX` environment variable.

```bash
# macOS: replace install-linux.sh with install-macos.sh
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \
  | bash -s -- --mirror https://ghfast.top
```

```powershell
$m = 'https://ghfast.top'
$code = (iwr -useb "$m/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1").Content
& ([scriptblock]::Create($code)) -MirrorPrefix $m
```

| Mirror | Notes |
| --- | --- |
| `https://ghfast.top` | Default in the OpenWrt installer |
| `https://gh-proxy.org` | Used by the OpenWrt installer |
| `https://gh-proxy.com` | Also proxies the GitHub API |
| Your own | Any proxy that serves `https://<mirror>/https://github.com/...`, for example a self-hosted [gh-proxy](https://github.com/hunshcn/gh-proxy) on Cloudflare Workers or Docker |

- The installer finds the latest release through `api.github.com`, first directly and then through the mirror. Most mirrors do not proxy the API; if the lookup fails, use `gh-proxy.com` or add `--version <tag>` with the tag shown in the badge above.
- Public mirrors are third-party services that can change or go offline. Use your own for important machines.
- OpenWrt: the installer tries these mirrors automatically; use `install.sh --custom-proxy` for your own.

## Connect and configure

```bash
tailscale up
```

For Headscale: `tailscale up --login-server https://your-headscale-domain`.

| Action | Command |
| --- | --- |
| Choose AWG v3 (default), v2 or QUIC | `tailscale awg set` |
| Enable QUIC | `tailscale awg set --yes quic` |
| Show / save AWG JSON | `tailscale awg get` |
| Apply saved JSON | `tailscale awg set '<JSON>'` |
| Copy a compatible online peer's profile | `tailscale awg sync` |
| Declare this node a QUIC server | `tailscale awg server on` |
| Return to standard WireGuard | `tailscale awg reset` |
| Check active mode / diagnose | `tailscale awg status` / `tailscale awg doctor` |

- AWG peers need matching shared fields. Generate a profile once, save the JSON, then distribute or sync it.
- QUIC applies to the whole node and every communicating node must enable it. There is no automatic fallback to WireGuard. Enabling QUIC clears the AWG profile, so save the JSON first if you need it later.
- Transport changes restart the local service and briefly interrupt VPN traffic. Keep another way to reach remote machines.

## Docker

Use [docker-compose.yml](docker-compose.yml) with `ltlei/tailscale-awg:latest` or `:v1.104` (follows the latest patch release). Images are available for amd64, arm64, arm/v7 and 386.

```bash
curl -fsSLO https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/docker-compose.yml
docker compose pull
docker compose up -d
docker compose exec tailscaled tailscale up
```

For Headscale, append `--login-server https://your-headscale-domain`. For unattended login, provide `TS_AUTHKEY` privately and never commit it.

Inside a container, stage transport changes and then restart the container:

```bash
docker compose exec tailscaled tailscale awg set --no-restart --yes quic
docker compose restart tailscaled
```

For AWG, replace `--yes quic` with `'<JSON>'`.

- Keep the image's `containerboot` command and the **whole** `./tailscale-state` directory. Never share live node state between daemons.
- TUN mode needs `/dev/net/tun` and `NET_ADMIN`; routes apply inside the container. Exit nodes and subnet routers also need forwarding and approval in the control plane. With `TS_AUTH_ONCE=true`, later routing changes need an explicit `tailscale set`.
- Without TUN or extra capabilities, use [compose.userspace.yml](compose.userspace.yml) **on its own** (`docker compose -f compose.userspace.yml up -d`, and the same `-f` for later commands). Applications must use its SOCKS5 proxy on `1055` or HTTP proxy on `1056`.

## Troubleshooting

Check `tailscale version`, `tailscale netcheck`, `tailscale awg doctor` and `tailscale ping --tsmp <peer>`. A plain `tailscale ping` alone does not prove application traffic works. When reporting an [issue](https://github.com/LiuTangLei/tailscale-awg-installer/issues), include both peers' versions and diagnostics.

[BSD 3-Clause License](LICENSE) · [Tailscale](https://github.com/tailscale/tailscale) · [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-go)
