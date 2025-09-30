# Tailscale with Amnezia-WG 2.0 (v1.88.2+)

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20Android-blue)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](LICENSE)

Enhanced Tailscale client with Amnezia‑WG 2.0 obfuscation: junk traffic, protocol signatures, and handshake/header masquerading to resist DPI and blocking. Acts like vanilla Tailscale until you enable AWG features.

📚 Languages: [English](README.md) | [中文](doc/README-zh.md) | [فارسی](doc/README-fa.md) | [Русский](doc/README-ru.md)

For AWG v1.5 documentation, see: [doc/README-awg-v1.5.md](doc/README-awg-v1.5.md)

## 🚨 AWG 2.0 breaking changes (v1.88.2+)

From v1.88.2 this project switches to Amnezia‑WG 2.0. Configs from 1.x are not compatible.

- h1, h2, h3, h4 are now ranges (inclusive) instead of single fixed values. Their ranges must not overlap.
- Added support for s3 and s4 in addition to s1 and s2.
- The interactive command now helps you: when you run `tailscale awg set` it asks:
  Do you want to generate random AWG parameters automatically? [Y/n]:
  Press Enter to auto‑generate safe values for everything except i1–i5. This is the fastest way to get started if you’re unsure what to set.

If you were on AWG 1.x, reconfigure all nodes after upgrading. See “Migration to 2.0” below.

## 🚀 Installation

| Platform                   | Command / Action                                                                                                 |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Linux                      | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash`  |
| macOS*                     | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash`  |
| Windows (Admin PowerShell) | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` |
| Android                    | Download APK: [releases](https://github.com/LiuTangLei/tailscale-android/releases)                               |

macOS note: Due to system integrity protections, the installer uses CLI-only Tailscale. If the official Tailscale.app is detected, you'll be prompted to remove it to avoid conflicts.

Android build currently supports AWG config sync (receive) from another configured node. Use the in‑app Sync button:

![Android AWG Sync Example](doc/sync1.jpg)

### Docker Compose

Prefer containers? The repo ships with `docker-compose.yml` that runs the bundled `tailscaled` image with AWG support:

1. Start the service: `docker compose up -d`
2. Authenticate inside the container: `docker compose exec tailscaled tailscale up` (add `--login-server https://your-headscale-domain` if you use self-hosted Headscale)
3. Run interactive commands exactly like on a host install, e.g. `docker compose exec tailscaled tailscale awg sync`

The supported platforms match the upstream Tailscale Docker image.

### Mirrors (optional)

Self-host a prefix mirror (e.g. `https://your-mirror-site.com`) via gh-proxy if GitHub is slow/blocked:

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

PowerShell policy (if blocked): `Set-ExecutionPolicy RemoteSigned` (or `Bypass -Scope Process`)

### macOS Installation Notes

- CLI-only deployment: Uses open-source `tailscaled` (utun interface) for full compatibility with custom builds
- App conflict handling: Automatically detects and offers to remove official Tailscale.app to prevent system extension conflicts

## ⚡ Quick Start

Tip: `tailscale amnezia-wg` → `tailscale awg` (alias)

1. Login:

```bash
# Official
tailscale up
# Headscale
tailscale up --login-server https://your-headscale-domain
```

1. Configure AWG (auto‑generate recommended):

```bash
tailscale awg set
```

When prompted “Do you want to generate random AWG parameters automatically? [Y/n]:” just press Enter. This generates safe values for all parameters except i1–i5.

1. Sync other devices:

- Desktop: `tailscale awg sync`
- Android: tap Sync button (see screenshot above)

1. Optional manual tuning: rerun `tailscale awg set` and answer “n” to set specific values. You can leave i1–i5 unset if you don’t need custom protocol signatures.

1. Useful:

```bash
tailscale awg get     # show JSON
tailscale awg reset   # revert to vanilla WireGuard
```

## 🛡️ Features

### Junk Traffic & Signatures

Add fake packets and protocol signatures to evade DPI. Compatible with standard Tailscale peers:

```bash
# Basic junk traffic
tailscale awg set '{"jc":4,"jmin":64,"jmax":256}'

# With protocol signatures (i1-i5)
tailscale awg set '{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0x40><r 12>"}'
```

### Protocol Masquerading

Requires ALL nodes to use this fork with identical s1–s4 and h1–h4 settings (ix signatures do NOT require matching):

```bash
# Handshake obfuscation (s1..s4 must match on all nodes)
tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0}'

# With header field ranges (h1..h4 are non-overlapping ranges; all nodes must match)
tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000}}'

# Combined with signatures (i1-i5 can be different per node)
tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000},"i1":"<b 0xc0><r 32><c><t>"}'
```

## 🎯 Configuration

Basic (works with standard clients):

