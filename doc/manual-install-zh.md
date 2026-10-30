# 手动安装

[English](manual-install.md) · [返回 README](README-zh.md)

一键安装器无法运行时（例如离线机器、自定义系统布局）使用本教程。安装器会自动完成同样的步骤，并在失败时回滚，能用安装器时优先用安装器。

手动安装只替换 `tailscale` 和 `tailscaled` 两个二进制文件。只要状态目录不变，登录状态和节点配置都会保留。

## 准备

每个 [Release](https://github.com/LiuTangLei/tailscale/releases/latest) 都提供 x86_64（`amd64`）和 ARM64（`arm64`）的独立二进制：

| 系统 | 文件 |
| --- | --- |
| Linux | `tailscale-linux-<arch>`、`tailscaled-linux-<arch>` |
| macOS | `tailscale-darwin-<arch>`、`tailscaled-darwin-<arch>` |
| Windows | `tailscale-windows-<arch>.exe`、`tailscaled-windows-<arch>.exe` |
| 全部 | `SHA256SUMS`（所有文件的校验值） |

- 版本号与上游一致：fork `vX.Y.Z` 基于 Tailscale `vX.Y.Z`。
- 以 `releases/latest/download/<文件>` 结尾的链接始终指向最新版。需要固定版本时改用 `releases/download/vX.Y.Z/<文件>`。
- GitHub 慢或无法访问时，在每个 GitHub 链接前加镜像前缀，例如 `https://ghfast.top/https://github.com/...`，详见 [GitHub 镜像](README-zh.md#github-镜像)。
- 安装前务必用 `SHA256SUMS` 校验二进制。
- 其他 Linux 架构（armv7、mips、riscv64 等）请用 [OpenWrt 软件包](#openwrt) 或 [Docker 镜像](README-zh.md#docker)。

## Linux

以下命令以 root 或可用 `sudo` 的用户执行。所有步骤请在同一个终端里完成，后面的步骤会用到前面设置的变量。

### 1. 下载并校验

```bash
case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "不支持的架构: $(uname -m)" ;;
esac
BASE=https://github.com/LiuTangLei/tailscale/releases/latest/download
# 使用镜像：
# BASE=https://ghfast.top/https://github.com/LiuTangLei/tailscale/releases/latest/download

mkdir -p ~/tailscale-awg && cd ~/tailscale-awg
curl -fL -O "$BASE/tailscale-linux-$ARCH" -O "$BASE/tailscaled-linux-$ARCH" -O "$BASE/SHA256SUMS"
grep -E " tailscaled?-linux-$ARCH\$" SHA256SUMS | sha256sum -c -
chmod +x "tailscale-linux-$ARCH" "tailscaled-linux-$ARCH"
./"tailscale-linux-$ARCH" version
```

两行都必须显示 `OK`。没有 `curl` 时，用 `wget` 逐个下载。

然后从下面三种方式中**任选一种**。

### 2a. 替换官方软件包（推荐）

保留官方软件包的服务文件和路径。也可用于升级任何已有的 systemd 安装，包括一键安装器或 2b 方式装的。尚未安装 Tailscale 时，先安装官方版本：

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

找到实际在用的二进制，备份后替换：

```bash
TS=$(readlink -f "$(command -v tailscale)")
TSD=$(systemctl show -p ExecStart tailscaled | sed -n 's/.*path=\([^ ;]*\).*/\1/p')
TSD=$(readlink -f "$TSD")
echo "client: $TS  daemon: $TSD"   # 通常是 /usr/bin/tailscale 和 /usr/sbin/tailscaled

sudo systemctl stop tailscaled
sudo cp -p "$TS" "$TS.official" && sudo cp -p "$TSD" "$TSD.official"
sudo install -m 755 "tailscale-linux-$ARCH" "$TS"
sudo install -m 755 "tailscaled-linux-$ARCH" "$TSD"
sudo systemctl start tailscaled
```

系统更新软件包时会装回官方二进制。可以每次更新后重做本节，或者锁定软件包：

| 发行版 | 锁定 | 解除锁定 |
| --- | --- | --- |
| Debian / Ubuntu | `sudo apt-mark hold tailscale` | `sudo apt-mark unhold tailscale` |
| Fedora / RHEL | `sudo dnf versionlock add tailscale`（需要 versionlock 插件） | `sudo dnf versionlock delete tailscale` |
| Arch Linux | 在 `/etc/pacman.conf` 中添加 `IgnorePkg = tailscale` | 删除这一行 |

### 2b. 独立安装（systemd）

不想安装官方软件包时使用。

```bash
sudo install -m 755 "tailscale-linux-$ARCH" /usr/local/bin/tailscale
sudo install -m 755 "tailscaled-linux-$ARCH" /usr/local/bin/tailscaled
sudo mkdir -p /var/lib/tailscale && sudo chmod 700 /var/lib/tailscale

sudo tee /etc/systemd/system/tailscaled.service >/dev/null <<'EOF'
[Unit]
Description=Tailscale node agent
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=41641
ExecStopPost=/usr/local/bin/tailscaled --cleanup
Restart=on-failure
RuntimeDirectory=tailscale
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SYS_MODULE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW CAP_SYS_MODULE
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now tailscaled
```

如果已经装了官方软件包，请改用 2a，或先卸载软件包，避免两个服务冲突。

### 2c. 独立安装（OpenRC，适用于 Alpine 等）

```bash
sudo install -m 755 "tailscale-linux-$ARCH" /usr/local/bin/tailscale
sudo install -m 755 "tailscaled-linux-$ARCH" /usr/local/bin/tailscaled
sudo mkdir -p /var/lib/tailscale && sudo chmod 700 /var/lib/tailscale

sudo tee /etc/init.d/tailscaled >/dev/null <<'EOF'
#!/sbin/openrc-run
name="tailscaled"
description="Tailscale node agent"
command="/usr/local/bin/tailscaled"
command_args="--state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock --port=41641"
command_background=true
pidfile="/run/tailscaled.pid"
start_stop_daemon_args="-1 /var/log/tailscaled.log -2 /var/log/tailscaled.log"

depend() {
    need net
}

start_pre() {
    mkdir -p /var/lib/tailscale /var/run/tailscale
    ${command} --cleanup || true
}

stop_post() {
    ${command} --cleanup || true
}
EOF

sudo chmod 755 /etc/init.d/tailscaled
sudo rc-update add tailscaled default
sudo rc-service tailscaled start
```

Alpine 未安装 `sudo` 时，直接以 root 执行并去掉 `sudo`。TUN 模式需要 `tun` 内核模块（`modprobe tun`）。

### 3. 登录并检查

```bash
sudo tailscale up            # Headscale 加 --login-server https://你的域名
tailscale version
tailscale awg status
```

如果 `tailscale awg status` 提示未知命令，说明仍在使用官方二进制，请检查 `command -v tailscale` 和服务 `ExecStart` 中的路径。

### 升级、回滚、卸载

- **升级**：重做第 1 步，再执行所选方式的替换命令（停止服务、`install` 两个文件、启动服务）。
- **回滚到官方版（2a）**：`sudo systemctl stop tailscaled`，把 `.official` 备份移回原处，再启动服务。也可以重装软件包，例如 `sudo apt install --reinstall tailscale`。
- **卸载（2b）**：`sudo systemctl disable --now tailscaled`，然后删除 `/etc/systemd/system/tailscaled.service`、`/usr/local/bin/tailscale` 和 `/usr/local/bin/tailscaled`。
- **卸载（2c）**：`sudo rc-service tailscaled stop && sudo rc-update del tailscaled default`，然后删除 `/etc/init.d/tailscaled`、`/usr/local/bin/tailscale` 和 `/usr/local/bin/tailscaled`。
- 删除 `/var/lib/tailscale` 会同时清除登录状态和已保存的 AWG 配置。

## macOS

fork 以命令行守护进程（utun）方式运行，不是 Tailscale.app。两者不能同时运行，从 App 迁移需要重新登录。

### 1. 移除冲突的安装

- **Tailscale.app**：从菜单栏退出，然后把它从 `/Applications` 移到废纸篓。
- **Homebrew**：`brew services stop tailscale && brew uninstall tailscale`
- **之前装过 fork**（安装器或手动）：无需移除，第 3 步会找到并替换。

### 2. 下载并校验

```bash
case "$(uname -m)" in x86_64) ARCH=amd64 ;; arm64) ARCH=arm64 ;; esac
BASE=https://github.com/LiuTangLei/tailscale/releases/latest/download
# 使用镜像：
# BASE=https://ghfast.top/https://github.com/LiuTangLei/tailscale/releases/latest/download

mkdir -p ~/tailscale-awg && cd ~/tailscale-awg
curl -fL -O "$BASE/tailscale-darwin-$ARCH" -O "$BASE/tailscaled-darwin-$ARCH" -O "$BASE/SHA256SUMS"
grep -E " tailscaled?-darwin-$ARCH\$" SHA256SUMS | shasum -a 256 -c -
chmod +x "tailscale-darwin-$ARCH" "tailscaled-darwin-$ARCH"
```

两行都必须显示 `OK`。如果是用浏览器下载的，还需清除隔离标记：`xattr -d com.apple.quarantine tailscale*-darwin-*`。二进制为 ad-hoc 签名。

### 3. 安装二进制

已有服务时沿用原来的目录（很多 Apple Silicon Mac 上安装器使用 `/opt/homebrew/bin`），全新安装使用 `/usr/local/bin`。

```bash
PLIST=/Library/LaunchDaemons/com.tailscale.tailscaled.plist
if [ -f "$PLIST" ]; then
  DIR=$(dirname "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$PLIST")")
else
  DIR=/usr/local/bin
fi
echo "Installing to $DIR"

sudo mkdir -p "$DIR" /var/lib/tailscale
sudo install -m 755 "tailscale-darwin-$ARCH" "$DIR/tailscale"
sudo install -m 755 "tailscaled-darwin-$ARCH" "$DIR/tailscaled"
```

如果服务原本就存在，用 `sudo launchctl kickstart -k system/com.tailscale.tailscaled` 重启后直接跳到第 5 步。

### 4. 创建并启动系统服务

```bash
sudo tee "$PLIST" >/dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.tailscale.tailscaled</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DIR/tailscaled</string>
        <string>--state=/var/lib/tailscale/tailscaled.state</string>
        <string>--socket=/var/run/tailscaled.socket</string>
        <string>--port=41641</string>
        <string>--tun=utun</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/tailscaled.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/tailscaled.log</string>
</dict>
</plist>
EOF

sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"
sudo launchctl bootstrap system "$PLIST"
```

如果 `PATH` 里没有 `/usr/local/bin`，请把它加入 shell 配置文件。

### 5. 登录并检查

```bash
sudo tailscale up            # Headscale 加 --login-server https://你的域名
tailscale version
tailscale awg status
```

### 升级与卸载

- **升级**：重做第 2、3 步，然后执行 `sudo launchctl kickstart -k system/com.tailscale.tailscaled`。
- **卸载**：

  ```bash
  PLIST=/Library/LaunchDaemons/com.tailscale.tailscaled.plist
  DIR=$(dirname "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$PLIST")")
  sudo launchctl bootout system/com.tailscale.tailscaled
  sudo rm -f "$PLIST" "$DIR/tailscale" "$DIR/tailscaled"
  ```

  如需清除登录状态和 AWG 配置，再删除 `/var/lib/tailscale`。日志位于 `/var/log/tailscaled.log`。

## Windows

所有命令都在**以管理员身份运行的 PowerShell** 中执行。需要托盘图形界面选方式 A，只要后台服务选方式 B。

### 1. 下载并校验

```powershell
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tag  = (Invoke-RestMethod https://api.github.com/repos/LiuTangLei/tailscale/releases/latest).tag_name
# 无法访问 api.github.com 时，按 Release 页面手动填写版本，例如：
# $tag = 'v1.104.4'
$ver  = $tag.TrimStart('v')
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$base = "https://github.com/LiuTangLei/tailscale/releases/download/$tag"
# 使用镜像：
# $base = "https://ghfast.top/https://github.com/LiuTangLei/tailscale/releases/download/$tag"

$dir = "$env:TEMP\tailscale-awg"
New-Item -ItemType Directory -Force $dir | Out-Null
$files = "tailscale-windows-$arch.exe", "tailscaled-windows-$arch.exe"
foreach ($f in $files + 'SHA256SUMS') { Invoke-WebRequest -UseBasicParsing "$base/$f" -OutFile "$dir\$f" }

$sums = Get-Content "$dir\SHA256SUMS"
foreach ($f in $files) {
  $want = (($sums | Where-Object { $_ -match "  $([regex]::Escape($f))$" }) -split '\s+')[0]
  $got  = (Get-FileHash "$dir\$f" -Algorithm SHA256).Hash.ToLower()
  if ($got -ne $want) { throw "Checksum mismatch: $f" }
}
Unblock-File "$dir\*.exe"
"Verified $tag ($arch)"
```

### 2A. 搭配官方图形界面（推荐）

托盘程序必须与 fork **版本相同**。先安装同版本的官方 MSI；如果已经装了这个版本，可以跳过：

```powershell
$msi = "$dir\tailscale-setup-$ver-$arch.msi"
Invoke-WebRequest -UseBasicParsing "https://pkgs.tailscale.com/stable/tailscale-setup-$ver-$arch.msi" -OutFile $msi
Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait
```

然后替换两个二进制：

```powershell
$dst = "$env:ProgramFiles\Tailscale"
Stop-Service Tailscale
Get-Process tailscale-ipn -ErrorAction SilentlyContinue | Stop-Process -Force
Copy-Item "$dst\tailscale.exe"  "$dst\tailscale.exe.official"  -Force
Copy-Item "$dst\tailscaled.exe" "$dst\tailscaled.exe.official" -Force
Copy-Item "$dir\tailscale-windows-$arch.exe"  "$dst\tailscale.exe"  -Force
Copy-Item "$dir\tailscaled-windows-$arch.exe" "$dst\tailscaled.exe" -Force
Start-Service Tailscale
Start-Process "$dst\tailscale-ipn.exe"
& "$dst\tailscale.exe" set --auto-update=false
```

关闭自动更新，避免官方程序把 fork 覆盖回去。通过托盘图标或 `tailscale up` 登录。

### 2B. 仅后台服务（无图形界面）

`tailscaled.exe` 需要同目录下的 `wintun.dll`。官方 MSI 自带该文件，这里从 wintun.net 下载：

```powershell
$dst = "$env:ProgramFiles\Tailscale"
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item "$dir\tailscale-windows-$arch.exe"  "$dst\tailscale.exe"  -Force
Copy-Item "$dir\tailscaled-windows-$arch.exe" "$dst\tailscaled.exe" -Force

Invoke-WebRequest -UseBasicParsing https://www.wintun.net/builds/wintun-0.14.1.zip -OutFile "$dir\wintun.zip"
if ((Get-FileHash "$dir\wintun.zip" -Algorithm SHA256).Hash -ne '07C256185D6EE3652E09FA55C0B673E2624B565E02C4B9091C79CA7D2F24EF51') { throw 'wintun checksum mismatch' }
Expand-Archive "$dir\wintun.zip" "$dir\wintun" -Force
Copy-Item "$dir\wintun\wintun\bin\$arch\wintun.dll" $dst -Force

& "$dst\tailscaled.exe" install-system-daemon
$path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($path -notlike "*$dst*") { [Environment]::SetEnvironmentVariable('Path', "$path;$dst", 'Machine') }
```

`install-system-daemon` 会创建并启动 `Tailscale` 服务。重新打开终端使新的 `Path` 生效，然后执行 `tailscale up`。

### 3. 检查

```powershell
tailscale version
tailscale awg status
```

### 升级、回滚、卸载

- **升级（A）**：重做第 1 步；如果基础版本变了，先安装对应版本的 MSI，再执行替换命令。
- **升级（B）**：重做第 1 步，`Stop-Service Tailscale`，重新复制两个 `.exe`，`Start-Service Tailscale`。
- **回滚到官方版（A）**：停止服务，把 `.official` 文件复制回 `tailscale.exe` 和 `tailscaled.exe`，再启动服务。也可以重装官方 MSI。
- **卸载（A）**：在 *设置 → 应用* 中卸载 Tailscale。
- **卸载（B）**：`& "$env:ProgramFiles\Tailscale\tailscaled.exe" uninstall-system-daemon`，然后删除 `C:\Program Files\Tailscale`，并从系统 `Path` 中移除该目录。
- 状态和日志位于 `C:\ProgramData\Tailscale`，删除后会清除登录状态和 AWG 配置。

## OpenWrt

最简单的方式是 [OpenWrt 安装器](https://github.com/LiuTangLei/openwrt-tailscale-awg)。手动安装软件包：

1. 查看软件包架构：`opkg print-architecture`（OpenWrt 24.10）或 `apk --print-arch`（OpenWrt 25.12）。
2. 从 [OpenWrt Releases](https://github.com/LiuTangLei/openwrt-tailscale-awg/releases/latest) 下载对应的 `.ipk` 或 `.apk`，复制到路由器的 `/tmp`。
3. 安装：
   - OpenWrt 24.10：`opkg install /tmp/tailscale_*.ipk`
   - OpenWrt 25.12：`apk add --allow-untrusted /tmp/tailscale_*.apk`
4. 启动：`/etc/init.d/tailscale enable && /etc/init.d/tailscale start`，然后执行 `tailscale up`。

也可以添加已签名的 [软件源](https://github.com/LiuTangLei/openwrt-tailscale-awg/tree/feed)，通过 `opkg` / `apk` 获取更新。配置文件位于 `/etc/config/tailscale`。

## Android 与 iOS

- **Android**：从 [Android Releases](https://github.com/LiuTangLei/tailscale-android/releases/latest) 下载 APK 并在设备上打开安装。如果装了 Google Play 的官方 Tailscale，需要先卸载，因为签名不同。之后的 fork 更新可直接覆盖安装并保留数据。
- **iOS**：用 TrollStore 安装 [AwgScale Releases](https://github.com/LiuTangLei/AwgScale/releases) 中的 IPA。系统 VPN 需要 TrollStore 或 Packet Tunnel 权限。

## 排查

| 问题 | 检查 |
| --- | --- |
| `tailscale awg` 提示未知命令 | 仍在使用官方二进制。Linux / macOS：`which -a tailscale tailscaled` 及服务启动命令；Windows：`Get-Command tailscale`。 |
| 校验值不一致 | 重新下载。镜像可能返回旧文件或损坏文件，换一个镜像或直连 GitHub。 |
| 客户端与守护进程版本不一致 | 两个二进制都要来自同一个 Release，替换后重启服务。 |
| 服务无法启动 | Linux：`journalctl -u tailscaled -e`；macOS：`/var/log/tailscaled.log`；Windows：`C:\ProgramData\Tailscale\Logs`。 |
| Windows 创建 TUN 失败 | `wintun.dll` 必须与 `tailscaled.exe` 在同一目录（方式 B）。 |

传输设置（AWG、QUIC）见 [连接与配置](README-zh.md#连接与配置)。
