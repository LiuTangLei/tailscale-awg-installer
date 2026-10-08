# Tailscale + AmneziaWG / QUIC

[English](../README.md) · [فارسی](README-fa.md) · [Русский](README-ru.md) · [下载](https://github.com/LiuTangLei/tailscale/releases/latest)

支持 AWG v2/v3 与 QUIC 混淆的 Tailscale fork，兼容 Tailscale 和 Headscale。默认使用标准 WireGuard，升级保留当前传输模式。从 v1.102.4 开始支持 QUIC 混淆。

## 安装

桌面安装器默认安装最新稳定版，支持 x86_64 / ARM64。

| 平台 | 安装 / 下载 |
| --- | --- |
| Linux | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` |
| macOS | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` |
| Windows（管理员 PowerShell） | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` |
| OpenWrt | [安装器与软件包](https://github.com/LiuTangLei/openwrt-tailscale-awg) |
| Android | [签名 APK](https://github.com/LiuTangLei/tailscale-android/releases/latest) |
| iOS | [AwgScale 预览 IPA](https://github.com/LiuTangLei/AwgScale/releases) |

- macOS 使用 CLI/utun，从 Tailscale.app 迁移需要重新登录。
- Windows GUI 必须匹配 fork 的基础版本。iOS 系统 VPN 需要 TrollStore 或 Packet Tunnel 权限；IPA 非 Apple 分发签名。
- 系统包管理器升级可能覆盖为官方二进制；AWG 命令消失时重新运行安装器。

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
| 恢复标准 WireGuard | `tailscale awg reset` |
| 查看生效模式 / 诊断 | `tailscale awg status` / `tailscale awg doctor` |

- AWG 通信双方必须使用兼容配置，共享字段保持一致。生成一次，保存 JSON 后分发或同步。
- QUIC 按整个节点生效，所有通信节点都需支持，不会自动回退 WG。启用时会清除 AWG，需要恢复时请先保存 JSON。
- 切换会自动重启本机服务，短暂中断 VPN；请保留其他管理连接。

## Docker

使用 [docker-compose.yml](../docker-compose.yml)，镜像为 `ltlei/tailscale-awg:latest` 或 `:v1.104.1`，支持 amd64、arm64、arm/v7、386。

```bash
curl -fsSLO https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/docker-compose.yml
docker compose pull
docker compose up -d
docker compose exec tailscaled tailscale up
docker compose exec tailscaled tailscale version
```

Headscale 在 `tailscale up` 后添加 `--login-server https://你的域名`。无人值守登录通过私有部署环境提供 `TS_AUTHKEY`，不要提交密钥。

v1.104.1：先在容器内暂存传输配置，再重启容器。

```bash
docker compose exec tailscaled tailscale awg set --no-restart --yes quic
docker compose restart tailscaled
```

AWG 将 `--yes quic` 替换为 `'<JSON>'`；旧镜像先升级再使用 `--no-restart`。

- 保留 `containerboot` 和**整个** `./tailscale-state` 目录，不要让多个守护进程共用运行中的节点状态。
- 默认 TUN 模式需要 `/dev/net/tun` 与 `NET_ADMIN`，路由只作用于容器内。出口节点 / 子网路由还需开启转发并在控制端批准。`TS_AUTH_ONCE=true` 时，后续路由变更要显式执行 `tailscale set`。
- 无 TUN、无额外权限时，**单独**使用 [compose.userspace.yml](../compose.userspace.yml)：`docker compose -f compose.userspace.yml up -d`，登录及后续命令同样带 `-f`。应用需使用本机 SOCKS5 `1055` 或 HTTP `1056` 代理；仅共享网络命名空间不会获得路由。

## 排查

检查 `tailscale version`、`tailscale netcheck`、`tailscale awg doctor`、`tailscale ping --tsmp <对端>`。默认 disco ping 成功不代表业务流量正常。反馈 [问题](https://github.com/LiuTangLei/tailscale-awg-installer/issues) 时附上双方版本和诊断结果。

[BSD 3-Clause 许可证](../LICENSE) · [Tailscale](https://github.com/tailscale/tailscale) · [AmneziaWG](https://github.com/amnezia-vpn/amneziawg-go)
