# Tailscale-Amnezia-WG 一键安装脚本

WireGuard 协议以安全、轻量和高性能著称，但其流量特征极为鲜明，容易被DPI识别。本项目基于 Tailscale，融合 Amnezia-WG 1.5 的混淆，有效隐藏Tailscale的WireGuard 流量特征

**📚 多语言:** [English](../README.md) | [中文](README-zh.md) | [فارسی](README-fa.md) | [Русский](README-ru.md)

## 🚀 安装方式

**Linux：**

```bash
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash
```

**macOS：**

```bash
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash
```

**Windows（以管理员身份运行 PowerShell）：**

```powershell
iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 | iex
```

### 镜像加速（适合国内/被墙环境）

建议自建镜像（如 <https://your-mirror-site.com>），避免公共镜像被封。可用 [gh-proxy](https://github.com/hunshcn/gh-proxy) 快速部署。

```bash
# Linux:
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com
```

```bash
# macOS:
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --mirror https://your-mirror-site.com
```

```powershell
# Windows:
$scriptContent = (iwr -useb https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content;$scriptBlock = [scriptblock]::Create($scriptContent); & $scriptBlock -MirrorPrefix 'https://your-mirror-site.com/'
```

**PowerShell 执行策略问题：**

```powershell
# 如果脚本被拦截：
Set-ExecutionPolicy RemoteSigned
# 或
Set-ExecutionPolicy Bypass -Scope Process
```

## ⚙️ 使用说明

本节介绍如何首次配置和使用 Tailscale + Amnezia-WG。

> **提示：** 所有 `tailscale amnezia-wg` 子命令都可以简写为 `tailscale awg`，如 `tailscale awg set`。

### 1. 登录 Tailscale

安装完成后，先连接到你的 Tailscale 网络：

```bash
# 官方服务
tailscale up

# Headscale 自建服务
tailscale up --login-server https://你的-headscale-域名
```

### 2. 首次初始化（主节点）

在你的第一个节点上，运行交互式配置命令：

```bash
tailscale amnezia-wg set
```

配置过程中，遇到 H1、H2、H3、H4 时可以直接输入 `random`，自动生成安全随机值。

### 3. 其他节点一键同步

主节点配置好后，其他设备只需执行：

```bash
tailscale amnezia-wg sync
```

即可自动同步主节点的 S1/S2/H1-H4 等核心参数。

### 4. 每台设备自定义（可选）

同步后，如需调整每台设备独立参数，可再次运行：

```bash
tailscale amnezia-wg set
```

只需修改你关心的参数，S1/S2/H1-H4 保持一致即可。

### 常用命令

```bash
# 查看当前 Amnezia-WG 配置
tailscale amnezia-wg get

# 恢复为标准 WireGuard 协议
tailscale amnezia-wg reset
```

## 🛡️ Amnezia-WG 特色

### 垃圾流量与协议签名

可插入伪造数据包和协议签名，轻松绕过 DPI，兼容原版 Tailscale：

```bash
# 基础垃圾流量
tailscale amnezia-wg set '{"jc":4,"jmin":64,"jmax":256}'

# 协议签名（i1-i5）
tailscale amnezia-wg set '{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0xc0><r 16>","i2":"<b 0x40><r 12>"}'
```

### 协议伪装

如需协议伪装，所有节点需用本分支且参数一致（ix 签名可不同）：

```bash
# 握手混淆（s1/s2 所有节点需一致）
tailscale amnezia-wg set '{"s1":10,"s2":15}'

# 协议头字段（h1-h4，所有节点需一致）
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777}'

# 结合签名（i1-i5 可不同）
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777,"i1":"<b 0xc0><r 32><c><t>"}'
```

## 🎯 配置参考

**基础配置（兼容原版客户端）：**

| 类型        | 配置                                                  | 兼容性      |
| ----------- | ----------------------------------------------------- | ----------- |
| 仅垃圾包    | `{"jc":4,"jmin":64,"jmax":256}`                       | ✅ 原版兼容 |
| 垃圾包+签名 | `{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0xc0><r 16>"}` | ✅ 原版兼容 |

