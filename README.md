# Tailscale with Amnezia-WG 2.0

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20OpenWrt%20|%20Android%20|%20iOS-blue)](#platform-support)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](LICENSE)

Enhanced Tailscale client with Amnezia-WG 2.0 obfuscation: junk traffic, protocol signatures, and handshake/header masquerading to resist DPI and blocking. It works with the official Tailscale control server and Headscale; no custom control server is required. Until you enable AWG settings, it behaves like standard Tailscale. Junk traffic and CPS signature modes interoperate with standard Tailscale peers, while handshake/header masquerading requires matching AWG settings on AWG peers.

Languages: [English](README.md) | [中文](doc/README-zh.md) | [فارسی](doc/README-fa.md) | [Русский](doc/README-ru.md)

Legacy AWG 1.5 archive: [doc/README-awg-v1.5.md](doc/README-awg-v1.5.md).

## Installation

| Platform | Command / Action |
| --- | --- |
| Linux | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` |
| macOS* | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` |
| Windows (Admin PowerShell) | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` |
| OpenWrt | See [OpenWrt Installation](#openwrt-installation) |
| Android | Download APK from [releases](https://github.com/LiuTangLei/tailscale-android/releases) |
| iOS | Experimental open-source client: see [AwgScale](https://github.com/LiuTangLei/AwgScale) (TrollStore or Packet Tunnel entitlement signing required) |

- macOS: the installer uses CLI-only `tailscaled`. If the official Tailscale.app is detected, you'll be prompted to remove it to avoid conflicts.
- Android and iOS mobile clients support manual AWG setup and syncing AWG settings from other nodes.
- iOS: AwgScale is experimental and self-managed. It is not available on the App Store; the current IPA targets TrollStore, or a normal Apple signing path with the Packet Tunnel entitlement.

![Android AWG Sync Example](doc/sync1.jpg)

## Docker Compose

The repository includes `docker-compose.yml` for running `tailscaled` with AWG support.

- State is stored in `./tailscale-state` next to the compose file, so node state and AWG settings survive container restarts and host reboots.
- If you are upgrading from the old bind mount `/var/lib/tailscale:/var/lib/tailscale`, copy the existing state first:

```bash
docker compose down
cp -a /var/lib/tailscale ./tailscale-state
# update docker-compose.yml
docker compose up -d
```

Basic flow:

1. Start the service: `docker compose up -d`
2. Authenticate inside the container: `docker compose exec tailscaled tailscale up`
3. Run AWG commands the same way, for example: `docker compose exec tailscaled tailscale awg sync`

If you use Headscale, add `--login-server https://your-headscale-domain` to `tailscale up`.

Note the two names: the Compose service/container is `tailscaled`, and the CLI binary inside the container is `tailscale`. So the direct Docker form is:

```bash
docker exec -it tailscaled tailscale status
```

`docker exec tailscale status` is not equivalent: Docker would look for a container named `tailscale`, then try to run `status` as a program.

To use `tailscale ...` directly on the Linux host, persist an alias in your shell startup file:

```bash
printf "\nalias tailscale='docker exec -it tailscaled tailscale'\n" >> ~/.bashrc && . ~/.bashrc
```

For Zsh, use `~/.zshrc` instead:

```bash
printf "\nalias tailscale='docker exec -it tailscaled tailscale'\n" >> ~/.zshrc && . ~/.zshrc
```

Then run:

```bash
tailscale up
tailscale awg get
```

## OpenWrt Installation

Default command:

```bash
wget -O /usr/bin/install.sh https://raw.githubusercontent.com/LiuTangLei/openwrt-tailscale-awg/main/install_en.sh && chmod +x /usr/bin/install.sh && /usr/bin/install.sh
```

Mirror command for regions with restricted GitHub access:

```bash
wget -O /usr/bin/install.sh https://ghfast.top/https://raw.githubusercontent.com/LiuTangLei/openwrt-tailscale-awg/main/install.sh && chmod +x /usr/bin/install.sh && /usr/bin/install.sh
```

This script is forked from [GuNanOvO/openwrt-tailscale](https://github.com/GuNanOvO/openwrt-tailscale).

## Mirrors

If GitHub is slow or blocked, you can self-host a prefix mirror such as `https://your-mirror-site.com`:

```bash
# Linux
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com

# macOS
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --mirror https://your-mirror-site.com
```

```powershell
# Windows
$scriptContent = (iwr -useb https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content; $scriptBlock = [scriptblock]::Create($scriptContent); & $scriptBlock -MirrorPrefix 'https://your-mirror-site.com/'
```

If PowerShell blocks execution, use `Set-ExecutionPolicy RemoteSigned` or `Bypass -Scope Process`.

## Quick Start

Tip: `tailscale amnezia-wg` is the same as `tailscale awg`.

1. Log in:

```bash
# Official control server
tailscale up

# Headscale
tailscale up --login-server https://your-headscale-domain
```

2. Configure AWG:

```bash
tailscale awg set
```

Press Enter at the auto-generation prompt to generate recommended values for everything except `i1`-`i5`.

3. On other devices, sync the same AWG config from this already-configured node:

- CLI platforms (Linux/macOS/Windows/OpenWrt): run `tailscale awg sync` on the other device
- Android and iOS (AwgScale): use the in-app AWG controls to set values manually or sync settings from another node

4. Verify or reset when needed:

```bash
tailscale awg get
tailscale awg reset
```

## Configuration Presets

| Goal | Example | Compatibility |
| --- | --- | --- |
| Basic junk traffic | `tailscale awg set '{"jc":4,"jmin":64,"jmax":256}'` | Works with standard Tailscale peers |
| Junk traffic + signatures | `tailscale awg set '{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0x40><r 12>"}'` | Works with standard Tailscale peers |
| Handshake masquerading | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0}'` | All AWG nodes must use the same `s1`-`s4` |
| Full masquerading | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000}}'` | All AWG nodes must use the same `s1`-`s4` and `h1`-`h4` |
| Full masquerading + signatures | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000},"i1":"<b 0xc0><r 32><c><t>"}'` | `i1`-`i5` may differ per node; `s1`-`s4` and `h1`-`h4` must match |

