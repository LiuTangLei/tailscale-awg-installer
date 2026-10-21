# 指定底层物理出口网卡

[English / 源码与完整边界](outbound-interface.md) · [Issue #19](https://github.com/LiuTangLei/tailscale-awg-installer/issues/19)

`tailscaled --tun=tailscale0` 设置的是 **VPN 虚拟网卡名称**，不决定加密连接使用
哪张以太网、Wi-Fi 或 PPP 网卡。

Linux 多宽带场景可以利用现有 socket 标记配合策略路由，选择非默认物理出口，
**无需修改 WG、AWG 或 QUIC 核心**。这是管理员网络配置，不是新增了指定网卡的
CLI 参数。核对版本为 `v1.104.1`，提交
[`411ee6685`](https://github.com/LiuTangLei/tailscale/tree/411ee6685253069b5a3b496ab14c98e5b2f82afb)；
不要把会变化的 `main` 分支直接当作已发布 fork 二进制的源码。

| 传输 | Linux 底层路径 |
| --- | --- |
| WireGuard / AWG | magicsock → `netns.Listener` → UDP |
| QUIC / HTTP3，`io=magicsock` | 复用 magicsock 的 UDP 或 DERP TCP |
| 独立 QUIC / HTTP3，`io=udp` | host `ListenPacket` → `netns.Listener` → 独立 UDP socket |
| DERP | `derphttp` → `netns.NewDialer` → TCP，通常为 TLS/443 |

这些 socket 通常设置 `SO_MARK=0x80000`，用于绕过 VPN 路由。
`TS_FORCE_LINUX_BIND_TO_DEVICE` 只强制绑定**系统默认出口**，不能填写网卡名；
`TS_BIND_TO_INTERFACE_BY_ROUTE` 对绑定行为的调整只适用于 macOS/Windows。
源码中的 `SetListenConfigInterfaceName` 用于入站 peer API 监听器加固，失败会被
容忍，不是出站配置开关。

## Linux 配置示例

前提：管理员可修改路由，守护进程能实际设置 `SO_MARK`，没有强制开启
`TS_FORCE_LINUX_BIND_TO_DEVICE=true`。裁剪权限的 userspace 容器可能无法打标；
带 `mark` 的合成路由查询不能证明真实 socket 已打标。修改运行中的网络前，保留
独立管理连接。

以下为**示例值，必须替换**：已启用并有地址的网卡 `wan2`，IPv4 地址
`198.51.100.2/24`、网关 `198.51.100.1`，IPv6 地址 `2001:db8:2::2/64`、网关
`2001:db8:2::1`。两种地址族的路由表 `100` 和规则优先级 `5180` / `5190` 必须未被占用。

先检查 `ip -4 rule`、`ip -6 rule`，以及两种地址族的 `route show table main`
和 `route show table 100`。规则要排在 Tailscale 的 bypass-to-main 规则之前，
后者通常为 `5210`。OpenWrt mwan3/PBR 等管理器可能设置更早的规则或覆盖配置，
应在现有管理器中集成。以下为一次性命令，不是可重复执行的启动脚本。

```bash
# 先安装终止规则，避免指定路由丢失后改走另一条宽带。
sudo ip -4 rule add pref 5190 fwmark 0x80000/0xff0000 type unreachable
sudo ip -6 rule add pref 5190 fwmark 0x80000/0xff0000 type unreachable

sudo ip -4 route add table 100 198.51.100.0/24 dev wan2 src 198.51.100.2
sudo ip -4 route add table 100 default via 198.51.100.1 dev wan2
sudo ip -6 route add table 100 2001:db8:2::/64 dev wan2 src 2001:db8:2::2
sudo ip -6 route add table 100 default via 2001:db8:2::1 dev wan2

sudo ip -4 rule add pref 5180 fwmark 0x80000/0xff0000 lookup 100
sudo ip -6 rule add pref 5180 fwmark 0x80000/0xff0000 lookup 100
```

WAN2 **只有 IPv4** 时保留两种地址族的终止规则，省略 IPv6 路由和 IPv6 lookup
规则；这样 IPv6 被阻断，不会走另一条宽带。需要访问的局域网路由也要补入专用表。
PPP 点对点出口和 IPv6 链路本地网关应使用实际路由形式，不能照搬以太网示例。
`SO_BINDTODEVICE` 本身也不会替你配置地址和网关路由。

使用实际 Peer / DERP IP 检查：

```bash
ip -4 route get 203.0.113.10 mark 0x80000
ip -6 route get 2001:db8:ffff::10 mark 0x80000
tailscale netcheck
tailscale ping --tsmp <peer>
```

同时在指定和其他 WAN 上抓包，确认真实 socket 的标记和业务传输。应用策略后，
对已有连接重新连接或重启守护进程。合成路由查询或默认 disco ping 不代替业务验收。

回滚时只删除**本次创建的规则和原先未使用的专用表**：

```bash
sudo ip -4 rule del pref 5180 fwmark 0x80000/0xff0000 lookup 100
sudo ip -6 rule del pref 5180 fwmark 0x80000/0xff0000 lookup 100
sudo ip -4 rule del pref 5190 fwmark 0x80000/0xff0000 type unreachable
sudo ip -6 rule del pref 5190 fwmark 0x80000/0xff0000 type unreachable
sudo ip -4 route flush table 100
sudo ip -6 route flush table 100
```

没有创建的 lookup 规则不需要删除。回滚后恢复正常出口选择。持久化应接入本机
网络管理器，处理 DHCP/PPPoE 地址或网关更新、网卡删除重建。Linux 可能在网卡
关闭时移除 IPv6 地址；恢复时先恢复地址，再安装路由。

## 恢复和平台边界

- 未配置策略时原有行为不变。配置后指定路由失效会阻断已标记流量。相同 bypass
  mark 的其他 socket 也受影响；它不是逐 Peer 配置，也不是入站接口防火墙。
- `netmon` 监控接口地址、启停和默认路由。重大变化触发 magicsock 重绑、STUN 和
  DERP 重连检查。只改变自定义策略表不一定触发重绑，内核路由仍作用于已标记
  socket。独立 QUIC 在网络通知时保留 UDP socket，不会把绑定的旧 ifindex
  自动改成新索引；策略路由方案避免固定绑定。
- “恢复”指地址和路由恢复后可重连，不保证源 IP、NAT 映射变化时已有 TCP/QUIC
  会话无缝存活。独立 `io=udp` 仍需要可达端点，没有因此获得打洞或 DERP 回退。
- 这不是整个进程的 DNS/隐私断网保护。系统 DNS、外部代理、其他未标记辅助流量
  需独立策略。代理后续连接走代理网络；NAT-PMP/UPnP 可能仍按默认网关发现，
  不能假设在管理 WAN2。防火墙、NAT、`rp_filter` 要结合实网检查。
- Docker bridge 内看到的是容器接口。应在正确命名空间配置，或使用有明确出口的
  独立命名空间/容器；本方案不要求、也不自动启用 host networking。
- Windows 使用 `IP_UNICAST_IF` / `IPV6_UNICAST_IF`，macOS 使用接口索引绑定，
  当前选择来自默认/目标路由，并非用户网卡选项。固定端点可考虑目标路由；修改
  网卡 metric 会影响其他应用。Android/iOS 涉及平台 VPN 生命周期。这些平台
  本次只审阅源码，未做运行验收，不能套用 Linux 命令。

## 已完成验证

[可复现测试](../tests/interface-egress/README.md)：Linux Docker 内核
`7.0.12-linuxkit`、发布源码 `411ee6685`，**14 阶段、70 次 socket 探测通过**。
使用真实 netns hook、IPv4/IPv6 UDP/TCP 和真实 QUIC TLS 握手，覆盖非默认出口、
未配置 IPv6、默认路由变化、路由丢失、网卡关闭/恢复、删除后以新索引重建、
同一 UDP socket 重连、回滚，及普通未标记流量维持原有路由。

这证明 socket/策略路由契约，不是已认证 WG/AWG/DERP Tailnet 或真实双运营商验收。
本次未修改传输核心、发布新二进制或改变生产网络。