**进阶配置（所有节点都用本分支时）：**

| 用途           | 示例配置                                                                                         | 说明                |
| -------------- | ------------------------------------------------------------------------------------------------ | ------------------- |
| 握手前缀       | `{"s1":10,"s2":15}`                                                                              | s1/s2: 0–64，需一致 |
| 协议头混淆     | `{"s1":10,"s2":15,"h1":123456,"h2":789012,"h3":345678,"h4":901234}`                              | h1–h4: 32位，需一致 |
| 组合（含签名） | `{"jc":2,"s1":10,"s2":15,"h1":123456,"h2":789012,"h3":345678,"h4":901234,"i1":"<b 0xc0><r 16>"}` | jc/i1-i5 可选       |

> ⚠️ 垃圾包（jc）和超长签名链（i1–i5）会增加延迟和流量消耗，建议适量使用。

### 参数说明

- **jc**：垃圾包数量（0-10，需配合 jmin/jmax）
- **jmin/jmax**：垃圾包字节范围（64-1024，需与 jc 一起用）
- **i1-i5**：协议签名（任意十六进制串）
- **s1/s2**：握手包前缀（0-64 字节，所有节点需一致，仅握手时用）
- **h1-h4**：协议头混淆（32 位整数，4 个全设或全不设，所有节点需一致，建议每个值都不同，推荐范围 5–2147483647）

### 官方参数范围

| 参数       | 范围             | 说明                   |
| ---------- | ---------------- | ---------------------- |
| I1-I5      | 任意十六进制数据 | 协议伪装签名包         |
| S1, S2     | 0-64 字节        | Init/Response 随机前缀 |
| Jc         | 0-10             | I1-I5 后的垃圾包数量   |
| Jmin, Jmax | 64-1024 字节     | 随机垃圾包大小范围     |
| H1-H4      | 0-4294967295     | 协议混淆的 32 位值     |

## 📊 支持平台

| 平台    | 架构                 | 状态               |
| ------- | -------------------- | ------------------ |
| Linux   | x86_64, ARM64        | ✅ 完全支持        |
| macOS   | Intel, Apple Silicon | ✅ 完全支持        |
| Windows | x86_64, ARM64        | ✅ PowerShell 安装 |

## 🔄 迁移自官方 Tailscale

1. 运行安装脚本，自动替换二进制并保留原有配置
2. 认证和设置不变
3. 推荐先用基础混淆：`tailscale amnezia-wg set '{"jc":4,"jmin":64,"jmax":256}'`

## ⚠️ 注意事项

- 默认行为与官方 Tailscale 完全一致，只有启用混淆后才有区别
- 垃圾包（jc）和签名（i1-i5）兼容所有 Tailscale 节点，每个节点可用不同参数
- 协议伪装（s1/s2）和头字段（h1-h4）需所有节点参数一致

## 🛠️ 进阶用法

### 协议头字段（h1-h4）配置

协议混淆可防止被识别为 WireGuard。必须 4 个字段全设或都不设：

```bash
# 第一个节点：生成随机值（每个 h1-h4 输入 random）
tailscale amnezia-wg set  # 按提示设置 h1, h2, h3, h4

# 获取配置 JSON
tailscale amnezia-wg get

# 复制 JSON 到其他节点（必须包含全部 h1-h4）
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777}'
```

### 协议签名生成

1. 用 Wireshark 抓包真实流量
2. 从头部提取 hex 模式
3. 构造格式：`<b 0xHEX>`（静态）、`<r LENGTH>`（随机）、`<c>`（计数器）、`<t>`（时间戳）
4. 示例：`<b 0xc0000000><r 16><c><t>` = 类 QUIC 头 + 16 随机字节 + 计数器 + 时间戳

### 混淆包 I1–I5（签名链）与 CPS（自定义协议签名）

每次“特殊”握手前（约每 120 秒），客户端可发最多 5 个自定义 UDP 包（I1–I5），格式为 CPS，用于协议伪装。

**CPS 格式：**

```text
i{n} = <tag1><tag2><tag3>...<tagN>
```

**标签类型：**

