# Tailscale + AmneziaWG / QUIC

[English](../README.md) · [فارسی](README-fa.md) · [Русский](README-ru.md) · [下载](https://github.com/LiuTangLei/tailscale/releases/latest)

**Current release: v1.104.4** — desktop, Docker, OpenWrt, Android and AwgScale.
带 AmneziaWG 与 QUIC 混淆传输的 Tailscale fork，兼容官方 Tailscale 控制端和 Headscale。在你切换传输之前，行为与标准 Tailscale 一致。

[![Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=release)](https://github.com/LiuTangLei/tailscale/releases/latest) [![Docker](https://img.shields.io/docker/v/ltlei/tailscale-awg?sort=semver&label=docker)](https://hub.docker.com/r/ltlei/tailscale-awg/tags)

版本号与上游一致：fork `vX.Y.Z` 基于 Tailscale `vX.Y.Z`。

## 功能

- **三种节点级传输**：标准 WireGuard（默认）、AWG v3 / v2、QUIC。
- **AWG v3**：报头保护、内容填充、随机时序；保留 AWG v2 兼容旧节点。
- **QUIC**：基于 TLS 的 HTTP/3，搭配调优的 BBRv3；节点按节点密钥自动互信，无需同步参数。
- **0-RTT 快速重连**：v1.104.2 及以上节点之间使用一次性票据，失败自动回退完整握手；与 v1.104.1 的 QUIC 节点保持兼容。
- **弱网乱序更稳**：乱序到达的 QUIC 包不再被误判为重复包丢弃。
- **可选服务端角色**：`tailscale awg server on` 后，客户端连接本节点时使用 Chromium 风格的 TLS ClientHello。
- **一条命令切换**并自动重启，`tailscale awg doctor` 一键诊断。
- **安全升级**：安装器校验 SHA-256，失败自动回滚，并保留当前传输模式。

## 安装

| 平台 | 安装 / 下载 | 版本 |
| --- | --- | --- |
| Linux | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` | [![release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=)](https://github.com/LiuTangLei/tailscale/releases/latest) |
| macOS | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` | [![release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=)](https://github.com/LiuTangLei/tailscale/releases/latest) |
| Windows（管理员 PowerShell） | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` | [![release](https://img.shields.io/github/v/release/LiuTangLei/tailscale?label=)](https://github.com/LiuTangLei/tailscale/releases/latest) |
| Docker | `ltlei/tailscale-awg:latest`（[见下文](#docker)） | [![docker](https://img.shields.io/docker/v/ltlei/tailscale-awg?sort=semver&label=)](https://hub.docker.com/r/ltlei/tailscale-awg/tags) |
| OpenWrt | [安装器、软件包与软件源](https://github.com/LiuTangLei/openwrt-tailscale-awg) | [![openwrt](https://img.shields.io/github/v/release/LiuTangLei/openwrt-tailscale-awg?label=)](https://github.com/LiuTangLei/openwrt-tailscale-awg/releases/latest) |
| Android | [签名 APK](https://github.com/LiuTangLei/tailscale-android/releases/latest) | [![android](https://img.shields.io/github/v/release/LiuTangLei/tailscale-android?label=)](https://github.com/LiuTangLei/tailscale-android/releases/latest) |
| iOS | [AwgScale IPA](https://github.com/LiuTangLei/AwgScale/releases/latest) | [![ios](https://img.shields.io/github/v/release/LiuTangLei/AwgScale?label=)](https://github.com/LiuTangLei/AwgScale/releases/latest) |

- 需要手动安装？见 [手动安装教程](manual-install-zh.md)，涵盖 Linux、macOS、Windows、OpenWrt 和手机。
- 桌面安装器默认安装最新版，支持 x86_64 / ARM64。指定版本加 `--version <tag>`（Windows 为 `-Version <tag>`）；Linux / macOS 卸载加 `--uninstall`。
- macOS 使用 CLI/utun 守护进程，从 Tailscale.app 迁移需要重新登录。
- Windows GUI 必须与 fork 的基础 Tailscale 版本一致。
- iOS 需要 TrollStore 或 Packet Tunnel 权限，IPA 不是 App Store 签名。
- 系统包管理器升级可能换回官方二进制；`tailscale awg` 命令消失时重新运行安装器。

## GitHub 镜像

GitHub 访问慢或不可用时，在脚本地址前加镜像前缀，并把同一前缀传给安装器。Linux / macOS 用 `--mirror`，Windows 用 `-MirrorPrefix` 或环境变量 `MIRROR_PREFIX`。

```bash
# macOS 把 install-linux.sh 换成 install-macos.sh
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \
  | bash -s -- --mirror https://ghfast.top
```

```powershell
$m = 'https://ghfast.top'
$code = (iwr -useb "$m/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1").Content
& ([scriptblock]::Create($code)) -MirrorPrefix $m
```

| 镜像 | 说明 |
| --- | --- |
| `https://ghfast.top` | OpenWrt 安装器默认镜像 |
| `https://gh-proxy.org` | OpenWrt 安装器备用镜像 |
| `https://gh-proxy.com` | 同时代理 GitHub API |
| 自建 | 任何支持 `https://<镜像>/https://github.com/...` 格式的代理，例如用 Cloudflare Workers 或 Docker 自建 [gh-proxy](https://github.com/hunshcn/gh-proxy) |

- 安装器通过 `api.github.com` 获取最新版本，先直连，失败再走镜像。多数镜像不代理 API；查询失败时改用 `gh-proxy.com`，或按上方徽章显示的版本加 `--version <tag>`。
- 公共镜像由第三方运营，可能变更或失效；重要机器建议使用自建镜像。
- OpenWrt 安装器会自动尝试上述镜像，自建镜像用 `install.sh --custom-proxy`。

## 连接与配置

```bash
tailscale up
```

Headscale 改用：`tailscale up --login-server https://你的域名`。

| 操作 | 命令 |
| --- | --- |
| 选择 AWG v3（默认）、v2 或 QUIC | `tailscale awg set` |
| 启用 QUIC | `tailscale awg set --yes quic` |
| 查看 / 保存 AWG JSON | `tailscale awg get` |
| 应用已有 JSON | `tailscale awg set '<JSON>'` |
| 同步兼容在线节点的配置 | `tailscale awg sync` |
| 声明本节点为 QUIC 服务端 | `tailscale awg server on` |
| 恢复标准 WireGuard | `tailscale awg reset` |
| 查看生效模式 / 诊断 | `tailscale awg status` / `tailscale awg doctor` |

- AWG 通信双方的共享字段必须一致。生成一次，保存 JSON 后分发或同步。
- QUIC 对整个节点生效，所有通信节点都要启用，不会自动回退 WireGuard。启用 QUIC 会清除 AWG 配置，以后还要用请先保存 JSON。
- 切换传输会重启本机服务，VPN 短暂中断；远程操作时请保留其他管理通道。

## Docker

使用 [docker-compose.yml](../docker-compose.yml)，镜像为 `ltlei/tailscale-awg:latest` 或 `:v1.104`（自动跟随最新补丁版），支持 amd64、arm64、arm/v7、386。

```bash
curl -fsSLO https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/docker-compose.yml
docker compose pull
docker compose up -d
docker compose exec tailscaled tailscale up
```

Headscale 在 `tailscale up` 后加 `--login-server https://你的域名`。无人值守登录请私下提供 `TS_AUTHKEY`，不要提交到仓库。

容器内先暂存传输配置，再重启容器：

```bash
docker compose exec tailscaled tailscale awg set --no-restart --yes quic
docker compose restart tailscaled
```

AWG 将 `--yes quic` 替换为 `'<JSON>'`。

- 保留镜像自带的 `containerboot` 启动命令和**整个** `./tailscale-state` 目录，不要让多个守护进程共用运行中的节点状态。
- TUN 模式需要 `/dev/net/tun` 与 `NET_ADMIN`，路由只作用于容器内。出口节点 / 子网路由还需开启转发并在控制端批准。`TS_AUTH_ONCE=true` 时，后续路由变更需显式执行 `tailscale set`。
- 无 TUN、无额外权限时，**单独**使用 [compose.userspace.yml](../compose.userspace.yml)（`docker compose -f compose.userspace.yml up -d`，后续命令同样带 `-f`）。应用需通过 SOCKS5 `1055` 或 HTTP `1056` 代理访问。

## 排查

检查 `tailscale version`、`tailscale netcheck`、`tailscale awg doctor`、`tailscale ping --tsmp <对端>`。仅 `tailscale ping` 成功不代表业务流量正常。提交 [Issue](https://github.com/LiuTangLei/tailscale-awg-installer/issues) 时请附上双方版本和诊断结果。

[BSD 3-Clause 许可证](../LICENSE) · [Tailscale](https://github.com/tailscale/tailscale) · [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-go)
