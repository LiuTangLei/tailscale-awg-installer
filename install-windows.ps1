# Windows-only installer (PowerShell): replace official Tailscale with Amnezia-WG 2.0-enabled binaries
# Compatible with Windows PowerShell 5.1 and PowerShell 7+
# Requires: Admin
#
# Parameters:
#   -MirrorPrefix: Optional GitHub mirror prefix (e.g., 'https://mirror.example.com')
#                  Will be prepended to GitHub URLs for faster downloads

[CmdletBinding()]
param(
  [string]$Repo = 'LiuTangLei/tailscale',
  [string]$Version = 'latest',
  [string]$InstallDir,
  [switch]$EnableMsiFallback = $true,
  [string]$MirrorPrefix = ''
)

# Support environment variable override for one-liner usage
if ([string]::IsNullOrEmpty($MirrorPrefix) -and $env:MIRROR_PREFIX) {
  $MirrorPrefix = $env:MIRROR_PREFIX
  Write-Info "Using mirror from environment: $MirrorPrefix"
}

$ErrorActionPreference = 'Stop'

#region Output Functions
function Write-Info($m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok($m) { Write-Host "[SUCCESS] $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "[WARNING] $m" -ForegroundColor Yellow }
function Write-Err($m) { Write-Host "[ERROR] $m" -ForegroundColor Red }
#endregion

#region System Validation
# Basic compatibility setup
$IsCore = ($PSVersionTable.PSEdition -eq 'Core' -or $PSVersionTable.PSVersion.Major -ge 6)
if (-not $IsCore) {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
  } catch {}
}

# System requirements check
try { $osVer = [version]((Get-CimInstance Win32_OperatingSystem).Version) }
catch { $osVer = [System.Environment]::OSVersion.Version }

if ($osVer.Major -lt 10) {
  Write-Err "Unsupported Windows version ($osVer). Requires Windows 10+."
  exit 1
}
if (-not [Environment]::Is64BitOperatingSystem) {
  Write-Err 'Unsupported 32-bit Windows. Only 64-bit (amd64/arm64) is supported.'
  exit 1
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Err "Please run this script as Administrator"
  exit 1
}

# Architecture detection
$arch = switch ((Get-CimInstance Win32_Processor).Architecture) {
  9 { 'amd64' }
  12 { 'arm64' }
  default { Write-Err "Unsupported arch: $_"; exit 1 }
}
$platform = "windows-$arch"
#endregion

#region Web Helper Functions
$UA = @{ 'User-Agent' = "tailscale-installer pwsh/$($PSVersionTable.PSVersion)"; 'Accept' = 'application/vnd.github+json' }

function Invoke-RestCompat([string]$Uri) {
  $p = @{ Uri = $Uri; Headers = $UA }
  if (-not $IsCore -and (Get-Command Invoke-RestMethod).Parameters.Keys -contains 'UseBasicParsing') {
    $p.UseBasicParsing = $true
  }
  Invoke-RestMethod @p
}

function Invoke-WebRequestCompat([string]$Uri, [string]$OutFile) {
  $p = @{ Uri = $Uri; OutFile = $OutFile; Headers = $UA }
  if (-not $IsCore -and (Get-Command Invoke-WebRequest).Parameters.Keys -contains 'UseBasicParsing') {
    $p.UseBasicParsing = $true
  }
  Invoke-WebRequest @p
}
#endregion

#region Service Management Functions
function Get-OfficialVersionFromTag([string]$Tag) {
  # Extract official Tailscale version from fork tag (e.g., v1.88.4 from v1.88.4-awg2.0-x)
  if ($Tag -match '^v?(\d+\.\d+\.\d+)') {
    return $Matches[1]
  }
  return $null
}

function Get-InstalledTailscaleVersion {
  # Try to get version from GUI binary (tailscale-ipn.exe) if it exists
  $ipnPath = "$Env:ProgramFiles\Tailscale\tailscale-ipn.exe"
  if (Test-Path $ipnPath) {
    try {
      $versionInfo = (Get-Item $ipnPath).VersionInfo
      if ($versionInfo.ProductVersion) {
        # ProductVersion may include extra info, extract just x.y.z
        if ($versionInfo.ProductVersion -match '(\d+\.\d+\.\d+)') {
          return $Matches[1]
        }
      }
    } catch { }
  }

  # Fallback: try tailscale.exe command
  try {
    $output = & tailscale.exe version 2>&1 | Select-Object -First 1
    if ($output -match '(\d+\.\d+\.\d+)') {
      return $Matches[1]
    }
  } catch { }

  return $null
}

function Wait-ServiceStatus([string]$Name, [ValidateSet('Running', 'Stopped')][string]$Status, [int]$TimeoutSec = 30) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    $s = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq $Status) { return $true }
    Start-Sleep -Milliseconds 400
  }
  return $false
}

