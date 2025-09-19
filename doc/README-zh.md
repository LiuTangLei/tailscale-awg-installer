# Tailscale with Amnezia‑WG 2.0（v1.88.2+）

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20Android-blue)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](../LICENSE)

WireGuard 协议以安全、轻量和高性能著称，但其流量特征极为鲜明，容易被DPI识别。本项目基于 Tailscale，融合 Amnezia-WG 2.0 的混淆，有效隐藏Tailscale的WireGuard 流量特征

语言： [English](../README.md) | [中文](README-zh.md) | [فارسی](README-fa.md) | [Русский](README-ru.md)

AWG 1.5 旧文档： [README-awg-v1.5.md](README-awg-v1.5.md)

## 破坏性变更（v1.88.2+）

- h1–h4 从"固定值"改为"范围（闭区间）"，四个范围不得重叠
- 新增 s3、s4（在 s1、s2 基础上）
- 交互式自动生成：`tailscale awg set` 提示 "Do you want to generate random AWG parameters automatically? [Y/n]:" 时按回车，可自动生成除 i1–i5 外所有参数

1.x 配置与 2.0 不兼容，请参考"从 1.x 迁移"。

## 安装

| 平台    | 命令 / 操作 |
| ------- | ----------- |
| Linux   | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh \| bash` |
| macOS*  | `curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh \| bash` |
| Windows | `iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 \| iex` |
| Android | 从 [releases](https://github.com/LiuTangLei/tailscale-android/releases) 下载 APK |

macOS：脚本使用 CLI 版 tailscaled，如检测到官方 Tailscale.app，将提示移除以避免冲突。

Android 支持从其它已配置节点"接收"AWG 配置（应用内点 Sync）。

![Android 同步示例](sync1.jpg)

## 镜像（可选）

如果 GitHub 访问缓慢或被屏蔽，可通过 gh-proxy 自建前缀镜像（如 `https://your-mirror-site.com`）：

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

PowerShell 执行策略（如被阻止）：`Set-ExecutionPolicy RemoteSigned`（或 `Bypass -Scope Process`）

## macOS 安装说明

- 仅 CLI 部署：使用开源 `tailscaled`（utun 接口）以完全兼容自定义构建
- 应用冲突处理：自动检测并提供移除官方 Tailscale.app 以防止系统扩展冲突

## 快速入门

提示：`tailscale amnezia-wg` 等于 `tailscale awg`

1. 登录

```bash
# 官方
tailscale up
# Headscale
tailscale up --login-server https://your-headscale-domain
```

1. 交互设置（推荐自动生成）

```bash
tailscale awg set
```

出现自动生成提示时直接回车，除 i1–i5 外均会生成随机安全值。

1. 同步到其它设备

- 桌面端：`tailscale awg sync`
- Android：应用内 Sync 按钮

1. 按需微调：再次运行 `tailscale awg set`，若不需要协议签名，可不设置 i1–i5。

1. 常用命令

```bash
tailscale awg get
tailscale awg reset
```

## 功能与示例

- 垃圾流量与签名（与标准节点可互通）

```bash
# 基础垃圾流量
tailscale awg set '{"jc":4,"jmin":64,"jmax":256}'
# 协议签名（i1–i5 可选）
tailscale awg set '{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0x40><r 12>"}'
```

- 协议伪装（所有节点需使用本分支；s1–s4 与 h1–h4 必须一致，i1–i5 无需一致）

```bash
# 握手混淆
tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0}'
# 头部范围（不重叠）
tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000}}'
# 混合（含签名）
tailscale awg set '{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000},"i1":"<b 0xc0><r 32><c><t>"}'
```

## 配置参考

- 基础（与标准客户端互通）

| 用途        | JSON                                                  | 兼容 |
| ----------- | ----------------------------------------------------- | ---- |
| 仅垃圾流量  | `{"jc":4,"jmin":64,"jmax":256}`                       | ✅   |
| 垃圾+签名   | `{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0xc0><r 16>"}` | ✅   |

- 高级（所有节点共享 s1–s4 与 h1–h4）

| 用途     | 示例                                                                                                                                     | 说明                                   |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| 握手前缀 | `{"s1":10,"s2":15,"s3":8,"s4":0}`                                                                                                         | s1–s4 在所有节点必须一致               |
| 头部范围 | `{"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000}}`             | h1–h4 为范围且不得重叠，且必须一致     |
| 组合     | `{"jc":2,"s1":10,"s2":15,"s3":8,"s4":0,"h1":{"min":100000,"max":200000},"h2":{"min":300000,"max":350000},"h3":{"min":400000,"max":450000},"h4":{"min":500000,"max":550000},"i1":"<b 0xc0><r 16>"}` | 垃圾/签名可选                           |

参数说明：

- jc（0–10）与 jmin/jmax（64–1024）：垃圾包数量与大小范围
- i1–i5：可选协议签名链（十六进制迷你语言）
- s1–s4：握手前缀/填充字段（所有 AWG 节点间必须一致）
- h1–h4：头部字段范围，每项 {"min": low, "max": high}（闭区间），四个范围不得重叠；要么全部设置，要么全不设置；必须一致

## 平台支持

| 平台    | 架构                 | 状态                |
| ------- | -------------------- | ------------------- |
| Linux   | x86_64, ARM64        | ✅ 完整             |
| macOS   | Intel, Apple Silicon | ✅ 完整             |
| Windows | x86_64, ARM64        | ✅ 安装器           |
| Android | ARM64, ARM           | ✅ APK（仅同步 AWG） |

## 从 1.x 迁移

1. 所有节点升级至 v1.88.2+（本仓库构建）
1. 可选：清空旧 1.x 配置

```bash
tailscale awg reset
```

1. 在每台设备运行 `tailscale awg set` 并按回车自动生成参数（除 i1–i5）
1. 用 `tailscale awg get` 分发或用 `tailscale awg sync` 同步
1. 启用伪装的节点之间 s1–s4 与 h1–h4 必须一致，且 h1–h4 不重叠

注意：1.x 与 2.0 之间协议伪装不互通。

## 高级：创建协议签名（i1–i5）

1. 用 Wireshark 抓包
1. 从头部提取十六进制模式
1. 组合：`<b 0xHEX>`（静态）、`<r N>`（随机 N 字节）、`<c>`（计数器）、`<t>`（时间戳）
1. 例：`<b 0xc0><r 16><c><t>`

CPS 链格式：

```text
i{n} = <tag1><tag2>...<tagN>
```

若 i1 未设置，则 I2–I5 会被跳过。

## 排错

```bash
tailscale version
tailscale awg get
```

连接问题：

```bash
tailscale awg reset
sudo journalctl -u tailscaled -f
```

PowerShell 建议使用交互模式：

```powershell
tailscale awg set
```

## 链接

- Releases: <https://github.com/LiuTangLei/tailscale/releases>
- Android APK: <https://github.com/LiuTangLei/tailscale-android/releases>
- 安装器问题: <https://github.com/LiuTangLei/tailscale-awg-installer/issues>
- Amnezia‑WG 文档: <https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted>

## 许可证

BSD 3‑Clause（与上游相同）
