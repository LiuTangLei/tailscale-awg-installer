# Tailscale with Amnezia‑WG 2.0（v1.88.2+）

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20OpenWrt%20|%20Android-blue)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](../LICENSE)

本项目基于 Tailscale，集成 Amnezia-WG 2.0 混淆能力，可通过垃圾流量、协议签名、握手和头部伪装降低 WireGuard 流量被 DPI 识别的概率。不启用 AWG 参数时，行为与标准 Tailscale 一致。

语言： [English](../README.md) | [中文](README-zh.md) | [فارسی](README-fa.md) | [Русский](README-ru.md)

AWG 1.5 旧文档： [README-awg-v1.5.md](README-awg-v1.5.md)

## 安装

| 平台 | 命令 / 操作 |
| --- | --- |
| Linux | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` |
| macOS* | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` |
| Windows | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` |
| OpenWrt | 见下方 [OpenWrt 安装](#openwrt-安装) |
| Android | 从 [releases](https://github.com/LiuTangLei/tailscale-android/releases) 下载 APK |

- macOS：安装器使用 CLI 版 `tailscaled`。若检测到官方 Tailscale.app，会提示移除以避免冲突。
- Android：目前仅支持接收 AWG 配置同步，请使用应用内 Sync 按钮。

![Android 同步示例](sync1.jpg)

## Docker Compose

仓库内置 `docker-compose.yml`，可直接运行带 AWG 支持的 `tailscaled` 容器。

- 状态保存在 compose 文件旁边的 `./tailscale-state` 目录中，容器重启或宿主机重启后，节点状态和 AWG 配置都会保留。
- 若你从旧的 `/var/lib/tailscale:/var/lib/tailscale` bind mount 升级，先复制原有状态文件：

```bash
docker compose down
cp -a /var/lib/tailscale ./tailscale-state
# 更新 docker-compose.yml
docker compose up -d
```

基本流程：

1. 启动服务：`docker compose up -d`
2. 容器内登录：`docker compose exec tailscaled tailscale up`
3. 后续执行 AWG 命令，例如：`docker compose exec tailscaled tailscale awg sync`

如果使用 Headscale，在 `tailscale up` 后追加 `--login-server https://你的域名`。

可选：如果希望像宿主机原生安装一样直接执行 `tailscale ...`，可以添加 alias：

```bash
alias tailscale='docker exec -it tailscaled tailscale'
```

这个 alias 只对当前 shell 生效。若要持久化，请写入 `~/.bashrc` 或 `~/.zshrc`，然后重新加载 shell。

## OpenWrt 安装

英文版安装命令：

```bash
wget -O /usr/bin/install.sh https://raw.githubusercontent.com/LiuTangLei/openwrt-tailscale-awg/main/install_en.sh && chmod +x /usr/bin/install.sh && /usr/bin/install.sh
```

中文用户或 GitHub 受限地区可使用镜像版交互安装：

```bash
wget -O /usr/bin/install.sh https://ghfast.top/https://raw.githubusercontent.com/LiuTangLei/openwrt-tailscale-awg/main/install.sh && chmod +x /usr/bin/install.sh && /usr/bin/install.sh
```

