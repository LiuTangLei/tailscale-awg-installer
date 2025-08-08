# Tailscale with Amnezia‑WG 1.5 Integration

A Tailscale fork that integrates Amnezia‑WG 1.5 capabilities for advanced DPI evasion and censorship circumvention with multi-level obfuscation, while maintaining full backward compatibility with standard WireGuard.

## Installation

Use the per-OS one‑click installers:

- Linux: `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash`
- macOS: `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash`
- Windows (PowerShell as Admin): `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 | iex`

For details and manual installation, see the top‑level README.

## Key Features

- **Zero-config compatibility**: Behaves exactly like standard Tailscale by default
- **Runtime configuration**: Change settings without restarting tailscaled
- **Multiple interfaces**: CLI commands, JSON flags, and environment variables
- **Advanced DPI evasion**: Custom Protocol Signature (CPS), junk packet injection, and handshake randomization
- **Protocol masking**: Mimic QUIC, DNS, SIP, and other UDP protocols
- **Dynamic headers**: Randomized packet headers make each client unique
- **Backward compatible**: All zero/empty values = standard WireGuard behavior
- **Amnezia‑WG 1.0 compatibility**: When I1 is empty, behaves like Amnezia‑WG 1.0

## Quick Start

### Basic DPI Evasion (Recommended)

```bash
# Add junk packets for basic DPI evasion (prompt to restart)
tailscale amnezia-wg set '{"jc":4,"jmin":40,"jmax":70}'

# Advanced protocol masking with QUIC-like signature
tailscale amnezia-wg set '{"jc":4,"jmin":40,"jmax":70,"s1":10,"s2":15,"i1":"<b 0xc0><r 32><c><t>"}'

# Verify configuration
tailscale amnezia-wg get

# Reset to standard WireGuard (prompt to restart)
tailscale amnezia-wg reset
```

### Alternative Configuration Methods

```bash
# Via set command with JSON flag
tailscale set --amnezia-wg='{"jc":4,"jmin":40,"jmax":70}'

# Interactive configuration (includes CPS guidance)
tailscale amnezia-wg set
# (prompts for each parameter with examples)

# Environment variables (requires tailscaled restart)
export TS_AMNEZIA_JC=4 TS_AMNEZIA_JMIN=40 TS_AMNEZIA_JMAX=70
export TS_AMNEZIA_I1='<b 0xc0><r 32><c><t>'
sudo systemctl restart tailscaled
```

## Configuration Parameters

| Parameter | Description | Default | Recommended | Compatibility |
|-----------|-------------|---------|-------------|---------------|
| `jc` | Junk packet count | 0 | 3-6 | ✅ Safe with standard WG |
| `jmin` | Min junk packet size (bytes) | 0 | 40-50 | ✅ Safe with standard WG |
| `jmax` | Max junk packet size (bytes) | 0 | 70-100 | ✅ Safe with standard WG |
| `s1` | Init packet prefix length (0-64) | 0 | 10-20 (advanced) | ❌ Breaks standard WG |
| `s2` | Response packet prefix length (0-64) | 0 | 10-20 (advanced) | ❌ Breaks standard WG |
| `i1` | Primary signature packet (CPS format) | "" | Protocol-specific | ✅ Safe with standard WG |
| `i2` | Secondary signature packet (CPS format) | "" | Optional entropy | ✅ Safe with standard WG |
| `i3` | Tertiary signature packet (CPS format) | "" | Optional entropy | ✅ Safe with standard WG |
| `i4` | Quaternary signature packet (CPS format) | "" | Optional entropy | ✅ Safe with standard WG |
| `i5` | Quinary signature packet (CPS format) | "" | Optional entropy | ✅ Safe with standard WG |

### Custom Protocol Signature (CPS) Format

CPS packets use tag-based format to emulate protocols:

| Tag | Format | Description | Example |
|-----|---------|-------------|---------|
| `b` | `<b hex_data>` | Static bytes to emulate protocols | `<b 0xc0>` (QUIC header) |
| `c` | `<c>` | Packet counter (32-bit, network byte order) | `<c>` |
| `t` | `<t>` | Unix timestamp (32-bit, network byte order) | `<t>` |
| `r` | `<r length>` | Cryptographically secure random bytes | `<r 16>` |

**Examples:**

- Static header: `<b 0xc0000000>` (4-byte fixed header)
- With random data: `<b 0x1234><r 16>` (header + 16 random bytes)
- With counter/timestamp: `<b 0xabcd><c><t>` (header + counter + timestamp)

**⚠️ Important**: Don't use random examples! To create effective CPS signatures:

1. **Capture real traffic** with Wireshark or tcpdump from the protocol you want to mimic
2. **Extract hex patterns** from actual packet headers  
3. **Build CPS format** using captured hex data with `<b hex_pattern>`
4. **Add dynamic fields** like `<c>`, `<t>`, `<r length>` as needed

