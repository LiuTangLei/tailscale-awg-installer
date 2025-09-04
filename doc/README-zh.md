# Tailscale with Amnezia-WG 1.5

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows%20|%20Android-blue)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](LICENSE)

WireGuard 协议以安全、轻量和高性能著称，但其流量特征极为鲜明，容易被DPI识别。本项目基于 Tailscale，融合 Amnezia-WG 1.5 的混淆，有效隐藏Tailscale的WireGuard 流量特征

**📚 语言:** [English](README.md) | [中文](doc/README-zh.md) | [فارسی](doc/README-fa.md) | [Русский](doc/README-ru.md)

## 🚀 安装

| 平台                        | 命令 / 操作                                                                                                |
| --------------------------- | ---------------------------------------------------------------------------------------------------------- | ----- |
| Linux                       | `curl -fsSL <https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh>   | bash` |
| macOS                       | `curl -fsSL <https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh>   | bash` |
| Windows (管理员 PowerShell) | `iwr -useb <https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1> | iex`  |
| Android                     | 下载 APK: [releases](https://github.com/LiuTangLei/tailscale-android/releases)                             |

Android 版本目前支持从另一个已配置的节点同步（接收）AWG 配置。请使用应用内的同步按钮：

![Android AWG 同步示例](doc/sync1.jpg)

### 镜像 (可选)

如果 GitHub 访问缓慢或被封锁，您可以通过 [gh-proxy](https://github.com/hunshcn/gh-proxy) 自建一个前缀镜像 (例如 `https://your-mirror-site.com`)：

```bash
# Linux
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com

# macOS
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --mirror https://your-mirror-site.com
```

```powershell
# Windows
$scriptContent = (iwr -useb https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content; $scriptBlock = [scriptblock]::Create($scriptContent); & $scriptBlock -MirrorPrefix \'https://your-mirror-site.com/\'
```

PowerShell 策略 (如果被阻止): `Set-ExecutionPolicy RemoteSigned` (或 `Bypass -Scope Process`)

## ⚡ 快速入门

> 提示: `tailscale amnezia-wg` → `tailscale awg` (别名)

1. 登录:

```bash
# 官方
tailscale up
# Headscale
tailscale up --login-server https://your-headscale-domain
```

2. 第一台设备 (生成共享核心值):

```bash
tailscale awg set
```

为 H1–H4 输入 `random` 以自动生成安全的 32 位值。

3. 同步其他设备:
   - 桌面端: `tailscale awg sync`
   - Android: 点击同步按钮 (见上图)
4. 可选的设备级微调: 重新运行 `tailscale awg set` 并只更改非共享字段 (保持 S1/S2/H1–H4 不变)。
5. 常用命令:

```bash
tailscale awg get     # 显示 JSON
tailscale awg reset   # 恢复为原生 WireGuard
```

## 🛡️ 功能

### 垃圾流量 & 签名

添加伪造数据包和协议签名以规避 DPI。与标准 Tailscale 对等节点兼容：

```bash
# 基本垃圾流量
tailscale awg set \'{"jc":4,"jmin":64,"jmax":256}\'

# 带协议签名 (i1-i5)
tailscale awg set \'{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0xc0><r 16>","i2":"<b 0x40><r 12>"}\'
```

### 协议伪装

要求所有节点都使用此分支版本，并具有完全相同的设置 (ix 签名不需要匹配)：

```bash
# 握手混淆 (s1/s2 在所有节点上必须匹配)
tailscale awg set \'{"s1":10,"s2":15}\'

# 带头部字段 (h1-h4 用于协议混淆，在所有节点上必须匹配)
tailscale awg set \'{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777}\'

# 结合签名 (i1-i5 可在每个节点上不同)
tailscale awg set \'{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777,"i1":"<b 0xc0><r 32><c><t>"}\'
```

## 🎯 配置

基础 (可与标准客户端协同工作):

| 类型            | JSON                                                            | 兼容性 |
| --------------- | --------------------------------------------------------------- | ------ |
| 仅垃圾流量      | `{\"jc\":4,\"jmin\":64,\"jmax\":256}`                           | ✅ 是  |
| 垃圾流量 + 签名 | `{\"jc\":2,\"jmin\":64,\"jmax\":128,\"i1\":\"<b 0xc0><r 16>\"}` | ✅ 是  |

高级 (所有节点必须使用此分支并共享 S1/S2/H1–H4):

| 用途     | 示例                                                                                                               | 注意事项            |
| -------- | ------------------------------------------------------------------------------------------------------------------ | ------------------- |
| 握手前缀 | `{\"s1\":10,\"s2\":15}`                                                                                            | s1/s2: 0–64 字节    |
| 头部混淆 | `{\"s1\":10,\"s2\":15,\"h1\":123456,\"h2\":789012,\"h3\":345678,\"h4\":901234}`                                    | 设置所有 h1–h4      |
| 组合     | `{\"jc\":2,\"s1\":10,\"s2\":15,\"h1\":123456,\"h2\":789012,\"h3\":345678,\"h4\":901234,\"i1\":\"<b 0xc0><r 16>\"}` | 垃圾流量/签名为可选 |

参数:

- jc (0–10) 与 jmin/jmax (64–1024): 垃圾数据包数量和大小范围
- i1–i5: 可选的签名链 (十六进制格式的迷你语言)
- s1/s2 (0–64 字节): 握手填充前缀 (在所有 AWG 节点间必须匹配)
- h1–h4 (32 位整数): 头部混淆 (要么全部设置，要么全不设置；必须匹配)。选择随机唯一值 (建议 5–2147483647)

注意: 非常大的垃圾包数量或过长的签名链会增加延迟和带宽消耗。

## 📊 平台支持

| 平台    | 架构                 | 状态                |
| ------- | -------------------- | ------------------- |
| Linux   | x86_64, ARM64        | ✅ 完全支持         |
| macOS   | Intel, Apple Silicon | ✅ 完全支持         |
| Windows | x86_64, ARM64        | ✅ 安装程序         |
| Android | ARM64, ARM           | ✅ APK (仅同步 AWG) |

## 🔄 从官方 Tailscale 迁移

1. 运行安装程序 - 它会自动替换二进制文件，同时保留您的设置
2. 您现有的身份验证和配置将保持不变
3. 从基础混淆开始: `tailscale awg set \'{\"jc\":4,\"jmin\":64,\"jmax\":256}\'`

## ⚠️ 注意事项

- 在应用 AWG 配置之前，其行为与原生版本无异
- 垃圾流量/签名功能可与标准客户端互操作 (每个节点的值可以不同)
- s1/s2 和 h1–h4 要求每个通信节点共享完全相同的值
- 请备份您的配置 (使用 `tailscale awg get`)

## 🛠️ 高级用法

### 头部字段配置 (h1-h4)

协议混淆，用于规避 WireGuard 检测。必须设置全部 4 个值，或者都不设置：

```bash
# 第一个节点：生成随机值 (为每个 h1-h4 输入 \'random\')
tailscale awg set  # 在提示时设置所有 h1, h2, h3, h4

# 获取配置 JSON
tailscale awg get

# 将整个 JSON 复制到其他节点 (必须包含所有 h1-h4)
tailscale awg set \'{\"s1\":10,\"s2\":15,\"h1\":3946285740,\"h2\":1234567890,\"h3\":987654321,\"h4\":555666777}\'
```

### 创建协议签名

1. 使用 Wireshark 捕获真实流量
2. 从头部提取十六进制模式
3. 构建格式: `<b 0xHEX>` (静态), `<r LENGTH>` (随机), `<c>` (计数器), `<t>` (时间戳)
4. 示例: `<b 0xc0000000><r 16><c><t>` = 类似 QUIC 的头部 + 16 字节随机数据 + 计数器 + 时间戳

### 混淆包 I1–I5 (签名链) & CPS (自定义协议签名)

在每次“特殊”握手（每 120 秒）之前，客户端可能会发送最多五个自定义 UDP 包（I1–I5），采用 CPS 格式进行协议模仿。

**CPS 格式:**

```text
i{n} = <tag1><tag2><tag3>...<tagN>
```

**标签类型:**

| 标签 | 格式           | 描述                            | 约束条件      |
| ---- | -------------- | ------------------------------- | ------------- |
| b    | `<b hex_data>` | 用于模拟协议的静态字节          | 任意长度      |
| c    | `<c>`          | 数据包计数器 (32位, 网络字节序) | 每个链中唯一  |
| t    | `<t>`          | Unix 时间戳 (32位, 网络字节序)  | 每个链中唯一  |
| r    | `<r length>`   | 加密安全的随机字节              | length ≤ 1000 |

**示例:**

```text
i1 = <b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>
```

> ⚠️ 如果未设置 i1，则整个链 (I2–I5) 都将被跳过。

#### 使用 Wireshark 捕获真实的混淆包

1. 启动 Amnezia-WG 并配置 i1–i5 参数
2. 使用 Wireshark 监控 UDP 端口 (例如，过滤器: `udp.port == 51820`)
3. 观察并分析混淆包，根据需要提取协议签名

更多详情，请参阅 [Amnezia-WG 官方文档](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted)

## 🐛 问题排查

### 验证安装

```bash
tailscale version          # 检查客户端版本
tailscale awg get          # 验证 Amnezia-WG 支持
```

### 连接问题

```bash
# 重置为标准 WireGuard
tailscale awg reset

# 首先尝试基本设置
tailscale awg set \'{\"jc\":2,\"jmin\":64,\"jmax\":128}\'

# 检查日志 (Linux)
sudo journalctl -u tailscaled -f
```

### Windows PowerShell 问题

使用交互模式以避免 JSON 转义问题：

```powershell
tailscale awg set  # 交互式设置
```

## 🤝 链接与支持

- Releases: [LiuTangLei/tailscale](https://github.com/LiuTangLei/tailscale/releases)
- Android APK: [tailscale-android](https://github.com/LiuTangLei/tailscale-android/releases)
- 安装程序问题: [Issue Tracker](https://github.com/LiuTangLei/tailscale-awg-installer/issues)
- Amnezia-WG 文档: [官方文档](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted)

## 📄 许可证

BSD 3-Clause 许可证 (与上游 Tailscale 相同)

---

**免责声明**: 仅用于教育和合法的隐私保护目的。您有责任遵守当地法律。
