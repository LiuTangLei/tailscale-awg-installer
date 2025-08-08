# Tailscale with Amnezia-WG 1.5 - One-Click Installer

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows-blue)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](LICENSE)

Drop-in replacement for official Tailscale with **Amnezia-WG 1.5** protocol masquerading capabilities for advanced DPI evasion and censorship circumvention.

## 🚀 One-Click Installation

We provide separate, reliable installers per OS.

- Linux: `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash`
- macOS: `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash`
- Windows (PowerShell as Admin): `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 | iex`

**If GitHub download is slow**: Use GitHub mirror service:

```bash
# Linux with mirror
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com

# macOS with mirror
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --mirror https://your-mirror-site.com

# Windows with mirror (alternative)
iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 -OutFile install.ps1
.\install.ps1 -MirrorPrefix 'https://your-mirror-site.com'
```

### Manual Download

Download pre-compiled binaries from [Releases](https://github.com/LiuTangLei/tailscale/releases/latest):

**Linux:**

```bash
# Download and replace official binaries
wget https://github.com/LiuTangLei/tailscale/releases/latest/download/tailscale-linux-amd64
wget https://github.com/LiuTangLei/tailscale/releases/latest/download/tailscaled-linux-amd64

sudo systemctl stop tailscaled
sudo cp tailscale-linux-amd64 /usr/local/bin/tailscale
sudo cp tailscaled-linux-amd64 /usr/local/bin/tailscaled
sudo chmod +x /usr/local/bin/tailscale*
sudo systemctl start tailscaled
```

**macOS:**

```bash
# Download and replace Homebrew installation
wget https://github.com/LiuTangLei/tailscale/releases/latest/download/tailscale-darwin-amd64
wget https://github.com/LiuTangLei/tailscale/releases/latest/download/tailscaled-darwin-amd64

sudo launchctl unload /Library/LaunchDaemons/com.tailscale.tailscaled.plist
sudo cp tailscale-darwin-amd64 /usr/local/bin/tailscale
sudo cp tailscaled-darwin-amd64 /usr/local/bin/tailscaled
sudo chmod +x /usr/local/bin/tailscale*
sudo launchctl load /Library/LaunchDaemons/com.tailscale.tailscaled.plist
```

**Windows:**

Use the one-liner installer above. Manual replacement is not recommended.

## ⚡ Quick Start

Note: First-time only — authenticate with Tailscale before applying Amnezia‑WG settings.

- Official control plane: `tailscale up`
- Headscale: `tailscale up --login-server https://<your-headscale-domain>`

After installation, your Tailscale works exactly like before. Enable Amnezia-WG features when needed:

```bash
# Connect to your network (same as official Tailscale)
tailscale up

# Enable basic DPI evasion (safe with any Tailscale peer)
tailscale amnezia-wg set '{"jc":4,"jmin":40,"jmax":70}'

# Check current obfuscation settings
tailscale amnezia-wg get

# Interactive setup with guidance
tailscale amnezia-wg set

# Reset to standard WireGuard
tailscale amnezia-wg reset
```

## 🛡️ Amnezia-WG 1.5 Features

### Protocol Masquerading

Make your WireGuard traffic look like any UDP protocol (QUIC, DNS, SIP):

```bash
tailscale amnezia-wg set '{"s1":10,"s2":15,"i1":"<b 0xc0><r 32><c><t>"}'
```

### Advanced Junk Traffic

Smart packet injection that doesn't interfere with standard peers:

```bash
tailscale amnezia-wg set '{"jc":4,"jmin":40,"jmax":70,"i1":"<b 0xc0><r 16>"}'
```

### Multi-Level Obfuscation

Combine multiple techniques for maximum stealth:

```bash
tailscale amnezia-wg set '{"jc":2,"s1":15,"s2":20,"i1":"<b 0xc0><r 16>","i2":"<b 0x40><r 12>"}'
```

## 🔧 Configuration Examples

### Conservative (Works with standard Tailscale peers)

```bash
# Basic junk packets - each node can use different values
tailscale amnezia-wg set '{"jc":4,"jmin":40,"jmax":70}'

# With protocol signatures - still compatible
tailscale amnezia-wg set '{"jc":2,"i1":"<b 0xc0><r 16>","i2":"<b 0x40><r 12>"}'
```

### Advanced (All nodes must use this fork)

```bash
# Protocol masquerading - requires identical s1/s2 on all nodes
tailscale amnezia-wg set '{"s1":10,"s2":15,"i1":"<b 0xc0><r 32><c><t>"}'

# Maximum obfuscation - complex signature chain
tailscale amnezia-wg set '{"jc":6,"s1":15,"s2":20,"i1":"<b 0xc0><r 32><c><t>","i2":"<b 0x40><r 16><t>"}'
```

## 🎯 Use Cases

| Scenario                   | Recommended Config                               | Compatibility                |
| -------------------------- | ------------------------------------------------ | ---------------------------- |
| **Basic DPI bypass**       | `{"jc":4,"jmin":40,"jmax":70}`                   | ✅ Works with standard peers |
| **Corporate firewall**     | `{"jc":4,"i1":"<b 0xc0><r 16>"}`                 | ✅ Works with standard peers |
| **Deep packet inspection** | `{"s1":10,"s2":15,"i1":"<b 0xc0><r 32><c><t>"}`  | ❌ All nodes need this fork  |
| **Government censorship**  | `{"jc":6,"s1":15,"s2":20,"i1":"...","i2":"..."}` | ❌ All nodes need this fork  |

## 📊 Platform Support

| Platform | Architecture           | Status                                |
| -------- | ---------------------- | ------------------------------------- |
| Linux    | x86_64 (amd64)         | ✅ Supported                          |
| Linux    | ARM64                  | ✅ Supported                          |
| macOS    | Intel (amd64)          | ✅ Supported                          |
| macOS    | Apple Silicon (arm64)  | ✅ Supported                          |
| Windows  | x86_64 (amd64) & ARM64 | ✅ Supported via PowerShell installer |

## 🔄 Migration Guide

### From Official Tailscale

1. Run the installer - it automatically replaces binaries
2. Your existing configuration and authentication remain unchanged
3. Start with conservative DPI evasion: `tailscale amnezia-wg set '{"jc":4,"jmin":40,"jmax":70}'` or use interactive mode

### From AmneziaWG 1.0

1. Replace compile-time settings with runtime configuration
2. H1–H4 still exist in 1.5 but are internal/auto-generated; configure CPS via I1–I5 instead (no manual H1–H4 knobs)
3. Use interactive setup: `tailscale amnezia-wg set`

## ⚠️ Important Notes

- **Default Behavior**: Works exactly like official Tailscale until you enable obfuscation
- **Mixed Networks**: Junk packets (`jc`) and signatures (`i1`-`i5`) work with any peer
- **Protocol Masquerading**: Handshake obfuscation (`s1`, `s2`) requires ALL nodes to use this fork
- **Performance**: Minimal overhead with conservative settings, monitor bandwidth with complex signatures

## 🛠️ Advanced Usage

### Environment Variables

```bash
export TS_AMNEZIA_JC=4
export TS_AMNEZIA_JMIN=40
export TS_AMNEZIA_JMAX=70
export TS_AMNEZIA_I1='<b 0xc0><r 32><c><t>'
sudo systemctl restart tailscaled
```

### JSON Configuration

```bash
# Set via general command
tailscale set --amnezia-wg='{"jc":4,"jmin":40,"jmax":70}'

# Batch configuration
tailscale amnezia-wg set '{"jc":4,"s1":10,"s2":15,"i1":"<captured_protocol_header>"}'
```

### Creating Custom Protocol Signatures

1. **Capture real traffic** with Wireshark from the protocol you want to mimic
2. **Extract hex patterns** from packet headers
3. **Build CPS format**: `<b 0xHEX_PATTERN>` for static headers
4. **Add dynamics**: `<c>` (counter), `<t>` (timestamp), `<r LENGTH>` (random)

Example: `<b 0xc0000000><r 16><c><t>` = QUIC-like header + 16 random bytes + counter + timestamp

## 🐛 Troubleshooting

### Installation Issues

```bash
# Check if installation worked
tailscale version
tailscaled --version

# Verify Amnezia-WG support
tailscale amnezia-wg get
```

### Windows PowerShell JSON Issues

Use interactive mode for easiest configuration:

```powershell
tailscale amnezia-wg set  # Interactive setup with prompts
```

### Connection Problems

```bash
# Reset to standard WireGuard
tailscale amnezia-wg reset

# Check logs
sudo journalctl -u tailscaled -f

# Try conservative settings first
tailscale amnezia-wg set '{"jc":2,"jmin":40,"jmax":60}'
```

### Configuration Issues

- **Mixed networks**: Only use `jc`, `jmin`, `jmax`, `i1`-`i5` with standard peers
- **Protocol masquerading**: Ensure ALL nodes have identical `s1`, `s2` values
- **Long signatures**: Use JSON mode for signatures >1000 characters

## 🤝 Contributing

This is a fork of [Tailscale](https://github.com/tailscale/tailscale) with integrated [Amnezia-WG 1.5](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted) protocol masquerading.

- **Report issues (installer scripts)**: [GitHub Issues](https://github.com/LiuTangLei/tailscale-awg-installer/issues)
- **Core fork source code**: [GitHub Repository](https://github.com/LiuTangLei/tailscale)
- **Official docs**: [Amnezia-WG Documentation](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted)

## 📄 License

BSD 3-Clause License (same as Tailscale)

---

**⚠️ Disclaimer**: This software is for educational and legitimate privacy purposes only. Users are responsible for compliance with applicable laws and regulations.