function Start-ServiceCompat([string]$Name) {
  try {
    Start-Service -Name $Name -ErrorAction Stop
    return $true
  } catch {
    Write-Warn "Start-Service failed: $($_.Exception.Message). Trying 'net start'..."
    try {
      net start $Name | Out-Null
      return ($LASTEXITCODE -eq 0)
    } catch {
      return $false
    }
  }
}

function Stop-ServiceCompat([string]$Name) {
  try {
    Stop-Service -Name $Name -Force -ErrorAction Stop
    return $true
  } catch {
    Write-Warn "Stop-Service failed: $($_.Exception.Message). Trying 'net stop'..."
    try {
      net stop $Name | Out-Null
      return ($LASTEXITCODE -eq 0)
    } catch {
      return $false
    }
  }
}
#endregion

#region Binary Validation
function Test-PeArchitecture([string]$Path, [string]$ExpectedArch) {
  if (-not (Test-Path $Path)) { return @{ Valid = $false; Reason = 'File not found' } }
  try {
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
      $br = New-Object System.IO.BinaryReader($fs)
      if ($br.ReadUInt16() -ne 0x5A4D) { return @{ Valid = $false; Reason = 'Invalid PE file' } }
      $fs.Seek(0x3C, [System.IO.SeekOrigin]::Begin) | Out-Null
      $peOff = $br.ReadUInt32()
      $fs.Seek([int64]$peOff, [System.IO.SeekOrigin]::Begin) | Out-Null
      if ($br.ReadUInt32() -ne 0x00004550) { return @{ Valid = $false; Reason = 'Invalid PE signature' } }
      $machine = $br.ReadUInt16()
      $archMap = @{ [UInt16]0x8664 = 'amd64'; [UInt16]0xAA64 = 'arm64'; [UInt16]0x014c = 'x86' }
      $detectedArch = $archMap[[UInt16]$machine]
      if (-not $detectedArch) { $detectedArch = "unknown(0x{0:X4})" -f $machine }
      $isValid = ($detectedArch -eq $ExpectedArch)
      $reason = if (-not $isValid) { "Expected $ExpectedArch, got $detectedArch" } else { $null }
      return @{ Valid = $isValid; Arch = $detectedArch; Reason = $reason }
    } finally { $fs.Dispose() }
  } catch {
    return @{ Valid = $false; Reason = $_.Exception.Message }
  }
}
#endregion

#region Path Resolution and Official Install
# Resolve install paths
$defaultDir = if ($InstallDir -and $InstallDir.Trim()) { $InstallDir } else { "$Env:ProgramFiles\Tailscale" }
$tsCmd = Get-Command tailscale.exe -ErrorAction SilentlyContinue
$tsPath = if ($tsCmd) { $tsCmd.Source } else { "$defaultDir\tailscale.exe" }
$tsdCmd = Get-Command tailscaled.exe -ErrorAction SilentlyContinue
$tsdPath = if ($tsdCmd) { $tsdCmd.Source } else { "$defaultDir\tailscaled.exe" }