| 标签 | 格式           | 说明                        | 限制      |
| ---- | -------------- | --------------------------- | --------- |
| b    | `<b hex_data>` | 静态字节模拟协议            | 任意长度  |
| c    | `<c>`          | 包计数器（32位，网络序）    | 每链唯一  |
| t    | `<t>`          | Unix 时间戳（32位，网络序） | 每链唯一  |
| r    | `<r length>`   | 加密安全随机字节            | 长度≤1000 |

**示例：**

```text
i1 = <b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>
```

> ⚠️ 未设置 i1 时，I2–I5 整链会被跳过。

#### 用 Wireshark 抓取真实混淆包

1. 启动 Amnezia-WG 并配置 i1–i5
2. 用 Wireshark 监听 UDP 端口（如过滤：`udp.port == 51820`）
3. 观察分析混淆包，按需提取协议签名

更多细节见 [Amnezia-WG 官方文档](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted)

## 🐛 故障排查

### 检查安装

```bash
tailscale version          # 查看客户端版本
tailscale amnezia-wg get   # 检查 Amnezia-WG 支持
```

### 连接问题

```bash
# 恢复标准 WireGuard
tailscale amnezia-wg reset

# 先试基础设置
tailscale amnezia-wg set '{"jc":2,"jmin":64,"jmax":128}'

# 查看日志（Linux）
sudo journalctl -u tailscaled -f
```

### Windows PowerShell 问题

建议用交互模式，避免 JSON 转义：

```powershell
tailscale amnezia-wg set  # 交互式配置
```

## 🤝 相关链接