## Parameter Reference

- `jc` with `jmin` and `jmax`: junk packet count and size range.
- `i1`-`i5`: optional CPS (Custom Protocol Signature) chain for custom protocol-mimicking packets.
- `s1`-`s4`: handshake padding or prefix fields; all AWG nodes must match.
- `h1`-`h4`: header field ranges in the form `{"min": low, "max": high}`; either set all four or none. The ranges must not overlap, and all AWG nodes must match.

Very large junk counts or long signature chains increase latency and bandwidth usage.

## Platform Support

| Platform | Arch | Status |
| --- | --- | --- |
| Linux | x86_64, ARM64 | ✅ Full |
| macOS | Intel, Apple Silicon | ✅ Full |
| Windows | x86_64, ARM64 | ✅ Installer |
| OpenWrt | Various | ✅ Script |
| Android | ARM64, ARM | ✅ APK (manual AWG + sync) |
| iOS | iPhone/iPad (iOS 15+) | ✅ Experimental client (manual AWG + sync) |

## Advanced: CPS Protocol Signatures

CPS means Custom Protocol Signature. It lets you assemble custom obfuscation packets that can imitate arbitrary protocol headers; it is not limited to one specific protocol.

CPS format:

```text
i{n} = <tag1><tag2>...<tagN>
```

Tags:

- `<b 0xHEX>`: static bytes
- `<r N>`: secure random bytes
- `<c>`: counter
- `<t>`: timestamp

Example:

```text
i1 = <b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>
```

If `i1` is unset, `i2`-`i5` are skipped.

## Troubleshooting

Verify installation:

```bash
tailscale version
tailscale awg get
```

If connectivity breaks, reset to standard WireGuard and start from a simple preset:

```bash
tailscale awg reset
tailscale awg set '{"jc":2,"jmin":64,"jmax":128}'
sudo journalctl -u tailscaled -f
```

On Windows PowerShell, prefer interactive setup to avoid JSON escaping issues:

```powershell
tailscale awg set
```

## Links & Support

- Releases: <https://github.com/LiuTangLei/tailscale/releases>
- Android APK: <https://github.com/LiuTangLei/tailscale-android/releases>
- iOS client (AwgScale): <https://github.com/LiuTangLei/AwgScale>
- Installer issues: <https://github.com/LiuTangLei/tailscale-awg-installer/issues>
- Amnezia-WG docs: <https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted/#how-to-extract-a-protocol-signature-for-amneziawg-manually>

## License

BSD 3-Clause License, same as upstream Tailscale.
