# 基于 Amnezia-WG 1.5 的 Tailscale

[![GitHub Release](https://img.shields.io/github/v/release/LiuTangLei/tailscale)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![Platform Support](https://img.shields.io/badge/platform-Linux%20|%20macOS%20|%20Windows-blue)](https://github.com/LiuTangLei/tailscale/releases/latest)
[![License](https://img.shields.io/badge/license-BSD--3--Clause-green)](LICENSE)

基于 **Amnezia-WG 1.5** 协议伪装的 Tailscale，用于 DPI 规避和审查绕过。

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

**高级配置 (需要所有节点都使用此分支):**

| 类型         | 配置                                                                                             | 状态        |
| ------------ | ------------------------------------------------------------------------------------------------ | ----------- |
| **握手混淆** | `{"s1":10,"s2":15,"h1":123456,"h2":789012,"h3":345678,"h4":901234}`                              | ❌ 需要分支 |
| **完整混淆** | `{"jc":2,"s1":10,"s2":15,"h1":123456,"h2":789012,"h3":345678,"h4":901234,"i1":"<b 0xc0><r 16>"}` | ❌ 需要分支 |

> **隐蔽级别**: 使用更多参数类型 (jc/i1-i5/s1-s2/h1-h4) 提供更好的混淆效果，但避免过多垃圾包 (jc) 和签名 (i1-i5) 以防止带宽浪费和延迟问题。

### 参数说明

- **jc**: 垃圾包数量 (0-10，必须同时设置 jmin/jmax)
- **jmin/jmax**: 垃圾包大小范围 (字节) (64-1024，使用 jc 时必需)
- **i1-i5**: 协议签名包用于伪装 (任意十六进制数据)
- **s1/s2**: Init/Response 包的随机前缀 (0-64 字节，需要所有节点匹配值)
- **h1-h4**: 协议混淆 (32 位值，必须设置全部 4 个或都不设，需要所有节点匹配值)

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
tailscale amnezia-wg set  # 提示时设置所有 h1, h2, h3, h4

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