- **二进制发布**：[LiuTangLei/tailscale](https://github.com/LiuTangLei/tailscale/releases)
- **安装问题反馈**：[GitHub Issues](https://github.com/LiuTangLei/tailscale-awg-installer/issues)
- **Amnezia-WG 文档**：[官方文档](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted)

## 📄 许可证

BSD 3-Clause License（与 Tailscale 相同）

---

**⚠️ 免责声明：仅供学习和合规用途，用户需自行遵守当地法律法规。**

## 🚀 安装

**Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash
```

**macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash
```

**Windows (以管理员身份运行 PowerShell):**

```powershell
iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 | iex
```

## 🚀 安装

**Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash
```

**macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash
```

**Windows (以管理员身份运行 PowerShell):**

```powershell
iwr -useb https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1 | iex
```

### 安装选项

**镜像下载 (如果 GitHub 在您的国家/地区访问缓慢或被阻止):**

建议使用您自己的镜像域名 (例如 <https://your-mirror-site.com>) 以避免公共镜像被阻止。您可以使用 [gh-proxy](https://github.com/hunshcn/gh-proxy) 部署自己的镜像。

```bash
# Linux:
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-linux.sh | bash -s -- --mirror https://your-mirror-site.com
```

```bash
# macOS:
curl -fsSL https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-macos.sh | bash -s -- --mirror https://your-mirror-site.com
```

```powershell
# Windows:
$scriptContent = (iwr -useb https://your-mirror-site.com/https://raw.githubusercontent.com/LiuTangLei/tailscale-awg-installer/main/install-windows.ps1).Content;$scriptBlock = [scriptblock]::Create($scriptContent); & $scriptBlock -MirrorPrefix 'https://your-mirror-site.com/'
```

**PowerShell 执行策略问题:**

```powershell
# 如果脚本执行被阻止:
Set-ExecutionPolicy RemoteSigned
# 或
Set-ExecutionPolicy Bypass -Scope Process
```

## ⚡ 快速开始

1. **安装** 使用上面的命令
2. **登录** Tailscale:

```bash
# 官方控制平面
tailscale up

# Headscale 用户
tailscale up --login-server https://your-headscale-domain
```

3. **启用混淆** (需要时):

```bash
# 基础 DPI 规避 (兼容任何对等节点)
tailscale amnezia-wg set '{"jc":4,"jmin":64,"jmax":256}'

# 查看当前设置
tailscale amnezia-wg get

# 交互式设置
tailscale amnezia-wg set

# 重置为标准 WireGuard
tailscale amnezia-wg reset
```

## 🛡️ Amnezia-WG 功能

### 垃圾流量和签名

添加虚假数据包和协议签名来规避 DPI。兼容标准 Tailscale 节点:

```bash
# 基础垃圾流量
tailscale amnezia-wg set '{"jc":4,"jmin":64,"jmax":256}'

# 带协议签名 (i1-i5)
tailscale amnezia-wg set '{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0xc0><r 16>","i2":"<b 0x40><r 12>"}'
```

### 协议伪装

需要所有节点都使用此分支版本并使用相同设置 (ix 签名不需要匹配):

```bash
# 握手混淆 (s1/s2 必须在所有节点上匹配)
tailscale amnezia-wg set '{"s1":10,"s2":15}'

# 带头部字段 (h1-h4 用于协议混淆，必须在所有节点上匹配)
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777}'

# 结合签名 (i1-i5 每个节点可以不同)
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777,"i1":"<b 0xc0><r 32><c><t>"}'
```

## 🎯 配置指南

**基础配置 (兼容官方客户端):**

| 类型            | 配置                                                  | 状态        |
| --------------- | ----------------------------------------------------- | ----------- |
| **仅垃圾包**    | `{"jc":4,"jmin":64,"jmax":256}`                       | ✅ 兼容官方 |
| **垃圾包+签名** | `{"jc":2,"jmin":64,"jmax":128,"i1":"<b 0xc0><r 16>"}` | ✅ 兼容官方 |

**进阶配置（仅适用于所有节点都用本分支时）:**

| 用途                | 最简示例                                                                                         | 说明                |
| ------------------- | ------------------------------------------------------------------------------------------------ | ------------------- |
| 握手前缀            | `{"s1":10,"s2":15}`                                                                              | s1/s2: 0–64，需一致 |
| 协议头混淆          | `{"s1":10,"s2":15,"h1":123456,"h2":789012,"h3":345678,"h4":901234}`                              | h1–h4: 32位，需一致 |
| 组合（含垃圾/签名） | `{"jc":2,"s1":10,"s2":15,"h1":123456,"h2":789012,"h3":345678,"h4":901234,"i1":"<b 0xc0><r 16>"}` | jc/i1-i5 可选       |

> 注意：垃圾包（jc）和超长签名链（i1–i5）会增加延迟和流量消耗，建议适量使用。

### 参数说明

- **jc**：垃圾包数量（0-10，需配合 jmin/jmax）
- **jmin/jmax**：垃圾包字节范围（64-1024，和 jc 一起用）
- **i1-i5**：协议签名（任意十六进制串）
- **s1/s2**：握手包前缀（0-64 字节，所有节点需一致，仅握手时用，不影响持续流量）
- **h1-h4**：协议头混淆（32 位整数，4 个全设或全不设，所有节点需一致，建议每个值都不同，推荐范围 5–2147483647，仅改变标识，不增加包）

### 官方参数范围

| 参数           | 范围             | 描述                       |
| -------------- | ---------------- | -------------------------- |
| **I1-I5**      | 任意十六进制数据 | 协议伪装的签名包           |
| **S1, S2**     | 0-64 字节        | Init/Response 包的随机前缀 |
| **Jc**         | 0-10             | I1-I5 后面的垃圾包数量     |
| **Jmin, Jmax** | 64-1024 字节     | 随机垃圾包的大小范围       |
| **H1-H4**      | 0-4294967295     | 协议混淆的 32 位值         |

## 📊 平台支持

| 平台        | 架构                 | 状态               |
| ----------- | -------------------- | ------------------ |
| **Linux**   | x86_64, ARM64        | ✅ 完全支持        |
| **macOS**   | Intel, Apple Silicon | ✅ 完全支持        |
| **Windows** | x86_64, ARM64        | ✅ PowerShell 安装 |

## 🔄 从官方 Tailscale 迁移

1. 运行安装程序 - 自动替换二进制文件同时保留您的设置
2. 您现有的身份验证和配置保持不变
3. 开始使用基础混淆: `tailscale amnezia-wg set '{"jc":4,"jmin":64,"jmax":256}'`

## ⚠️ 重要说明

- **默认行为**: 在启用混淆之前，工作方式与官方 Tailscale 完全相同
- **垃圾包 (jc) 和签名 (i1-i5)**: 兼容任何 Tailscale 节点，包括标准客户端。每个节点可以使用不同的值
- **协议伪装 (s1/s2) 和头部字段 (h1-h4)**: 需要所有节点都使用此分支版本并使用相同值
- **性能**: 基础设置下开销极小

## 🛠️ 高级用法

### 头部字段配置 (h1-h4)

协议混淆以规避 WireGuard 检测。必须设置全部 4 个值或都不设:

```bash
# 第一个节点: 生成随机值 (每个 h1-h4 输入 'random')
tailscale amnezia-wg set  # 按提示设置所有 h1, h2, h3, h4

# 获取配置 JSON
tailscale amnezia-wg get

# 将完整的 JSON 复制到其他节点 (必须包含所有 h1-h4)
tailscale amnezia-wg set '{"s1":10,"s2":15,"h1":3946285740,"h2":1234567890,"h3":987654321,"h4":555666777}'
```

### 创建协议签名

1. 使用 Wireshark 捕获真实流量
2. 从头部提取十六进制模式
3. 构建格式: `<b 0xHEX>` (静态), `<r LENGTH>` (随机), `<c>` (计数器), `<t>` (时间戳)
4. 示例: `<b 0xc0000000><r 16><c><t>` = 类 QUIC 头部 + 16 随机字节 + 计数器 + 时间戳

### 混淆包 I1–I5 (签名链) 和 CPS (自定义协议签名)

每次"特殊"握手之前 (每 120 秒)，客户端可以发送最多五个自定义 UDP 包 (I1–I5)，采用 CPS 格式进行协议伪装。

**CPS 格式:**

```text
i{n} = <tag1><tag2><tag3>...<tagN>
```

**标签类型:**

| 标签 | 格式           | 描述                           | 约束          |
| ---- | -------------- | ------------------------------ | ------------- |
| b    | `<b hex_data>` | 静态字节用于协议模拟           | 任意长度      |
| c    | `<c>`          | 包计数器 (32位，网络字节序)    | 每链唯一      |
| t    | `<t>`          | Unix 时间戳 (32位，网络字节序) | 每链唯一      |
| r    | `<r length>`   | 加密安全的随机字节             | length ≤ 1000 |

**示例:**

```text
i1 = <b 0xf6ab3267fa><c><b 0xf6ab><t><r 10>
```

> ⚠️ 如果未设置 i1，整个链 (I2–I5) 将被跳过。

#### 使用 Wireshark 捕获真实混淆包

1. 启动 Amnezia-WG 并配置 i1–i5 参数
2. 使用 Wireshark 监控 UDP 端口 (例如，过滤器: `udp.port == 51820`)
3. 观察和分析混淆包，根据需要提取协议签名

更多详情，请参阅 [Amnezia-WG 官方文档](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted)

## 🐛 故障排除

### 验证安装

```bash
tailscale version          # 检查客户端版本
tailscale amnezia-wg get   # 验证 Amnezia-WG 支持
```

### 连接问题

```bash
# 重置为标准 WireGuard
tailscale amnezia-wg reset

# 首先尝试基础设置
tailscale amnezia-wg set '{"jc":2,"jmin":64,"jmax":128}'

# 检查日志 (Linux)
sudo journalctl -u tailscaled -f
```

### Windows PowerShell 问题

使用交互模式避免 JSON 转义问题:

```powershell
tailscale amnezia-wg set  # 交互式设置
```

## 🤝 链接和支持

- **二进制发布**: [LiuTangLei/tailscale](https://github.com/LiuTangLei/tailscale/releases)
- **安装程序问题**: [GitHub Issues](https://github.com/LiuTangLei/tailscale-awg-installer/issues)
- **Amnezia-WG 文档**: [官方文档](https://docs.amnezia.org/documentation/instructions/new-amneziawg-selfhosted)

## 📄 许可证

BSD 3-Clause 许可证 (与 Tailscale 相同)

---

**⚠️ 免责声明**: 仅用于教育和合法隐私目的。用户有责任遵守适用法律。
