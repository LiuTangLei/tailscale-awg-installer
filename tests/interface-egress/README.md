# Linux outbound-interface policy regression

Run the matrix **only inside the disposable container below**. It creates routes,
rules and two network namespaces. It needs no host networking, TUN, public ports,
tailnet credentials or existing Tailscale state.

Build `probe.go` from the verified fork source, not the installer's directory.
The example assumes a native arm64 Docker engine; use `GOARCH=amd64` for x86_64.
Use absolute paths for both directories:

```bash
PROOF=/absolute/path/to/tailscale-awg-installer/tests/interface-egress
SOURCE=/absolute/path/to/LiuTangLei-tailscale-v1.104.1
cd "$SOURCE"
git rev-parse HEAD  # tested release: 411ee6685253069b5a3b496ab14c98e5b2f82afb
GOWORK=off GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -mod=readonly -o "$PROOF/egress-probe" "$PROOF/probe.go"
docker build -t tailscale-interface-test "$PROOF"
docker run --rm --network none \
  --cap-add NET_ADMIN --cap-add NET_RAW --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined --security-opt seccomp=unconfined \
  -e ISSUE19_DISPOSABLE_FIXTURE=1 -v "$PROOF:/proof" \
  tailscale-interface-test python3 -u /proof/matrix.py
```

The additional namespace capability and security options are for this test
fixture, **not** the Tailscale deployment. Remove the test image afterward if
unneeded: `docker image rm tailscale-interface-test`.

The probe uses the release's real `netns.Listener` / `netns.NewDialer`, checks
`SO_MARK=0x80000`, keeps its UDP / QUIC transport sockets open across phases,
and performs actual UDP echoes, TCP transfers and QUIC TLS handshakes over IPv4
and IPv6. Its certificate verification bypass is restricted to this isolated
test. The two gateways identify which link received the connection.

Expected result: **14 phases, 70 probes**, with results in `matrix-result.json`.
Checks include VPN loop bypass, non-default egress, ordinary unmarked traffic,
main-route changes, missing selected routes, link down/up, interface deletion
and recreation with a new index, IPv6 without a configured egress, reconnect,
and rollback. IPv6 address restoration models a network manager after link-up.

This tests the common socket/routing contract and real QUIC handshakes. It does
not create authenticated WireGuard/AWG peers or a DERP session, prove seamless
survival of an existing session after an address/NAT change, or simulate an ISP.