# Use service-configured path if available
$svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
if ($svc) {
  $svcCfg = Get-CimInstance Win32_Service -Filter "Name='Tailscale'" -ErrorAction SilentlyContinue
  if ($svcCfg -and $svcCfg.PathName) {
    $exePath = ($svcCfg.PathName -replace '^"([^"]+)".*', '$1') -replace '^([^\s]+).*', '$1'
    if (Test-Path $exePath) {
      $tsdPath = $exePath
      $defaultDir = Split-Path -Path $tsdPath -Parent
      $tsPath = "$defaultDir\tailscale.exe"
    }
  }
}

# Detect fork version to match official Tailscale version
$officialVersion = $null
$forkTag = $Version
if ($Version -eq 'latest') {
  try {
    Write-Info "Detecting fork version..."
    $resp = Invoke-RestCompat -Uri "https://api.github.com/repos/$Repo/releases/latest"
    $forkTag = $resp.tag_name
    $officialVersion = Get-OfficialVersionFromTag -Tag $forkTag
    if ($officialVersion) {
      Write-Info "Fork version: $forkTag (official Tailscale: $officialVersion)"
    }
  } catch { Write-Warn "Could not detect fork version: $($_.Exception.Message)" }
} else {
  $officialVersion = Get-OfficialVersionFromTag -Tag $Version
  if ($officialVersion) {
    Write-Info "Fork version: $forkTag (official Tailscale: $officialVersion)"
  }
}

# Check if we need to install or upgrade official Tailscale
$needsServiceCreate = $false
$needsInstallOrUpgrade = $false

if (-not (Get-Command tailscale.exe -ErrorAction SilentlyContinue) -and -not $svc) {
  Write-Warn 'Tailscale not found. Installing official version...'
  $needsInstallOrUpgrade = $true
} else {
  # Tailscale exists, check if GUI version matches fork version
  $installedVersion = Get-InstalledTailscaleVersion
  if ($installedVersion -and $officialVersion) {
    if ($installedVersion -ne $officialVersion) {
      Write-Warn "Installed Tailscale GUI version ($installedVersion) differs from fork version ($officialVersion)"
      Write-Info "Will upgrade official Tailscale to $officialVersion to match fork"
      $needsInstallOrUpgrade = $true
    } else {
      Write-Info "Tailscale GUI version ($installedVersion) matches fork; will replace binaries only"
    }
  } else {
    Write-Info 'Tailscale found; will replace binaries only'
  }
}