**💡 Pro tip**: CPS signatures (i1-i5) are advanced junk packets that can replace basic junk packets. More i1-i5 signatures = fewer jc packets needed for effective DPI evasion.

📖 **Complete guide**: [Amnezia‑WG Self-Hosted Setup](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted)

## CLI Commands

```bash
# Amnezia‑WG 1.5 specific commands
tailscale amnezia-wg set '{"jc":4,"jmin":40,"jmax":70}'                     # Basic DPI evasion (prompt to restart)
tailscale amnezia-wg set '{"jc":4,"i1":"<b 0xc0><r 32><c><t>"}'             # Protocol masking (prompt to restart)
tailscale amnezia-wg set                                                     # Interactive setup with CPS guidance
tailscale amnezia-wg get                                                     # Show current config
tailscale amnezia-wg reset                                                   # Reset to standard WG (prompt to restart)

# General set command with Amnezia-WG flag
tailscale set --amnezia-wg='{"jc":4,"jmin":40,"jmax":70}'
```

## Environment Variables

Set these before starting tailscaled:

```bash
export TS_AMNEZIA_JC=4        # Junk packet count
export TS_AMNEZIA_JMIN=40     # Min junk packet size
export TS_AMNEZIA_JMAX=70     # Max junk packet size
export TS_AMNEZIA_S1=0        # Init packet prefix length
export TS_AMNEZIA_S2=0        # Response packet prefix length
export TS_AMNEZIA_I1='<b 0xc0><r 32><c><t>'     # Primary signature packet (CPS format)
export TS_AMNEZIA_I2=''       # Secondary signature packet (CPS format)
export TS_AMNEZIA_I3=''       # Tertiary signature packet (CPS format)
export TS_AMNEZIA_I4=''       # Quaternary signature packet (CPS format)
export TS_AMNEZIA_I5=''       # Quinary signature packet (CPS format)
```

## Usage Scenarios

### 1. Conservative DPI Evasion (Most Common)

```bash
tailscale amnezia-wg set '{"jc":4,"jmin":40,"jmax":70}'
```

- **Use case**: Most censorship environments
- **Impact**: Minimal bandwidth overhead, good compatibility
- **Effectiveness**: Bypasses basic DPI detection
- **Compatibility**: ✅ Works with standard Tailscale/WireGuard peers

### 2. Protocol Masking (Intermediate)

```bash
tailscale amnezia-wg set '{"jc":4,"jmin":40,"jmax":70,"s1":10,"s2":15,"i1":"<b 0xc0><r 32><c><t>"}'
```

- **Use case**: Moderate DPI environments, needs to look like QUIC
- **Impact**: Moderate bandwidth overhead, advanced obfuscation
- **Effectiveness**: Strong DPI evasion with protocol mimicry
- **Compatibility**: ❌ Requires ALL nodes to use this fork with same config

### 3. Full Signature Chain (Advanced)

```bash
tailscale amnezia-wg set '{"jc":6,"s1":15,"s2":20,"i1":"<b 0xc0><r 32><c><t>","i2":"<b 0x40><r 16><t>","i3":"<r 20>","i4":"<c><b 0x0001><r 8>","i5":"<t><r 12>"}'
```

- **Use case**: Strict DPI environments, maximum obfuscation
- **Impact**: Higher bandwidth overhead, complex signature chain
- **Effectiveness**: Maximum DPI evasion with multi-level obfuscation
- **Compatibility**: ❌ Requires ALL nodes to use this fork with identical config

### 4. Standard WireGuard (Default)

```bash
tailscale amnezia-wg reset
```

- **Use case**: Normal networks, maximum performance
- **Impact**: No overhead, maximum compatibility
- **Effectiveness**: No DPI evasion
- **Compatibility**: ✅ Full compatibility with all WireGuard implementations

## Restart Requirements

| Configuration Method | Restart Required |
|---------------------|------------------|
| `tailscale amnezia-wg set` | Prompted (Y/n) |
| `tailscale amnezia-wg reset` | Prompted (Y/n) |
| `tailscale set --amnezia-wg` | No (live update) |
| Environment variables | Yes (restart tailscaled) |

## Compatibility

| Peer Type | Junk Packets | Handshake Obfuscation | Protocol Masking |
|-----------|--------------|----------------------|------------------|
| This fork (1.5) | ✅ Supported | ✅ Supported | ✅ Supported |
| This fork (1.0 mode) | ✅ Supported | ✅ Supported | ❌ N/A |
| Standard Tailscale | ✅ Ignored | ❌ May fail | ❌ May fail |
| Standard WireGuard | ✅ Ignored | ❌ May fail | ❌ May fail |

### ⚠️ Important Compatibility Notes

**Junk packets (`jc`, `jmin`, `jmax`) and CPS signatures (`i1`-`i5`)**:

