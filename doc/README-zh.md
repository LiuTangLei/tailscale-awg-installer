# 支持 AmneziaWG 与 QUIC / HTTP/3 的 Tailscale

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20OpenWrt%20|%20Android%20|%20iOS-blue)](#平台支持)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](../LICENSE)

本项目为 Tailscale 集成可选的 AmneziaWG 或 QUIC / HTTP/3 数据传输，同时保留官方 Tailscale 与 Headscale 的控制面兼容性。默认仍为原生 WireGuard；在 native 模式下关闭所有 AWG 参数，即恢复标准 WireGuard 行为。升级不会自动把现有节点切换到 HTTP/3。

**最新集成版：[v1.102.4](https://github.com/LiuTangLei/tailscale/releases/tag/v1.102.4)。** 已合并上游 Tailscale 1.102.4 及当前 H3 原生 IP 实现，QUIC 依赖固定为已发布的 `v0.62.0-tailscale.4`。HTTP/3 需要显式启用；移动端、路由器仍独立发布，不能默认认为已包含 H3。

从 `v1.102.2` 开始同时支持两种配置：

- **AWG v3（推荐）**：增加头部保护、传输内容填充、随机时序范围，并保留垃圾包、CPS、握手及消息头混淆。
- **AWG v2（兼容模式）**：继续支持原有 `jc`、`jmin`、`jmax`、`s1`-`s4`、`h1`-`h4`、`i1`-`i5` 配置格式。

语言：[English](../README.md) | [中文](README-zh.md) | [فارسی](README-fa.md) | [Русский](README-ru.md)

AWG 1.5 历史说明：[README-awg-v1.5.md](README-awg-v1.5.md)。

## 安装

安装器默认选择最新稳定版。在平台安装模型允许的情况下，它会保留现有 CLI/服务状态与 AWG 偏好，执行只读迁移检查，安装相互匹配的客户端/守护进程，最后根据实际版本显示 v2/v3 指引。安装器不会自动生成或覆盖 AWG 配置。macOS 从 Tailscale.app 切换到 CLI/utun 服务时仍需重新登录，因为两种安装模型不共享状态。

替换前，各桌面安装器都会检查架构与内嵌版本；能直接取得可信发布元数据且资产提供 GitHub SHA-256 摘要时，还会校验摘要。二进制替换事务会保留恢复副本与原服务配置；若回滚不完整，恢复副本会留在磁盘上而不会被清理。Linux 同时支持 systemd 与 OpenRC；Windows GUI 必须与 fork 的官方基础版本完全一致。

Linux 发行版升级 Tailscale 软件包、或 macOS 升级 Homebrew formula 时，都可能重新写回官方二进制。若包更新后 AWG 命令消失，请重新运行安装器并再次确认 `tailscale version`。

| 平台 | 命令 / 操作 |
| --- | --- |
| Linux | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` |
| macOS | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` |
| Windows（管理员 PowerShell） | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` |
| OpenWrt | 见 [OpenWrt](#openwrt) |
| Android | 从 [tailscale-android releases](https://github.com/LiuTangLei/tailscale-android/releases) 下载 APK |
| iOS | 实验性 [AwgScale](https://github.com/LiuTangLei/AwgScale)；普通签名可使用 app-only 功能，系统 VPN 需要 TrollStore 或 Packet Tunnel 权限 |

指定已发布版本：

```bash
# Linux
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --version v1.102.4

# macOS
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --version v1.102.4
```

```powershell
# Windows 管理员 PowerShell
$code = (iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content
& ([scriptblock]::Create($code)) -Version v1.102.4
```

macOS 安装器使用 CLI/utun 版本。检测到 App Store 或独立版 Tailscale.app 时，会先征得同意并暂存 App 以便回滚；迁移中由用户停用的 System/Network Extension 无法由脚本自动重新启用。

## 快速开始

使用普通控制面登录：

```bash
# 官方 Tailscale
tailscale up

# Headscale
tailscale up --login-server https://你的域名
```

生成配置：

```bash
tailscale awg set
```

在 `v1.102.2+` 中，交互式生成器提供：

1. **AWG v3**：推荐选项，直接回车默认生成 v3。
2. **AWG v2**：输入 `2`，用于尚未升级到 v3 核心的旧节点、移动端或路由器。

应用前会先显示完整 JSON。请把它作为配置源保存，再复制到其他参与通信的节点，或从兼容且在线的节点执行 `tailscale awg sync`。

```bash
tailscale awg get
tailscale awg validate # v1.102.2+
tailscale awg sync
tailscale awg reset
```

## QUIC / HTTP/3 模式（v1.102.4+）

HTTP/3 模式直接通过经过身份认证的 QUIC DATAGRAM 承载 IP 包，不是把 WireGuard 再套进 QUIC。当前实现包含节点密钥自动认证、身份与配置持久化、有限批量发送、认证后的直接收包及接收缓冲复用。不能据此宣称所有线路都达到 WireGuard 速度，也不能宣称流量与真实浏览器完全一致。

切换前应升级所有参与节点。模式按整个节点生效：H3 节点不会为了旧对端自动回退到原生 WG/AWG。已配置 AWG 时，先保存 JSON，再显式清除 AWG 参数。不要通过唯一的远程管理连接切换传输模式，应保留独立恢复通道。

```bash
tailscale awg status
# 仅在已配置 AWG 时：先保存输出，再重置。
tailscale awg get
tailscale awg reset
# 为下次启动保存 HTTP/3 模式，并启用节点密钥自动信任。
tailscale awg transport --yes http3-ip
# 使用当前平台的服务管理器重启现有 tailscaled 服务。
tailscale awg status
tailscale awg doctor
```

Docker 中将命令改为 `docker compose exec tailscaled tailscale ...`，最后执行 `docker compose restart tailscaled` 应用模式。务必持久化**整个状态目录**，包括传输身份和配置，不能只保留 `tailscaled.state`。

可选的节点级服务端声明：`tailscale awg server --yes on`。只有非服务端主动连接已认证的声明服务端时，才使用 Chromium 风格的 H3 ClientHello；服务端互联、普通 Mesh 保持标准 TLS。它不是完整浏览器指纹复制，不会自动开放或修改监听端口。修改声明后需要重启守护进程。

恢复原生 WG/AWG：执行 `tailscale awg transport --yes native` 后重启。native 不会自动生成 AWG 配置，需要时重新应用之前保存的 JSON。旧实验配置中的原始 `quic-ip` 仍被接受，新部署推荐 `http3-ip`。

## 兼容矩阵

| 本机/对端配置 | 要求 | 结果 |
| --- | --- | --- |
| native 模式，所有 AWG 参数关闭 | 任意标准 Tailscale/WireGuard 节点 | 标准 WireGuard 行为 |
| HTTP/3（`http3-ip`） | 所有通信节点具备兼容的 H3 实现，AWG 关闭 | 原生 QUIC-IP 传输，不自动回退 WG |
| 仅 `jc`/`jmin`/`jmax` 或 `i1`-`i5` | 各节点可以不同 | 仅增加握手前垃圾包，标准节点会忽略 |
| AWG v2 的 `s1`-`s4`、`h1`-`h4` | 通信节点使用一致值 | AWG v2 通信 |
| AWG v3 | 所有通信节点都具备 v3 核心，并使用一致的共享字段 | AWG v3 通信 |
| `v1.102.2+` 应用 v2 配置 | 使用受支持的 v2 字段 | 支持，并会清除残留的 v3 专用状态 |

不能只在通信的一端启用 v3。支持 v3 的二进制可以运行 v2 或 v3，但双方当前生效的配置必须兼容。

## AWG v3 新增内容

AWG v3 保留全部 v2 字段，并增加：

| JSON 字段 | 作用 | 是否需要一致 |
| --- | --- | --- |
| `header_protection_key` | 64 个十六进制字符表示的 32 字节头部保护密钥 | v3 通信节点必须一致；非零密钥要求 `s1`-`s4 >= 12` |
| `content_padding_addition` | 随机传输内容填充范围 | 可以不同 |
| `rekey_after_time` | 随机重新握手间隔 | 本地时序，可以不同 |
| `rekey_timeout` | 随机握手重试超时 | 本地时序，可以不同 |
| `reject_after_time` | 随机会话拒绝时限 | 本地时序，可以不同 |
| `keepalive_timeout` | 随机保活超时 | 本地时序，可以不同 |
| `max_handshake_attempts` | 随机最大握手次数 | 本地行为，可以不同 |

v3 生成器会创建新的范围和头部保护密钥。不要复制 README 中的固定密钥；应生成一份真实配置，再把必须一致的字段分发给目标节点。

## AWG v2 兼容性

`v1.102.2+` 继续支持：

- `jc`、`jmin`、`jmax`：握手前垃圾包数量与大小。
- `s1`-`s4`：消息前缀/填充，通信节点必须一致。
- `h1`-`h4`：支持单值或 `{ "min": ..., "max": ... }` 范围；实际范围不能重叠，共享值必须保持一致。
- `i1`-`i5`：可选 CPS 包，各节点可以不同。

常用 CPS 标签包括：

- `<b 0xHEX>`：固定字节。
- `<r N>`：随机字节。
- `<rc N>`：随机英文字母。
- `<rd N>`：随机十进制数字。
- `<t>`：Unix 时间戳。

> 兼容提示：AmneziaWG 在 `amneziawg-go v0.2.16` 重构 AWG 2 时移除了旧 CPS `<c>` 计数器；本项目从 `v1.98.1` 起继承该变化，旧 `i1`-`i5` 删掉该标签即可。

## 从旧版本升级

1. 保存当前版本和配置：

   ```bash
   tailscale version
   tailscale awg get
   ```

2. 运行安装器。平台安装方式允许的情况下，登录状态和偏好配置都会保留。
3. 选择继续使用 v2，或让整组通信节点一起迁移到 v3。
4. 使用 v3 时，先将所有参与节点升级到具备 v3 核心的版本，再生成一份 v3 配置并分发/同步。
5. 执行 `tailscale awg set` 或 `tailscale awg sync` 后按提示重启；`v1.102.2` 在两种命令成功后都默认建议重启。

只升级二进制不会把当前生效的 v2 配置自动转换成 v3。

## Docker Compose

仓库中的 [docker-compose.yml](../docker-compose.yml) 使用 `ltlei/tailscale-awg:latest`，完整状态目录保存在 `./tailscale-state`。固定本次版本可使用 `ltlei/tailscale-awg:v1.102.4`。

**镜像和 Compose 配置应一起升级。** 保留镜像默认的 `containerboot`，不要用 `command: tailscaled ...` 覆盖入口。该入口负责解释 `TS_STATE_DIR`、`TS_SOCKET`、`TS_AUTHKEY`、`TS_EXTRA_ARGS`、`TS_USERSPACE` 等环境变量。示例使用持久化状态与内核网络模式；`TS_AUTH_ONCE=true` 会在已登录后保留节点状态，因此后续重启不会自动重新应用登录/up 参数。

需要首次无人值守登录时，通过私有部署环境设置 `TS_AUTHKEY`；Headscale 可另外设置 `TS_EXTRA_ARGS=--login-server=https://你的域名 --accept-routes`。不要把认证密钥提交到仓库。不设置认证密钥时，按下面的 CLI 流程完成登录。[issue #18](https://github.com/LiuTangLei/tailscale-awg-installer/issues/18) 的完整修复同时需要 v1.102.4 的 CLI/镜像修复与恢复启动入口：旧版 `tailscale up` 会在重启时覆盖已保存的 AWG 配置。新版 `up --reset` 也会保留独立管理的 AWG 配置，需要关闭时显式执行 `tailscale awg reset`。

若从旧的宿主机挂载 `/var/lib/tailscale:/var/lib/tailscale` 迁移，复制前应停止所有正在使用该状态的进程。不要让宿主机守护进程与容器同时使用同一节点状态。

```bash
docker compose down
# 若宿主机服务也使用此目录，按实际 init 系统选择：
# systemd：sudo systemctl stop tailscaled
# OpenRC： sudo rc-service tailscaled stop || sudo rc-service tailscale stop
mkdir -p ./tailscale-state
cp -a /var/lib/tailscale/. ./tailscale-state/
```

```bash
docker compose pull
docker compose up -d
docker compose exec tailscaled tailscale up
docker compose exec tailscaled tailscale awg set
```

使用 Headscale 时，把登录命令改为 `docker compose exec tailscaled tailscale up --login-server https://你的域名`。

依赖 Docker 修复或启用 H3 前，确认客户端与守护进程都为 `1.102.4` 或更新版本：

```bash
docker compose exec tailscaled tailscale version
```

Compose 服务/容器名是 `tailscaled`，容器里的命令是 `tailscale`：

```bash
docker exec -it tailscaled tailscale awg get
```

## OpenWrt

```bash
wget -O /usr/bin/install.sh https://raw.githubusercontent.com/LiuTangLei/openwrt-tailscale-awg/main/install_en.sh
chmod +x /usr/bin/install.sh
/usr/bin/install.sh
```

GitHub 访问受限时：

```bash
wget -O /usr/bin/install.sh https://ghfast.top/https://raw.githubusercontent.com/LiuTangLei/openwrt-tailscale-awg/main/install.sh
chmod +x /usr/bin/install.sh
/usr/bin/install.sh
```

OpenWrt、Android、iOS 独立发布。本次桌面/Docker 发布不包含新 APK、IPA 或路由器软件包。同步 v3 前必须检查实际客户端/核心版本；只要任一通信端尚不支持 v3，就继续使用 v2。包含不支持 H3 客户端的通信组不能直接切换到 H3。

## 镜像

Linux/macOS 使用 `--mirror PREFIX`，Windows 使用 `-MirrorPrefix`：

```bash
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com
```

```powershell
$code = (iwr -useb https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content
& ([scriptblock]::Create($code)) -MirrorPrefix 'https://your-mirror-site.com'
```

## 排错

先确认客户端、守护进程和 AWG 配置：

```bash
tailscale version
tailscale awg get
tailscale awg validate # v1.102.2+
```

如果 `tailscale ping` 成功而普通流量失败，需要注意默认 `tailscale ping` 是 disco 层检查，不经过双方 TUN。可以先重置 AWG，再逐步恢复参数：

```bash
tailscale awg reset
tailscale awg set '{"jc":2,"jmin":64,"jmax":128}'
```

## 平台支持

| 平台 | 架构 | 安装器/状态 |
| --- | --- | --- |
| Linux | x86_64、ARM64 | 本仓库安装器 |
| macOS | Intel、Apple Silicon | 本仓库 CLI/utun 安装器 |
| Windows | x86_64、ARM64 | 管理员 PowerShell 安装器 |
| OpenWrt | 取决于独立发行版 | 独立安装器仓库 |
| Android | 通用 APK（ARM64、ARM、x86_64、x86） | 独立 APK 发行 |
| iOS | iPhone/iPad（iOS 15+） | 实验性独立客户端；系统 VPN 需要 TrollStore 或 Packet Tunnel 权限 |

## 链接

- Tailscale fork releases：<https://github.com/LiuTangLei/tailscale/releases>
- Android APK：<https://github.com/LiuTangLei/tailscale-android/releases>
- iOS 客户端：<https://github.com/LiuTangLei/AwgScale>
- Installer issues：<https://github.com/LiuTangLei/tailscale-awg-installer/issues>
- AmneziaWG 上游：<https://github.com/amnezia-vpn/amneziawg-go>

## 许可证

BSD 3-Clause，与上游 Tailscale 一致。
