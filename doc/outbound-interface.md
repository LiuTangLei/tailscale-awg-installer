# Select a physical outbound interface

[中文](outbound-interface-zh.md) · [Issue #19](https://github.com/LiuTangLei/tailscale-awg-installer/issues/19)

`tailscaled --tun=tailscale0` names the **virtual VPN interface**. It does not
select the Ethernet, Wi-Fi or PPP interface carrying the encrypted connection.
For a multi-WAN Linux host, the existing socket mark plus policy routing can
select a non-default physical egress without changing Tailscale or its transport.
This is an administrator routing configuration, not a new CLI interface option.

## Verified transport paths

Audited release: `v1.104.1`, commit
[`411ee6685`](https://github.com/LiuTangLei/tailscale/tree/411ee6685253069b5a3b496ab14c98e5b2f82afb).
Use this release source when reproducing; the mutable `main` branch need not be
the source of a published fork binary.

| Transport | Actual outer socket path on Linux |
| --- | --- |
| Standard WireGuard / AWG | magicsock `listenPacket` → `netns.Listener` → UDP |
| QUIC / HTTP3, `io=magicsock` | host Bind → magicsock UDP, or DERP TCP |
| Independent QUIC / HTTP3, `io=udp` | `carrierBind.open` → host `ListenPacket` → `netns.Listener` → separate UDP socket |
| DERP | `derphttp` → `netns.NewDialer` → TCP, normally TLS on 443 |

[magicsock](https://github.com/LiuTangLei/tailscale/blob/411ee6685253069b5a3b496ab14c98e5b2f82afb/wgengine/magicsock/magicsock.go),
[host hooks](https://github.com/LiuTangLei/tailscale/blob/411ee6685253069b5a3b496ab14c98e5b2f82afb/wgengine/userspace.go),
[independent QUIC](https://github.com/LiuTangLei/tailscale/blob/411ee6685253069b5a3b496ab14c98e5b2f82afb/wgengine/wgtransport/quicbind/backend.go),
[DERP](https://github.com/LiuTangLei/tailscale/blob/411ee6685253069b5a3b496ab14c98e5b2f82afb/derp/derphttp/derphttp_client.go).

Linux normally applies `SO_MARK=0x80000` to these sockets to bypass VPN routes.
If socket marking is unavailable, it uses `SO_BINDTODEVICE` for the **default
route's** interface. `TS_FORCE_LINUX_BIND_TO_DEVICE` chooses that fallback; it
does not accept an interface name. `TS_BIND_TO_INTERFACE_BY_ROUTE` changes route
selection on macOS/Windows only. The similarly named
`SetListenConfigInterfaceName` is used to harden the inbound peer API listener;
it is not an outbound setting and deliberately tolerates socket-option failure.
See [Linux netns](https://github.com/LiuTangLei/tailscale/blob/411ee6685253069b5a3b496ab14c98e5b2f82afb/net/netns/netns_linux.go).

## Linux policy routing example

Requires root/`NET_ADMIN` for routing and working `SO_MARK` in the daemon. A
capability-stripped userspace daemon might not set the mark; a synthetic
`ip route get ... mark ...` alone does not establish that its actual sockets do.
Do not force `TS_FORCE_LINUX_BIND_TO_DEVICE=true` with this recipe. Retain an
independent administration connection before changing live routes.

The following values are **examples**, not auto-detected settings:

- `wan2`: chosen interface, already up and addressed.
- IPv4: `198.51.100.2/24`, gateway `198.51.100.1`.
- IPv6: `2001:db8:2::2/64`, gateway `2001:db8:2::1`.
- Routing table `100` and rule priorities `5180`, `5190`: unused in both families.

First inspect `ip -4 rule`, `ip -6 rule`, both families' `route show table main`
and `route show table 100`. Adjust all addresses and identifiers for the host.
Rules must precede the daemon's bypass-to-main rule, normally priority `5210`;
other policy managers, including OpenWrt mwan3/PBR, may have earlier rules or
overwrite these settings. Integrate into that manager instead of stacking
competing rules. These commands are for a one-time application, not a repeatable
startup script.

```bash
# Install terminal guards first: an empty selected table must not fall back.
sudo ip -4 rule add pref 5190 fwmark 0x80000/0xff0000 type unreachable
sudo ip -6 rule add pref 5190 fwmark 0x80000/0xff0000 type unreachable

sudo ip -4 route add table 100 198.51.100.0/24 dev wan2 src 198.51.100.2
sudo ip -4 route add table 100 default via 198.51.100.1 dev wan2
sudo ip -6 route add table 100 2001:db8:2::/64 dev wan2 src 2001:db8:2::2
sudo ip -6 route add table 100 default via 2001:db8:2::1 dev wan2

sudo ip -4 rule add pref 5180 fwmark 0x80000/0xff0000 lookup 100
sudo ip -6 rule add pref 5180 fwmark 0x80000/0xff0000 lookup 100
```

For **IPv4-only WAN2**, keep both guards and omit the IPv6 routes and IPv6 lookup
rule: marked IPv6 is then blocked instead of leaking through another WAN. Add
any required reachable LAN routes to this dedicated table too. PPP/point-to-point
links and IPv6 link-local gateways require their actual route forms; do not
invent an Ethernet gateway for them. `SO_BINDTODEVICE` alone does not provision
addresses or gateway routes either.

Check route decisions with the actual peer/DERP literal IPs:

```bash
ip -4 route get 203.0.113.10 mark 0x80000
ip -6 route get 2001:db8:ffff::10 mark 0x80000
tailscale netcheck
tailscale ping --tsmp <peer>
```

Observe packets on the selected and other WANs, verify the real sockets carry the
mark, and test application traffic. Reconnect/restart the daemon after applying
policy to existing connections. `route get` only tests the policy; a default
disco ping alone is not application acceptance.

Rollback **only these owned rules and this previously unused table**:

```bash
sudo ip -4 rule del pref 5180 fwmark 0x80000/0xff0000 lookup 100
sudo ip -6 rule del pref 5180 fwmark 0x80000/0xff0000 lookup 100
sudo ip -4 rule del pref 5190 fwmark 0x80000/0xff0000 type unreachable
sudo ip -6 rule del pref 5190 fwmark 0x80000/0xff0000 type unreachable
sudo ip -4 route flush table 100
sudo ip -6 route flush table 100
```

Skip deletion of a lookup rule that you did not install. Rollback restores normal
egress selection. Persist the configuration through the host's network manager,
including address/gateway renewal and interface recreation. Linux may remove an
IPv6 address on link-down; restore addresses **before** reinstalling routes.

## Recovery and limits

- No configuration means no behavior change. With the policy installed, a
  selected-route failure blocks marked traffic rather than choosing another WAN.
  The mark is shared with other sockets using the same bypass mark; this is not
  a per-peer setting or a receive-interface firewall.
- `netmon` tracks interface addresses/up state and default-route changes.
  Major changes cause magicsock rebind/restun and DERP reconnect checks. A change
  only to a custom policy table need not trigger a rebind; routing still applies
  to marked sockets. Independent QUIC keeps its UDP socket on network-change
  notifications; it does not automatically rebind that socket to a new ifindex.
  The policy solution avoids that ifindex binding.
- Recovery means reconnecting once usable addresses/routes return. It does not
  guarantee seamless survival of existing TCP/QUIC sessions when source IP, NAT
  mapping or peer endpoint changes. Independent `io=udp` also requires a reachable
  configured endpoint; it does not gain magicsock NAT traversal or DERP fallback.
- Socket policy is not a whole-process DNS/privacy kill switch. System DNS,
  external proxies and other unmarked helpers need their own routing policy.
  A proxy's onward connection uses the proxy's network. NAT-PMP/UPnP discovery can
  still target the system-default gateway; do not assume it manages WAN2 while
  WAN1 remains default. Check firewall, NAT and `rp_filter` for the real topology.
- Docker bridge namespaces see container interfaces, not host physical NIC names.
  Apply policy in the relevant namespace with available capabilities, or use a
  deliberately routed dedicated namespace/container. Host networking exposes
  host interfaces but is not required or configured automatically by this guide.
- Windows uses `IP_UNICAST_IF`/`IPV6_UNICAST_IF`; macOS uses interface-index socket
  binding. Current code selects these from default/route information, not a
  user-supplied physical-interface option. Per-destination routes can help for
  stable endpoints; changing interface metrics affects other applications.
  Android/iOS need platform VPN/network lifecycle integration, not this Linux
  recipe. These platforms were source-reviewed, not runtime-tested here.

## Validation

[Reproducible fixture](../tests/interface-egress/README.md): Linux Docker kernel
`7.0.12-linuxkit`, release `411ee6685`, **14 phases / 70 socket probes passed**.
Uses real release netns hooks and actual QUIC handshakes over IPv4/IPv6; tests
non-default egress, absent IPv6 routes, main-route changes, selected-route loss,
link down/up, deletion/recreation with a new index, reconnect on the same UDP
sockets and rollback. Ordinary unmarked traffic retains its normal routing.

This is socket/routing acceptance, not authenticated WG/AWG/DERP tailnet or
multi-ISP field acceptance. No core patch, published binary or production-network
change was required. Linux [socket options](https://man7.org/linux/man-pages/man7/socket.7.html)
and [policy-rule semantics](https://man7.org/linux/man-pages/man8/ip-rule.8.html).
