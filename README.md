# Tailscale + AmneziaWG / QUIC

[中文](doc/README-zh.md) · [فارسی](doc/README-fa.md) · [Русский](doc/README-ru.md) · [Releases](https://github.com/LiuTangLei/tailscale/releases/latest)

Tailscale fork with optional AWG v2/v3 and obfuscated QUIC (since v1.102.4). Supports Tailscale and Headscale. Defaults to standard WireGuard; upgrading preserves the active transport.

## Install

Desktop installers use the latest stable release and support x86_64 / ARM64.

| Platform | Install / download |
| --- | --- |
| Linux | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` |
| macOS | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` |
| Windows (Admin PowerShell) | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` |
| OpenWrt | [Installer and packages](https://github.com/LiuTangLei/openwrt-tailscale-awg) |
| Android | [Signed APK](https://github.com/LiuTangLei/tailscale-android/releases/latest) |
| iOS | [AwgScale preview IPA](https://github.com/LiuTangLei/AwgScale/releases) |

- macOS uses CLI/utun; migrating from Tailscale.app requires signing in again.
- Windows GUI must match the fork's base Tailscale version. iOS system VPN requires TrollStore or Packet Tunnel entitlement; the IPA is not Apple distribution-signed.
- Package-manager updates can restore official binaries. Rerun the installer if AWG commands disappear.

## Connect and configure

```bash
tailscale up
```

For Headscale: `tailscale up --login-server https://your-headscale-domain`.

| Action | Command |
| --- | --- |
| Choose AWG v3 (default), v2, or QUIC | `tailscale awg set` |
| Enable QUIC | `tailscale awg set --yes quic` |
| Show / save AWG JSON | `tailscale awg get` |
| Apply saved JSON | `tailscale awg set '<JSON>'` |
| Copy a compatible online peer's profile | `tailscale awg sync` |
| Return to standard WireGuard | `tailscale awg reset` |
| Check active mode / diagnose | `tailscale awg status` / `tailscale awg doctor` |

- AWG peers need compatible profiles with matching shared fields. Generate once, save the JSON, then distribute or sync it.
- QUIC requires compatible builds on every communicating node, applies node-wide, and has no automatic WG fallback. Enabling it clears AWG; save the JSON first if you need it later.
- Transport changes automatically restart the local service and briefly disconnect VPN traffic. Keep another administration connection.

## Docker

Use [docker-compose.yml](docker-compose.yml) with image `ltlei/tailscale-awg:latest` or `:v1.104.1`. Supports amd64, arm64, arm/v7 and 386.

```bash
curl -fsSLO https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/docker-compose.yml
docker compose pull
docker compose up -d
docker compose exec tailscaled tailscale up
docker compose exec tailscaled tailscale version
```

For Headscale, append `--login-server https://your-headscale-domain` to `tailscale up`. For unattended login, supply `TS_AUTHKEY` privately; never commit it.

With v1.104.1, stage transport changes inside the container, then restart it:

```bash
docker compose exec tailscaled tailscale awg set --no-restart --yes quic
docker compose restart tailscaled
```

For AWG, replace `--yes quic` with `'<JSON>'`. Upgrade old images before using `--no-restart`.

- Keep `containerboot` and the **whole** `./tailscale-state` directory. Never share live node state between daemons.
- Default TUN mode needs `/dev/net/tun` and `NET_ADMIN`; routes apply inside the container. Exit/subnet routing also requires forwarding and control-plane approval. With `TS_AUTH_ONCE=true`, later routing changes need an explicit `tailscale set`.
- Without TUN or extra capabilities, use [compose.userspace.yml](compose.userspace.yml) **alone**: `docker compose -f compose.userspace.yml up -d`. Use the same `-f` for login and later commands. Applications must use its localhost SOCKS5 `1055` or HTTP `1056` proxy; sharing the network namespace alone adds no routes.

## Troubleshooting

Check `tailscale version`, `tailscale netcheck`, `tailscale awg doctor` and `tailscale ping --tsmp <peer>`. A default disco ping alone does not prove application traffic works. Report both peers' versions and diagnostics in [Issues](https://github.com/LiuTangLei/tailscale-awg-installer/issues).

[BSD 3-Clause License](LICENSE) · [Tailscale](https://github.com/tailscale/tailscale) · [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-go)
