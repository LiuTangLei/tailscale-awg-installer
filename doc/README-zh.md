# 支持 AmneziaWG v2 与 v3 的 Tailscale

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20OpenWrt%20|%20Android%20|%20iOS-blue)](#平台支持)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](../LICENSE)

本项目为 Tailscale 集成 AmneziaWG 混淆，同时保留官方 Tailscale 与 Headscale 的控制面兼容性。所有 AWG 参数关闭时，行为与标准 Tailscale 一致。

从 `v1.102.2` 开始同时支持两种配置：

- **AWG v3（推荐）**：增加头部保护、传输内容填充、随机时序范围，并保留垃圾包、CPS、握手及消息头混淆。
- **AWG v2（兼容模式）**：继续支持原有 `jc`、`jmin`、`jmax`、`s1`-`s4`、`h1`-`h4`、`i1`-`i5` 配置格式。

v2 唯一例外是旧 CPS `<c>` 计数器标签。AmneziaWG 上游在 `amneziawg-go v0.2.16` 重构 AWG 2 实现时将其移除；本项目在 Tailscale `v1.98.5` 更新到 `wireguard-go v0.0.20` 时引入了包含该变化的上游 `amneziawg-go v0.2.17`。旧配置只需从 `i1`-`i5` 删除 `<c>`，其余 v2 参数仍然兼容。

语言：[English](../README.md) | [中文](README-zh.md) | [فارسی](README-fa.md) | [Русский](README-ru.md)

AWG 1.5 历史说明：[README-awg-v1.5.md](README-awg-v1.5.md)。

## 安装

安装器默认选择最新稳定版。在平台安装模型允许的情况下，它会保留现有 CLI/服务状态与 AWG 偏好，只读检查可访问的旧配置是否包含 `<c>`，安装相互匹配的客户端/守护进程，最后根据实际版本显示 v2/v3 指引。安装器不会自动生成或覆盖 AWG 配置。macOS 从 Tailscale.app 切换到 CLI/utun 服务时仍需重新登录，因为两种安装模型不共享状态。

| 平台 | 命令 / 操作 |
| --- | --- |
| Linux | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` |
| macOS | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` |
| Windows（管理员 PowerShell） | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` |
| OpenWrt | 见 [OpenWrt](#openwrt) |
| Android | 从 [tailscale-android releases](https://github.com/LiuTangLei/tailscale-android/releases) 下载 APK |
| iOS | 实验性 [AwgScale](https://github.com/LiuTangLei/AwgScale)，需要 TrollStore 或具有 Packet Tunnel 权限的签名 |

指定已发布版本：

```bash
# Linux
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --version v1.102.2

# macOS
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --version v1.102.2
```

```powershell
# Windows 管理员 PowerShell
$code = (iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content
& ([scriptblock]::Create($code)) -Version v1.102.2
```

macOS 安装器使用 CLI/utun 版本。检测到 App Store 或独立版 Tailscale.app 时，会在移除存在冲突的 App/系统扩展之前询问用户。

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

## 兼容矩阵

| 本机/对端配置 | 要求 | 结果 |
| --- | --- | --- |
| 所有 AWG 参数关闭 | 任意标准 Tailscale/WireGuard 节点 | 标准 WireGuard 行为 |
| 仅 `jc`/`jmin`/`jmax` 或 `i1`-`i5` | 各节点可以不同 | 仅增加握手前垃圾包，标准节点会忽略 |
| AWG v2 的 `s1`-`s4`、`h1`-`h4` | 通信节点使用一致值 | AWG v2 通信 |
| AWG v3 | 所有通信节点都具备 v3 核心，并使用一致的共享字段 | AWG v3 通信 |
| `v1.102.2+` 应用 v2 配置 | 不含 `<c>` | 支持，并会清除残留的 v3 专用状态 |
| 历史配置含 `<c>` | 本项目从 `v1.98.5` 起不支持 | 删除 `<c>` 后再应用或同步 |

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
- `h1`-`h4`：支持单值或 `{ "min": ..., "max": ... }` 范围；四组值应互不冲突且保持一致。
- `i1`-`i5`：可选 CPS 包，各节点可以不同。

当前支持的 CPS 标签：

- `<b 0xHEX>`：固定字节。
- `<r N>`：随机字节。
- `<rc N>`：随机英文字母。
- `<rd N>`：随机十进制数字。
- `<t>`：Unix 时间戳。

不再支持 `<c>`。迁移示例：

```text
旧：i1 = <b 0xc0><r 32><c><t>
新：i1 = <b 0xc0><r 32><t>
```

I1-I5 是握手前的额外包，不承载隧道数据，也不要求两端一致。删除 `<c>` 不需要修改共享的 `s1`-`s4` 或 `h1`-`h4`。

## 从旧版本升级

1. 保存当前版本和配置：

   ```bash
   tailscale version
   tailscale awg get
   ```

2. 运行安装器。平台安装方式允许的情况下，登录状态和偏好配置都会保留。
3. 若安装器提示发现 `<c>`，只删除该标签并重新应用 JSON。
4. 选择继续使用 v2，或让整组通信节点一起迁移到 v3。
5. 使用 v3 时，先将所有参与节点升级到具备 v3 核心的版本，再生成一份 v3 配置并分发/同步。
6. 更改传输参数后，重启 `tailscaled`、容器或对应平台的 App/服务。

只升级二进制不会把当前生效的 v2 配置自动转换成 v3。

## Docker Compose

仓库中的 [docker-compose.yml](../docker-compose.yml) 使用 `ltlei/tailscale-awg:latest`，状态保存在 `./tailscale-state`。

若从旧的宿主机挂载 `/var/lib/tailscale:/var/lib/tailscale` 迁移，请先停止容器并复制目录内容：

```bash
docker compose down
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

选择 v3 前先确认拉取的镜像版本不低于 `v1.102.2`：

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

OpenWrt、Android、iOS 独立发布。同步 v3 前必须检查实际客户端/核心版本；只要任一通信端尚不支持 v3，就继续使用 v2。

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

若同步历史配置后失败，检查 `i1`-`i5` 是否含 `<c>`；先修正作为配置源的节点，再重新同步。

## 平台支持

| 平台 | 架构 | 安装器/状态 |
| --- | --- | --- |
| Linux | x86_64、ARM64 | 本仓库安装器 |
| macOS | Intel、Apple Silicon | 本仓库 CLI/utun 安装器 |
| Windows | x86_64、ARM64 | 管理员 PowerShell 安装器 |
| OpenWrt | 取决于独立发行版 | 独立安装器仓库 |
| Android | ARM64、ARM | 独立 APK 发行 |
| iOS | iPhone/iPad | 实验性独立客户端 |

## 链接

- Tailscale fork releases：<https://github.com/LiuTangLei/tailscale/releases>
- Android APK：<https://github.com/LiuTangLei/tailscale-android/releases>
- iOS 客户端：<https://github.com/LiuTangLei/AwgScale>
- Installer issues：<https://github.com/LiuTangLei/tailscale-awg-installer/issues>
- AmneziaWG 上游：<https://github.com/amnezia-vpn/amneziawg-go>

## 许可证

BSD 3-Clause，与上游 Tailscale 一致。