if ($needsInstallOrUpgrade) {
  $installed = $false  # Try winget first (only if no specific version needed, as winget may install latest)
  if (-not $officialVersion -and (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    try {
      & winget install -e --id Tailscale.Tailscale --silent --accept-package-agreements --accept-source-agreements
      Start-Sleep -Seconds 3
      $installed = [bool](Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue)
    } catch { Write-Warn "winget failed: $($_.Exception.Message)" }
  }

  # Try MSI if winget failed/skipped and enabled
  if (-not $installed -and $EnableMsiFallback) {
    # Use version-specific URL if detected, otherwise use latest
    if ($officialVersion) {
      $msiUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-$officialVersion-$arch.msi"
    } else {
      $msiUrl = if ($arch -eq 'amd64') { 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' } else { 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-arm64.msi' }
    }
    try {
      Write-Warn "Trying MSI installer from $msiUrl..."
      $tmpMsi = "$env:TEMP\tailscale-$([guid]::NewGuid()).msi"
      Invoke-WebRequestCompat -Uri $msiUrl -OutFile $tmpMsi
      $p = Start-Process msiexec.exe -ArgumentList @('/i', "`"$tmpMsi`"", '/qn', '/norestart') -Wait -PassThru
      if ($p.ExitCode -in 0, 3010) {
        Start-Sleep -Seconds 3
        $installed = [bool](Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue)
      }
      Remove-Item -Force $tmpMsi -ErrorAction SilentlyContinue
    } catch { Write-Warn "MSI failed: $($_.Exception.Message)" }
  }

  # Fallback to minimal install
  if (-not $installed) {
    Write-Warn 'Falling back to minimal local install'
    New-Item -ItemType Directory -Force -Path $defaultDir | Out-Null
    $needsServiceCreate = $true
  }
}

$svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
if ($svc) {
  $svcCfg = Get-CimInstance Win32_Service -Filter "Name='Tailscale'" -ErrorAction SilentlyContinue
  if ($svcCfg -and $svcCfg.PathName) {
    $exePath = ($svcCfg.PathName -replace '^"([^"]+)".*', '$1')
    if (Test-Path $exePath) {
      $tsdPath = $exePath
      $defaultDir = Split-Path -Path $tsdPath -Parent
      $tsPath = "$defaultDir\tailscale.exe"
    }
  }
}
#endregion

#region Binary Download and Installation
Write-Info 'Stopping Tailscale service (if running)...'
Stop-ServiceCompat -Name 'Tailscale' | Out-Null
Wait-ServiceStatus -Name 'Tailscale' -Status 'Stopped' -TimeoutSec 60 | Out-Null

Get-Process -Name 'tailscaled','tailscale','tailscale-ipn' -ErrorAction SilentlyContinue |
  Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 800

# Resolve version and download URLs
if ($Version -eq 'latest') {
  Write-Info 'Resolving latest release...'
  try {
    $resp = Invoke-RestCompat -Uri "https://api.github.com/repos/$Repo/releases/latest"
    $Version = $resp.tag_name
    if (-not $Version) { throw 'No tag_name in response' }
    Write-Info "Latest: $Version"
  } catch {
    Write-Err "Failed to resolve latest release: $($_.Exception.Message)"
    exit 1
  }
}

# Try to resolve asset URLs from release
$tsUrl = $tsdUrl = $null
try {
  $rel = Invoke-RestCompat -Uri "https://api.github.com/repos/$Repo/releases/tags/$Version"
  $ap = if ($arch -eq 'amd64') { 'amd64|x86_64|x64' } else { 'arm64|aarch64' }
  $ts = $rel.assets | Where-Object { $_.name -match "(?i)tailscale(?!d).*($ap).*(windows|win).*\.exe$" } | Select-Object -First 1
  $tsd = $rel.assets | Where-Object { $_.name -match "(?i)tailscaled.*($ap).*(windows|win).*\.exe$" } | Select-Object -First 1
  if ($ts -and $tsd) {
    $tsUrl = if ($MirrorPrefix) { $ts.browser_download_url -replace '^https://github\.com', $MirrorPrefix + '/https://github.com' } else { $ts.browser_download_url }
    $tsdUrl = if ($MirrorPrefix) { $tsd.browser_download_url -replace '^https://github\.com', $MirrorPrefix + '/https://github.com' } else { $tsd.browser_download_url }
    Write-Info "Resolved assets: $($ts.name), $($tsd.name)"
  }
} catch { Write-Warn "Could not resolve assets from release: $($_.Exception.Message)" }

# Fallback to guessed URLs
if (-not $tsUrl -or -not $tsdUrl) {
  Write-Warn 'Using fallback asset URLs'
  $base = if ($MirrorPrefix) { "$MirrorPrefix/https://github.com/$Repo/releases/download/$Version" } else { "https://github.com/$Repo/releases/download/$Version" }
  $tsUrl = "$base/tailscale-$platform.exe"
  $tsdUrl = "$base/tailscaled-$platform.exe"
}

# Download and install
$temp = New-Item -ItemType Directory -Path $env:TEMP -Name "ts-$([System.Guid]::NewGuid())"
try {
  $tsFile = "$temp\tailscale.exe"
  $tsdFile = "$temp\tailscaled.exe"

  Write-Info "Downloading tailscale..."
  Invoke-WebRequestCompat -Uri $tsUrl -OutFile $tsFile
  Write-Info "Downloading tailscaled..."
  Invoke-WebRequestCompat -Uri $tsdUrl -OutFile $tsdFile

  # Unblock and validate
  Unblock-File -Path $tsFile, $tsdFile -ErrorAction SilentlyContinue
  $tsValid = Test-PeArchitecture -Path $tsFile -ExpectedArch $arch
  $tsdValid = Test-PeArchitecture -Path $tsdFile -ExpectedArch $arch

  if (-not $tsValid.Valid -or -not $tsdValid.Valid) {
    Write-Err "Invalid binaries: tailscale=$($tsValid.Reason), tailscaled=$($tsdValid.Reason)"
    exit 1
  }

  # Install with backup
  New-Item -ItemType Directory -Force -Path (Split-Path $tsPath), (Split-Path $tsdPath) | Out-Null
  if (Test-Path $tsPath) { Copy-Item -Force $tsPath "$tsPath.bak" -ErrorAction SilentlyContinue }
  if (Test-Path $tsdPath) { Copy-Item -Force $tsdPath "$tsdPath.bak" -ErrorAction SilentlyContinue }

  $attempt = 0
  while ($true) {
    try {
      Copy-Item -Force $tsFile $tsPath
      Copy-Item -Force $tsdFile $tsdPath
      break
    } catch [System.IO.IOException] {
      if ($attempt -ge 10) { throw }
      Start-Sleep -Milliseconds 500
      $attempt++
    }
  }
  Unblock-File -Path $tsPath, $tsdPath -ErrorAction SilentlyContinue

  Write-Ok 'Binaries installed'
} finally {
  Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
}
#endregion

#region Service Management
# Create service if needed
$svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
if ($needsServiceCreate -and -not $svc) {
  Write-Info 'Registering Tailscale service...'
  $svcArgs = @{
    Name           = 'Tailscale'
    BinaryPathName = "`"$tsdPath`""
    DisplayName    = 'Tailscale Daemon'
    StartupType    = 'Automatic'
  }
  if ((Get-Command New-Service).Parameters.Keys -contains 'Description') {
    $svcArgs['Description'] = 'Tailscale WireGuard-based VPN'
  }
  New-Service @svcArgs | Out-Null
  $svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
}

# Ensure service points to correct binary and start it
if ($svc) {
  try {
    sc.exe config Tailscale binPath= "`"$tsdPath`"" | Out-Null
    Write-Info 'Starting Tailscale service...'
    if (Start-ServiceCompat -Name 'Tailscale') {
      if (Wait-ServiceStatus -Name 'Tailscale' -Status 'Running' -TimeoutSec 30) {
        Write-Ok 'Service started successfully'
      } else {
        Write-Warn 'Service command succeeded but not in Running state'
      }
    } else {
      Write-Err 'Service failed to start. Check Event Viewer for details.'
    }
  } catch {
    Write-Err "Service configuration failed: $($_.Exception.Message)"
  }
}
#endregion

#region Launch GUI
Write-Info 'Launching Tailscale GUI client (if available)...'
$ipnPath = "$defaultDir\tailscale-ipn.exe"
if (Test-Path $ipnPath) {
  $outFile = $null
  $errFile = $null
  try {
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    Start-Process -FilePath $ipnPath -WindowStyle Hidden -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
    Write-Ok 'Tailscale GUI launched'
  } catch {
    Write-Warn "Failed to launch GUI: $($_.Exception.Message)"
  } finally {
    if ($outFile -and (Test-Path $outFile)) { Remove-Item -Path $outFile -Force -ErrorAction SilentlyContinue }
    if ($errFile -and (Test-Path $errFile)) { Remove-Item -Path $errFile -Force -ErrorAction SilentlyContinue }
  }
} else {
  Write-Warn 'Tailscale GUI (tailscale-ipn.exe) not found; skipping launch'
}
#endregion

Write-Host ''
Write-Host 'Quick Start:'
Write-Host '  tailscale up'
Write-Host ''
Write-Host 'Amnezia-WG commands (awg = amnezia-wg):'
Write-Host '  tailscale awg set        # Configure obfuscation (auto-generate with Enter)'
Write-Host '  tailscale awg get        # Show current config'
Write-Host '  tailscale awg sync       # Sync config from other nodes'
Write-Host '  tailscale awg reset      # Disable obfuscation'
Write-Host ''