# Tailscale with Amnezia-WG 1.5

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows-blue)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](LICENSE)

Tailscale with **Amnezia-WG 1.5** protocol masquerading for DPI evasion and censorship circumvention.

**📚 Languages:** [English](README.md) | [中文](doc/README-zh.md) | [فارسی](doc/README-fa.md) | [Русский](doc/README-ru.md)

## 🚀 Installation

**Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash
```

**macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash
```

**Windows (PowerShell as Admin):**

```powershell
iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 | iex
```

### Installation Options

**Mirror downloads (if GitHub is slow or blocked in your country):**

It is recommended to use your own mirror domain (e.g. <https://your-mirror-site.com>) to avoid public mirrors being blocked. You can deploy your own mirror using [gh-proxy](https://github.com/hunshcn/gh-proxy).

```bash
# Linux:
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com
```

```bash
# macOS:
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --mirror https://your-mirror-site.com
```

```powershell
# Windows:
$scriptContent = (iwr -useb https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content;$scriptBlock = [scriptblock]::Create($scriptContent); & $scriptBlock -MirrorPrefix 'https://your-mirror-site.com/'
```

**PowerShell execution policy issues:**

```powershell
# If script execution is blocked:
Set-ExecutionPolicy RemoteSigned
# or
Set-ExecutionPolicy Bypass -Scope Process
```

## ⚙️ Usage

This guide explains how to set up and use Tailscale with Amnezia-WG for the first time.

> **Note:** All `tailscale amnezia-wg` subcommands can be shortened to `tailscale awg`. For example, `tailscale awg set` is equivalent to `tailscale amnezia-wg set`.

### 1. Login to Tailscale

After installation, the first step is to connect to your Tailscale network.

```bash
# For the official Tailscale service
tailscale up

# For self-hosted Headscale servers
tailscale up --login-server https://your-headscale-domain
```

### 2. Initial Setup (First Device)

On your first device, run the interactive setup command. This will configure the core Amnezia-WG parameters that will be shared across your devices.

```bash
tailscale amnezia-wg set
```

You will be prompted to enter several values. For the magic headers (`H1`, `H2`, `H3`, `H4`), you can simply type **`random`** at the prompt to generate secure, random values automatically.

### 3. Syncing Other Devices

Once your first device is configured, you can easily sync the same settings to other devices on your Tailscale network. Run the following command on any new device:

```bash
tailscale amnezia-wg sync
```

This command will fetch the configuration from your already-configured node and apply it. This ensures all your devices share the same core parameters (`S1`, `S2`, `H1`-`H4`) required to communicate.

### 4. Customizing Individual Devices (Optional)

After syncing, you can still customize non-shared settings (like jitter) on a per-device basis. Run the interactive setup again:

```bash
tailscale amnezia-wg set
```

The interactive prompt will show your current settings. You can choose to modify only the parameters you need, leaving the shared core configuration (`S1`, `S2`, `H1`-`H4`) untouched.

### Other Commands

Here are some other useful commands:

```bash
# Check your current Amnezia-WG settings
tailscale amnezia-wg get

# Reset to the standard WireGuard protocol
tailscale amnezia-wg reset
```

## 🛡️ Amnezia-WG Features

### Junk Traffic & Signatures

Add fake packets and protocol signatures to evade DPI. Compatible with standard Tailscale peers:

```bash
# Basic junk traffic
tailscale amnezia-wg set '{"jc":4,"jmin":64,"jmax":256}'

# With protocol signatures (i1-i5)
tailscale amnezia-wg set '{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0xc0><r 16>","i2":"<b 0x40><r 12>"}'
```

### Protocol Masquerading

Requires ALL nodes to use this fork with identical settings (ix signatures do NOT require matching):

```bash
# Handshake obfuscation (s1/s2 must match on all nodes)
tailscale amnezia-wg set '{"s1":10,"s2":15}'

# With header fields (h1-h4 for protocol obfuscation, must match on all nodes)
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777}'

# Combined with signatures (i1-i5 can be different per node)
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777,"i1":"<b 0xc0><r 32><c><t>"}'
```

## 🎯 Configuration Guide

**Basic Configurations (Compatible with standard clients):**

| Type           | Config                                                | Status      |
| -------------- | ----------------------------------------------------- | ----------- |
| **Junk only**  | `{"jc":4,"jmin":64,"jmax":256}`                       | ✅ Standard |
| **Junk + Sig** | `{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0xc0><r 16>"}` | ✅ Standard |

**Advanced Configurations (fork-only; all nodes must share identical values):**

| Purpose                  | Minimal Example                                                                                  | Notes                     |
| ------------------------ | ------------------------------------------------------------------------------------------------ | ------------------------- |
| Handshake prefixes       | `{"s1":10,"s2":15}`                                                                              | s1/s2: 0–64, must match   |
| Header obfuscation       | `{"s1":10,"s2":15,"h1":123456,"h2":789012,"h3":345678,"h4":901234}`                              | h1–h4: 32‑bit, must match |
| Combined (with junk/sig) | `{"jc":2,"s1":10,"s2":15,"h1":123456,"h2":789012,"h3":345678,"h4":901234,"i1":"<b 0xc0><r 16>"}` | jc / i1-i5 optional       |

> Note: Excessive junk packets (jc) or very large signature chains (i1–i5) can increase latency and bandwidth usage.

### Parameter Explanation

- **jc**: Number of junk packets (0-10, must set jmin/jmax together)
- **jmin/jmax**: Junk packet size range in bytes (64-1024, required when using jc)
- **i1-i5**: Protocol signature packets for imitation (arbitrary hex-blob)
- **s1/s2**: Random prefixes for Init/Response packets (0-64 bytes, requires matching values on all nodes). Pure metadata padding at handshake layer
- **h1-h4**: Protocol obfuscation (32-bit values, must set all 4 or none, requires matching values on all nodes). Recommended each be unique; suggested practical range: 5–2147483647

### Official Parameter Ranges

| Parameter      | Range              | Description                               |
| -------------- | ------------------ | ----------------------------------------- |
| **I1-I5**      | arbitrary hex-blob | Signature packets for protocol imitation  |
| **S1, S2**     | 0-64 bytes         | Random prefixes for Init/Response packets |
| **Jc**         | 0-10               | Number of junk packets following I1-I5    |
| **Jmin, Jmax** | 64-1024 bytes      | Size range for random junk packets        |
| **H1-H4**      | 0-4294967295       | 32-bit values for protocol obfuscation    |

## 📊 Platform Support

| Platform    | Architectures        | Status                  |
| ----------- | -------------------- | ----------------------- |
| **Linux**   | x86_64, ARM64        | ✅ Fully supported      |
| **macOS**   | Intel, Apple Silicon | ✅ Fully supported      |
| **Windows** | x86_64, ARM64        | ✅ PowerShell installer |

## 🔄 Migration from Official Tailscale

1. Run the installer - automatically replaces binaries while preserving your settings
2. Your existing authentication and configuration remain unchanged
3. Start with basic obfuscation: `tailscale amnezia-wg set '{"jc":4,"jmin":64,"jmax":256}'`

## ⚠️ Important Notes

- **Default behavior**: Works exactly like official Tailscale until you enable obfuscation
- **Junk packets (jc) & signatures (i1-i5)**: Compatible with any Tailscale peer, including standard clients. Each node can use different values
- **Protocol masquerading (s1/s2) & header fields (h1-h4)**: Requires ALL nodes to use this fork with identical values
- **Performance**: Minimal overhead with basic settings

## 🛠️ Advanced Usage

### Header Field Configuration (h1-h4)

Protocol obfuscation to evade WireGuard detection. Must set all 4 values or none:

```bash
# First node: generate random values (enter 'random' for each h1-h4)
tailscale amnezia-wg set  # Set all h1, h2, h3, h4 when prompted

# Get the configuration JSON
tailscale amnezia-wg get

# Copy the entire JSON to other nodes (must include all h1-h4)
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777}'
```

### Creating Protocol Signatures

1. Capture real traffic with Wireshark
2. Extract hex patterns from headers
3. Build format: `<b 0xHEX>` (static), `<r LENGTH>` (random), `<c>` (counter), `<t>` (timestamp)
4. Example: `<b 0xc0000000><r 16><c><t>` = QUIC-like header + 16 random bytes + counter + timestamp

### Obfuscation Packets I1–I5 (Signature Chain) & CPS (Custom Protocol Signature)

Before each "special" handshake (every 120 seconds), the client may send up to five custom UDP packets (I1–I5) in the CPS format for protocol imitation.

**CPS Format:**

```text
i{n} = <tag1><tag2><tag3>...<tagN>
```

**Tag Types:**

| Tag | Format         | Description                                 | Constraints      |
| --- | -------------- | ------------------------------------------- | ---------------- |
| b   | `<b hex_data>` | Static bytes to emulate protocols           | Arbitrary length |
| c   | `<c>`          | Packet counter (32-bit, network byte order) | Unique per chain |
| t   | `<t>`          | Unix timestamp (32-bit, network byte order) | Unique per chain |
| r   | `<r length>`   | Cryptographically secure random bytes       | length ≤ 1000    |

**Example:**

```text
i1 = <b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>
```

> ⚠️ If i1 is not set, the entire chain (I2–I5) is skipped.

#### Capturing Real Obfuscation Packets with Wireshark

1. Start Amnezia-WG and configure the i1–i5 parameters
2. Use Wireshark to monitor the UDP port (e.g., filter: `udp.port == 51820`)
3. Observe and analyze the obfuscation packets, extract protocol signatures as needed

For more details, see the [Amnezia-WG official documentation](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted)

## 🐛 Troubleshooting

### Verify Installation

```bash
tailscale version          # Check client version
tailscale amnezia-wg get   # Verify Amnezia-WG support
```

### Connection Issues

```bash
# Reset to standard WireGuard
tailscale amnezia-wg reset

# Try basic settings first
tailscale amnezia-wg set '{"jc":2,"jmin":64,"jmax":128}'

# Check logs (Linux)
sudo journalctl -u tailscaled -f
```

### Windows PowerShell Issues

Use interactive mode to avoid JSON escaping problems:

```powershell
tailscale amnezia-wg set  # Interactive setup
```

## 🤝 Links & Support

- **Binary releases**: [LiuTangLei/tailscale](https://github.com/LiuTangLei/tailscale/releases)
- **Installer issues**: [GitHub Issues](https://github.com/LiuTangLei/tailscale-awg-installer/issues)
- **Amnezia-WG docs**: [Official Documentation](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted)

## 📄 License

BSD 3-Clause License (same as Tailscale)

---

**⚠️ Disclaimer**: For educational and legitimate privacy purposes only. Users are responsible for compliance with applicable laws.