| Type             | JSON                                                  | Compatible |
| ---------------- | ----------------------------------------------------- | ---------- |
| Junk only        | `{"jc":4,"jmin":64,"jmax":256}`                       | ✅ Yes     |
| Junk + Signature | `{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0xc0><r 16>"}` | ✅ Yes     |

Advanced (all nodes must use this fork & share s1–s4 and h1–h4):

| Purpose                   | Example                                                                                                                                      | Notes                                      |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| Handshake prefixes        | `{"s1":10,"s2":15,"s3":8,"s4":0}`                                                                                                         | s1–s4 must match on all nodes              |
| Header obfuscation ranges | `{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000}}`             | h1–h4 are ranges; ranges must not overlap  |
| Combined                  | `{"jc":2,"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000},"i1":"<b 0xc0><r 16>"}` | junk/signatures optional                    |

Parameters:

- jc (0–10) with jmin/jmax (64–1024): junk packet count & size range
- i1–i5: optional signature chain (hex-format mini language)
- s1–s4: handshake padding/prefix fields (must match across all AWG nodes)
- h1–h4: header field ranges, each as {"min": low, "max": high} (inclusive). Ranges must not overlap; set all 4 or none; must match on all nodes.

Notes: very large junk counts or long signature chains increase latency & bandwidth.

## 📊 Platform Support

| Platform | Arch                 | Status                 |
| -------- | -------------------- | ---------------------- |
| Linux    | x86_64, ARM64        | ✅ Full                |
| macOS    | Intel, Apple Silicon | ✅ Full                |
| Windows  | x86_64, ARM64        | ✅ Installer           |
| Android  | ARM64, ARM           | ✅ APK (sync-only AWG) |

## � Migration to 2.0 (from 1.x)

1. Upgrade all nodes to v1.88.2+ builds from this repo.
2. On each node, clear previous AWG 1.x settings (optional but recommended):

```bash
tailscale awg reset
```

1. Run `tailscale awg set` and press Enter at the prompt to auto‑generate all parameters except i1–i5.
2. Distribute the resulting config (`tailscale awg get`) to other nodes or use `tailscale awg sync`.
3. Ensure h1–h4 ranges are identical (and non‑overlapping) across nodes that should communicate with masquerading enabled. s1–s4 must also match.

Mixed 1.x/2.0 environments are not supported for header/handshake masquerading.

## 🛠️ Advanced Usage

### Creating Protocol Signatures (i1–i5)

1. Capture real traffic with Wireshark.
2. Extract hex patterns from headers.
3. Build format: `<b 0xHEX>` (static), `<r LENGTH>` (random), `<c>` (counter), `<t>` (timestamp).
4. Example: `<b 0xc0000000><r 16><c><t>` = QUIC‑like header + 16 random bytes + counter + timestamp.

### Obfuscation Packets I1–I5 (Signature Chain) & CPS (Custom Protocol Signature)

Before each "special" handshake (every 120 seconds), the client may send up to five custom UDP packets (I1–I5) in the CPS format for protocol imitation.

CPS format:

```text
i{n} = <tag1><tag2><tag3>...<tagN>
```

Tag types:

| Tag | Format         | Description                                 | Constraints      |
| --- | -------------- | ------------------------------------------- | ---------------- |
| b   | `<b hex_data>` | Static bytes to emulate protocols           | Arbitrary length |
| c   | `<c>`          | Packet counter (32-bit, network byte order) | Unique per chain |
| t   | `<t>`          | Unix timestamp (32-bit, network byte order) | Unique per chain |
| r   | `<r length>`   | Cryptographically secure random bytes       | length ≤ 1000    |

Example:

```text
i1 = <b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>
```

If i1 is not set, the entire chain (I2–I5) is skipped.

## 🐛 Troubleshooting

### Verify Installation

```bash
tailscale version          # Check client version
tailscale awg get          # Verify Amnezia-WG support
```

### Connection Issues

```bash
# Reset to standard WireGuard
tailscale awg reset

# Try basic settings first
tailscale awg set '{"jc":2,"jmin":64,"jmax":128}'

# Check logs (Linux)
sudo journalctl -u tailscaled -f
```

### Windows PowerShell Issues

Use interactive mode to avoid JSON escaping problems:

```powershell
tailscale awg set  # Interactive setup
```

## 🤝 Links & Support

- Releases: <https://github.com/LiuTangLei/tailscale/releases>
- Android APK: <https://github.com/LiuTangLei/tailscale-android/releases>
- Installer issues: <https://github.com/LiuTangLei/tailscale-awg-installer/issues>
- Amnezia‑WG docs: <https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted>

## 📄 License

BSD 3-Clause License (same as upstream Tailscale)

---

Disclaimer: Educational & legitimate privacy use only. You are responsible for legal compliance.