此脚本 fork 自 [GuNanOvO/openwrt-tailscale](https://github.com/GuNanOvO/openwrt-tailscale)。

## 镜像

如果 GitHub 访问缓慢或被屏蔽，可自建前缀镜像，例如 `https://your-mirror-site.com`：

```bash
# Linux
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com

# macOS
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --mirror https://your-mirror-site.com
```

```powershell
# Windows
$scriptContent = (iwr -useb https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content; $scriptBlock = [scriptblock]::Create($scriptContent); & $scriptBlock -MirrorPrefix 'https://your-mirror-site.com/'
```

如果 PowerShell 拒绝执行，可使用 `Set-ExecutionPolicy RemoteSigned` 或 `Bypass -Scope Process`。

## 快速入门

提示：`tailscale amnezia-wg` 与 `tailscale awg` 等价。

1. 登录网络：

```bash
# 官方控制面
tailscale up

# Headscale
tailscale up --login-server https://your-headscale-domain
```

2. 配置 AWG：

```bash
tailscale awg set
```

自动生成提示出现后直接回车，即可生成除 `i1`-`i5` 外的大部分推荐参数。

3. 在其他设备上，从当前这台已配置节点同步相同的 AWG 配置：

- 桌面端：在其他设备上运行 `tailscale awg sync`
- Android：在其他设备上的应用内点击 Sync

4. 查看或重置：

```bash
tailscale awg get
tailscale awg reset
```

## 配置预设

| 目标 | 示例 | 兼容性 |
| --- | --- | --- |
| 基础垃圾流量 | `tailscale awg set '{"jc":4,"jmin":64,"jmax":256}'` | 可与标准 Tailscale 节点通信 |
| 垃圾流量 + 签名 | `tailscale awg set '{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0x40><r 12>"}'` | 可与标准 Tailscale 节点通信 |
| 握手伪装 | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0}'` | 所有 AWG 节点的 `s1`-`s4` 必须一致 |
| 完整伪装 | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000}}'` | 所有 AWG 节点的 `s1`-`s4` 和 `h1`-`h4` 必须一致 |
| 完整伪装 + 签名 | `tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000},"i1":"<b 0xc0><r 32><c><t>"}'` | `i1`-`i5` 可不同，`s1`-`s4` 与 `h1`-`h4` 必须一致 |

## 参数说明

- `jc`、`jmin`、`jmax`：垃圾包数量与长度范围。
- `i1`-`i5`：可选 CPS（Custom Protocol Signature，自定义协议签名）链，用于发送自定义伪装协议包。
- `s1`-`s4`：握手填充或前缀字段，所有 AWG 节点必须一致。
- `h1`-`h4`：头部字段范围，格式为 `{"min": low, "max": high}`。四项要么全部设置，要么全不设置；四个范围不能重叠，且所有 AWG 节点必须一致。

垃圾包数量过大或签名链过长会增加延迟和带宽消耗。

## 平台支持

| 平台 | 架构 | 状态 |
| --- | --- | --- |
| Linux | x86_64, ARM64 | ✅ 完整 |
| macOS | Intel, Apple Silicon | ✅ 完整 |
| Windows | x86_64, ARM64 | ✅ 安装器 |
| OpenWrt | 多种架构 | ✅ 脚本 |
| Android | ARM64, ARM | ✅ APK（仅同步 AWG） |

## 高级：CPS 自定义协议签名

CPS 的全称是 Custom Protocol Signature。它本质上是可自定义的伪装协议包，可用于模拟任意协议头，而不是只对应某一种固定协议。

CPS 链格式：

```text
i{n} = <tag1><tag2>...<tagN>
```

标签类型：

- `<b 0xHEX>`：静态字节
- `<r N>`：安全随机字节
- `<c>`：计数器
- `<t>`：时间戳

示例：

```text
i1 = <b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>
```

若未设置 `i1`，则 `i2`-`i5` 会被跳过。

## 排错

先确认安装和 AWG 支持：

```bash
tailscale version
tailscale awg get
```

若连接异常，可先回退到标准 WireGuard，再从简单预设开始测试：

```bash
tailscale awg reset
tailscale awg set '{"jc":2,"jmin":64,"jmax":128}'
sudo journalctl -u tailscaled -f
```

Windows PowerShell 下建议使用交互模式，避免 JSON 转义问题：

```powershell
tailscale awg set
```

## 链接

- Releases: <https://github.com/LiuTangLei/tailscale/releases>
- Android APK: <https://github.com/LiuTangLei/tailscale-android/releases>
- 安装器问题: <https://github.com/LiuTangLei/tailscale-awg-installer/issues>
- Amnezia-WG 文档: <https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted/#how-to-extract-a-protocol-signature-for-amneziawg-manually>

## 许可证

BSD 3-Clause，与上游 Tailscale 相同。
