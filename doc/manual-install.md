# Manual installation

[中文](manual-install-zh.md) · [Back to README](../README.md)

Use this guide when the one-line installers cannot run, for example on an offline machine or a custom system layout. The installers perform the same steps automatically and also roll back on failure, so prefer them when you can.

Manual installation replaces only the `tailscale` and `tailscaled` binaries. Your login and node state are kept, as long as the state directory stays the same.

## Before you start

Each [release](https://github.com/LiuTangLei/tailscale/releases/latest) provides standalone binaries for x86_64 (`amd64`) and ARM64 (`arm64`):

| System | Files |
| --- | --- |
| Linux | `tailscale-linux-<arch>`, `tailscaled-linux-<arch>` |
| macOS | `tailscale-darwin-<arch>`, `tailscaled-darwin-<arch>` |
| Windows | `tailscale-windows-<arch>.exe`, `tailscaled-windows-<arch>.exe` |
| All | `SHA256SUMS` (checksums for every file) |

- Version numbers follow upstream: fork `vX.Y.Z` is based on Tailscale `vX.Y.Z`.
- Links ending in `releases/latest/download/<file>` always point to the newest release. To pin a version, use `releases/download/vX.Y.Z/<file>` instead.
- If GitHub is slow or blocked, put a mirror in front of every GitHub link, for example `https://ghfast.top/https://github.com/...`. See [GitHub mirrors](../README.md#github-mirrors).
- Always check the binaries against `SHA256SUMS` before installing them.
- Other Linux architectures (armv7, mips, riscv64 and so on) are covered by the [OpenWrt packages](#openwrt) and the [Docker image](../README.md#docker).

## Linux

Commands are for a root shell or a user with `sudo`. Run all steps in the same terminal, because later steps use variables from earlier ones.

### 1. Download and verify

```bash
case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" ;;
esac
BASE=https://github.com/LiuTangLei/tailscale/releases/latest/download
# With a mirror:
# BASE=https://ghfast.top/https://github.com/LiuTangLei/tailscale/releases/latest/download

mkdir -p ~/tailscale-awg && cd ~/tailscale-awg
curl -fL -O "$BASE/tailscale-linux-$ARCH" -O "$BASE/tailscaled-linux-$ARCH" -O "$BASE/SHA256SUMS"
grep -E " tailscaled?-linux-$ARCH\$" SHA256SUMS | sha256sum -c -
chmod +x "tailscale-linux-$ARCH" "tailscaled-linux-$ARCH"
./"tailscale-linux-$ARCH" version
```

Both lines must report `OK`. Without `curl`, use `wget` for each file.

Then follow **one** of the three options below.

### 2a. Replace the official package (recommended)

This keeps the service file and paths of the official package. It also upgrades any existing systemd install, including one made by the one-line installer or option 2b. If Tailscale is not installed yet, install the official version first:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

Find the binaries that are actually in use, back them up and replace them:

```bash
TS=$(readlink -f "$(command -v tailscale)")
TSD=$(systemctl show -p ExecStart tailscaled | sed -n 's/.*path=\([^ ;]*\).*/\1/p')
TSD=$(readlink -f "$TSD")
echo "client: $TS  daemon: $TSD"   # usually /usr/bin/tailscale and /usr/sbin/tailscaled

sudo systemctl stop tailscaled
sudo cp -p "$TS" "$TS.official" && sudo cp -p "$TSD" "$TSD.official"
sudo install -m 755 "tailscale-linux-$ARCH" "$TS"
sudo install -m 755 "tailscaled-linux-$ARCH" "$TSD"
sudo systemctl start tailscaled
```

A package update reinstalls the official binaries. Either repeat this section after each update, or hold the package:

| Distribution | Hold | Release the hold |
| --- | --- | --- |
| Debian / Ubuntu | `sudo apt-mark hold tailscale` | `sudo apt-mark unhold tailscale` |
| Fedora / RHEL | `sudo dnf versionlock add tailscale` (needs the versionlock plugin) | `sudo dnf versionlock delete tailscale` |
| Arch Linux | add `IgnorePkg = tailscale` to `/etc/pacman.conf` | remove that line |

### 2b. Standalone install with systemd

Use this when you do not want the official package.

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

If an official package is already installed, use 2a instead or remove the package first, so that two services do not compete.

### 2c. Standalone install with OpenRC (Alpine and others)

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

On Alpine, run these as root if `sudo` is not installed. TUN mode needs the `tun` kernel module (`modprobe tun`).

### 3. Log in and check

```bash
sudo tailscale up            # Headscale: add --login-server https://your-headscale-domain
tailscale version
tailscale awg status
```

If `tailscale awg status` reports an unknown command, an official binary is still in use. Check `command -v tailscale` and the service's `ExecStart` path.

### Upgrade, roll back, uninstall

- **Upgrade**: repeat step 1, then the replace commands of the option you used (stop the service, `install` both files, start the service).
- **Roll back to official (2a)**: `sudo systemctl stop tailscaled`, move the `.official` backups back, then start the service. You can also reinstall the package, for example `sudo apt install --reinstall tailscale`.
- **Uninstall (2b)**: `sudo systemctl disable --now tailscaled`, then remove `/etc/systemd/system/tailscaled.service`, `/usr/local/bin/tailscale` and `/usr/local/bin/tailscaled`.
- **Uninstall (2c)**: `sudo rc-service tailscaled stop && sudo rc-update del tailscaled default`, then remove `/etc/init.d/tailscaled`, `/usr/local/bin/tailscale` and `/usr/local/bin/tailscaled`.
- Deleting `/var/lib/tailscale` also removes the login and the saved AWG profile.

## macOS

The fork runs as a command-line daemon (utun), not as Tailscale.app. Both cannot run at the same time, and moving from the app requires signing in again.

### 1. Remove conflicting installs

- **Tailscale.app**: quit it from the menu bar, then move it from `/Applications` to the Trash.
- **Homebrew**: `brew services stop tailscale && brew uninstall tailscale`
- **Earlier fork install** (from the installer or by hand): nothing to remove. Step 3 finds and replaces it.

### 2. Download and verify

```bash
case "$(uname -m)" in x86_64) ARCH=amd64 ;; arm64) ARCH=arm64 ;; esac
BASE=https://github.com/LiuTangLei/tailscale/releases/latest/download
# With a mirror:
# BASE=https://ghfast.top/https://github.com/LiuTangLei/tailscale/releases/latest/download

mkdir -p ~/tailscale-awg && cd ~/tailscale-awg
curl -fL -O "$BASE/tailscale-darwin-$ARCH" -O "$BASE/tailscaled-darwin-$ARCH" -O "$BASE/SHA256SUMS"
grep -E " tailscaled?-darwin-$ARCH\$" SHA256SUMS | shasum -a 256 -c -
chmod +x "tailscale-darwin-$ARCH" "tailscaled-darwin-$ARCH"
```

Both lines must report `OK`. If you downloaded the files with a browser, also clear the quarantine flag: `xattr -d com.apple.quarantine tailscale*-darwin-*`. The binaries are ad-hoc signed.

### 3. Install the binaries

An existing service keeps its directory (the installer uses `/opt/homebrew/bin` on many Apple Silicon Macs). A new install uses `/usr/local/bin`.

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

If the service already existed, restart it with `sudo launchctl kickstart -k system/com.tailscale.tailscaled` and go to step 5.

### 4. Create and start the system service

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

If `/usr/local/bin` is not in your `PATH`, add it to your shell profile.

### 5. Log in and check

```bash
sudo tailscale up            # Headscale: add --login-server https://your-headscale-domain
tailscale version
tailscale awg status
```

### Upgrade and uninstall

- **Upgrade**: repeat steps 2 and 3, then `sudo launchctl kickstart -k system/com.tailscale.tailscaled`.
- **Uninstall**:

  ```bash
  PLIST=/Library/LaunchDaemons/com.tailscale.tailscaled.plist
  DIR=$(dirname "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$PLIST")")
  sudo launchctl bootout system/com.tailscale.tailscaled
  sudo rm -f "$PLIST" "$DIR/tailscale" "$DIR/tailscaled"
  ```

  Also delete `/var/lib/tailscale` to remove the login and AWG profile. Logs are in `/var/log/tailscaled.log`.

## Windows

Run everything in **PowerShell as Administrator**. Choose option A if you want the Tailscale tray app, or option B for a service without a GUI.

### 1. Download and verify

```powershell
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tag  = (Invoke-RestMethod https://api.github.com/repos/LiuTangLei/tailscale/releases/latest).tag_name
# If api.github.com is unreachable, set the tag from the release page by hand, for example:
# $tag = 'v1.104.4'
$ver  = $tag.TrimStart('v')
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$base = "https://github.com/LiuTangLei/tailscale/releases/download/$tag"
# With a mirror:
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

### 2A. With the Tailscale app (recommended)

The tray app must be the **same version** as the fork. Install the matching official MSI, or skip this if that exact version is already installed:

```powershell
$msi = "$dir\tailscale-setup-$ver-$arch.msi"
Invoke-WebRequest -UseBasicParsing "https://pkgs.tailscale.com/stable/tailscale-setup-$ver-$arch.msi" -OutFile $msi
Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait
```

Then replace the two binaries:

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

Turning off auto-update stops the official app from replacing the fork. Sign in from the tray icon or with `tailscale up`.

### 2B. Service only, without the app

`tailscaled.exe` needs `wintun.dll` in the same folder. The official MSI ships it; here it is downloaded from wintun.net:

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

`install-system-daemon` creates and starts the `Tailscale` service. Open a new terminal so the updated `Path` applies, then run `tailscale up`.

### 3. Check

```powershell
tailscale version
tailscale awg status
```

### Upgrade, roll back, uninstall

- **Upgrade (A)**: repeat step 1. If the base version changed, install the matching MSI first. Then repeat the replace commands.
- **Upgrade (B)**: repeat step 1, `Stop-Service Tailscale`, copy both `.exe` files again, `Start-Service Tailscale`.
- **Roll back to official (A)**: stop the service, copy the `.official` files back over `tailscale.exe` and `tailscaled.exe`, then start the service. Reinstalling the official MSI also works.
- **Uninstall (A)**: uninstall Tailscale from *Settings → Apps*.
- **Uninstall (B)**: `& "$env:ProgramFiles\Tailscale\tailscaled.exe" uninstall-system-daemon`, then delete `C:\Program Files\Tailscale` and remove it from the system `Path`.
- State and logs are in `C:\ProgramData\Tailscale`. Delete it to remove the login and AWG profile.

## OpenWrt

The [OpenWrt installer](https://github.com/LiuTangLei/openwrt-tailscale-awg) is the easiest route. To install a package by hand:

1. Find your package architecture: `opkg print-architecture` (OpenWrt 24.10) or `apk --print-arch` (OpenWrt 25.12).
2. Download the matching `.ipk` or `.apk` from the [OpenWrt releases](https://github.com/LiuTangLei/openwrt-tailscale-awg/releases/latest) and copy it to `/tmp` on the router.
3. Install it:
   - OpenWrt 24.10: `opkg install /tmp/tailscale_*.ipk`
   - OpenWrt 25.12: `apk add --allow-untrusted /tmp/tailscale_*.apk`
4. Start it: `/etc/init.d/tailscale enable && /etc/init.d/tailscale start`, then `tailscale up`.

You can also add the signed [package feed](https://liutanglei.github.io/openwrt-tailscale-awg/) to get updates through `opkg` / `apk`. Settings are in `/etc/config/tailscale`.

## Android and iOS

- **Android**: download the APK from [Android releases](https://github.com/LiuTangLei/tailscale-android/releases/latest) and open it on the device. If the official Tailscale app from Google Play is installed, uninstall it first, because the signatures differ. Later fork updates install over the old version and keep your data.
- **iOS**: install the IPA from [AwgScale releases](https://github.com/LiuTangLei/AwgScale/releases) with TrollStore. The system VPN needs TrollStore or a Packet Tunnel entitlement.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| `tailscale awg` is an unknown command | An official binary is still in use. Linux / macOS: `which -a tailscale tailscaled` and the service's start command. Windows: `Get-Command tailscale`. |
| Checksum mismatch | Download again. A mirror can serve a stale or broken file; try another mirror or GitHub directly. |
| Client and daemon versions differ | Replace both binaries from the same release, then restart the service. |
| Service does not start | Linux: `journalctl -u tailscaled -e`. macOS: `/var/log/tailscaled.log`. Windows: `C:\ProgramData\Tailscale\Logs`. |
| Windows: TUN creation fails | `wintun.dll` must be next to `tailscaled.exe` (option B). |

For transport settings (AWG, QUIC), see [Connect and configure](../README.md#connect-and-configure).
