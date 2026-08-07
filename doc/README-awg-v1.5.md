# Legacy AWG 1.5 notes

This page is an archive for profiles created by early releases of this fork. It is not an installation guide. For current installers, AWG v2/v3 behavior, and platform support, use the [main README](../README.md).

## Historical profile model

Early profiles used the following groups of fields:

- `jc`, `jmin`, and `jmax` for pre-handshake junk traffic.
- `s1`-`s4` and `h1`-`h4` for shared handshake/header masquerading. Communicating AWG peers need compatible shared values.
- `i1`-`i5` for optional per-node CPS packets such as `<b 0xc0><r 16><t>`.

Example archived profile:

```json
{
  "jc": 2,
  "jmin": 64,
  "jmax": 128,
  "s1": 10,
  "s2": 15,
  "h1": 123456,
  "h2": 789012,
  "h3": 345678,
  "h4": 901234,
  "i1": "<b 0xc0><r 16><t>"
}
```

Large junk counts and long CPS expressions increase bandwidth use and latency. With every AWG field disabled, the fork uses standard WireGuard behavior.

## Using an archived profile today

Current releases starting with `v1.102.2` can run AWG v3 or a compatible AWG v2 profile. Save the old JSON, install the current release by following the main README, then validate the profile before applying or syncing it:

```bash
tailscale awg get
tailscale awg validate
```

> Compatibility: AmneziaWG removed the legacy CPS `<c>` counter in the `amneziawg-go v0.2.16` AWG 2 refactor; this fork inherited the change in `v1.98.1`, so remove that tag from old `i1`-`i5` values.

To create a new profile, run `tailscale awg set`: press Enter for the recommended v3 generator or choose `2` for v2 compatibility.

## References

- [Current installer and compatibility guide](../README.md)
- [Tailscale fork releases](https://github.com/LiuTangLei/tailscale/releases)
- [AmneziaWG upstream](https://github.com/amnezia-vpn/amneziawg-go)