- ✅ **Safe with any WireGuard**: Standard peers ignore extra packets
- ✅ **Mixed networks**: Can mix this fork with standard Tailscale/WireGuard
- ✅ **Gradual deployment**: Upgrade nodes one by one
- ✅ **Independent settings**: Each node can use different values (both are per-node junk traffic)
- 💡 **Optimization tip**: More CPS signatures = fewer basic junk packets needed

**Handshake obfuscation (`s1`, `s2`)**:

- ❌ **Breaks standard WireGuard**: Connection will fail
- ❌ **All-or-nothing**: ALL nodes in your network must use this fork
- ❌ **Same config required**: All nodes need identical `s1` and `s2` values for handshake compatibility
- ✅ **Amnezia‑WG 1.0 compatibility**: When I1 is empty, works with Amnezia‑WG 1.0

### Recommended Approach for Mixed Environments

**For maximum compatibility (works with standard Tailscale):**

```bash
# Only use junk packets and CPS signatures - safe with any peer
# Each node can use different values independently
tailscale amnezia-wg set '{"jc":2,"jmin":40,"jmax":70,"i1":"<b 0xc0><r 16>","i2":"<b 0x40><r 12>"}'

# Example: Node A uses CPS signatures, Node B uses basic junk packets
# Node A: '{"jc":1,"i1":"<b 0xc0><r 16>","i2":"<b 0x40><r 20>"}'  # Less jc, more CPS
# Node B: '{"jc":5,"jmin":50,"jmax":80}'                         # More jc, no CPS
# Both work fine together!
```

**For private networks (all nodes use this fork):**

```bash
# Full AmneziaWG 1.5 obfuscation - only s1/s2 must match across nodes
tailscale amnezia-wg set '{"jc":4,"jmin":40,"jmax":70,"s1":10,"s2":15,"i1":"<b 0xc0><r 32><c><t>"}'
```

**For Amnezia‑WG 1.0 compatibility:**

```bash
# Leave I1 empty to use AmneziaWG 1.0 mode (compatible with existing 1.0 deployments)
tailscale amnezia-wg set '{"jc":4,"jmin":40,"jmax":70,"s1":10,"s2":15}'
```

## Troubleshooting

**Config not saving?**

- Use JSON format: `tailscale amnezia-wg set '{"jc":4}'`
- Check permissions: run with `sudo` if needed

**Connection issues?**

- Try conservative settings first: `{"jc":3,"jmin":40,"jmax":60}`
- Reset to standard: `tailscale amnezia-wg reset`
- **Mixed networks**: Only use junk packets (`jc`, `jmin`, `jmax`) and CPS signatures (`i1`-`i5`) if connecting to standard Tailscale
- **Junk traffic optimization**: Each node can use different values - no coordination needed. More CPS signatures = fewer basic junk packets needed
- **Handshake obfuscation**: Ensure ALL nodes use this fork with identical `s1,s2` values (i1-i5 can vary per node)
- **AmneziaWG 1.0 compatibility**: Leave `i1` empty to use 1.0 mode
- **Invalid CPS format**: Check CPS syntax: `<b hex>`, `<c>`, `<t>`, `<r length>`
- Check logs: `sudo journalctl -u tailscaled -f`

**Performance issues?**

- Reduce junk packet count: `{"jc":2}`
- Avoid complex CPS signatures unless necessary
- Use simple signatures: `{"i1":"<b 0xc0><r 16>"}`
- Reduce signature chain length (use fewer i2-i5 packets)
- Monitor bandwidth overhead with signature packets

## Technical Details

- **Implementation**: Extends Tailscale's preference system
- **Storage**: Persisted in tailscaled state file
- **Scope**: Per-node configuration
- **Protocol**: Compatible with Amnezia‑WG 1.5 wire format
- **Security**: Maintains WireGuard's cryptographic guarantees
- **Obfuscation**: Multi-level transport layer obfuscation (headers, handshake, protocol masking)
- **Performance**: Single-pass AEAD encryption with SIMD optimization
- **Backward compatibility**: Full compatibility when all parameters are zero/empty

## Migration from Amnezia‑WG 1.0

If you're upgrading from Amnezia‑WG 1.0:

1. **H1–H4 remain in 1.5 but are internal/auto‑generated**: user configuration should use I1–I5 CPS packets instead of manual H1–H4 tuning.
2. **S1/S2 remain the same**: Handshake length randomization unchanged
3. **Automatic 1.0 compatibility**: When I1 is empty, behaves exactly like Amnezia‑WG 1.0
4. **Gradual migration**: Can deploy gradually - nodes with empty I1 work with 1.0 nodes

## License

BSD 3-Clause (same as Tailscale)

---

**Default behavior is identical to standard Tailscale.** Amnezia‑WG 1.5 features are only active when explicitly configured.
