# Windows-only installer (PowerShell): replace official Tailscale with Amnezia-WG-enabled binaries
# Requires: PowerShell 5+, Administrator rights.

param(
  [string]$Repo = 'LiuTangLei/tailscale',
  [string]$Version = 'latest'
)

$ErrorActionPreference = 'Stop'

function Write-Info($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok($m){ Write-Host "[SUCCESS] $m" -ForegroundColor Green }
function Write-Warn($m){ Write-Host "[WARNING] $m" -ForegroundColor Yellow }
function Write-Err($m){ Write-Host "[ERROR] $m" -ForegroundColor Red }

# Admin check
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Err "Please run this script as Administrator"
  exit 1
}

# Track whether we need to create the service in minimal local install mode
$script:NeedsServiceCreate = $false

# Arch detection
$arch = (Get-CimInstance Win32_Processor).Architecture
switch ($arch) {
  9 { $arch = 'amd64' } # x64
  12 { $arch = 'arm64' }
  default { Write-Err "Unsupported arch: $arch"; exit 1 }
}
$platform = "windows-$arch"

# Resolve install paths (default program files)
$defaultDir = "$Env:ProgramFiles\Tailscale"
# PowerShell 5.1-compatible resolution (avoid null-conditional operator)
$tsCmd = Get-Command tailscale.exe -ErrorAction SilentlyContinue
$tsPath = if ($tsCmd) { $tsCmd.Source } else { $null }
$tsdCmd = Get-Command tailscaled.exe -ErrorAction SilentlyContinue
$tsdPath = if ($tsdCmd) { $tsdCmd.Source } else { $null }
if (-not $tsPath) { $tsPath = Join-Path $defaultDir 'tailscale.exe' }
if (-not $tsdPath) { $tsdPath = Join-Path $defaultDir 'tailscaled.exe' }

# Resolve service path if service exists (use the exact binary used by the service)
$svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
if ($svc) {
  $svcCfg = Get-CimInstance Win32_Service -Filter "Name='Tailscale'" -ErrorAction SilentlyContinue
  if ($svcCfg -and $svcCfg.PathName) {
    $exeCandidate = $svcCfg.PathName
    if ($exeCandidate.StartsWith('"')) { $exeCandidate = $exeCandidate.Split('"')[1] } else { $exeCandidate = $exeCandidate.Split(' ')[0] }
    if (Test-Path $exeCandidate) { $tsdPath = $exeCandidate }
  }
}

# If not installed, attempt official install; fallback to minimal local install
function Install-OfficialIfMissing {
  $hasCmd = [bool](Get-Command tailscale.exe -ErrorAction SilentlyContinue)
  $hasSvc = [bool](Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue)
  if ($hasCmd -or $hasSvc) {
    Write-Info 'Tailscale found; will replace binaries only'
    return
  }
  Write-Warn 'Tailscale not found. Attempting official install via winget...'
  $installed = $false
  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
  if ($winget) {
    try {
      winget install -e --id Tailscale.Tailscale --silent --accept-package-agreements --accept-source-agreements
      Start-Sleep -Seconds 3
      if (Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue) { $installed = $true }
    } catch {
      Write-Warn 'winget install failed or unavailable.'
    }
  }
  if (-not $installed) {
    Write-Warn 'Falling back to minimal local install (will register service).'
    New-Item -ItemType Directory -Force -Path $defaultDir | Out-Null
    $script:NeedsServiceCreate = $true
  }
}

Install-OfficialIfMissing

# Stop service if running
$svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
  Write-Info 'Stopping Tailscale service...'
  Stop-Service -Name 'Tailscale' -Force -ErrorAction SilentlyContinue
}

# Resolve latest tag
if ($Version -eq 'latest') {
  Write-Info 'Resolving latest release...'
  $resp = Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/$Repo/releases/latest"
  $Version = $resp.tag_name
  if (-not $Version) { Write-Err 'Failed to resolve latest release'; exit 1 }
  Write-Info "Latest: $Version"
}

$base = "https://github.com/$Repo/releases/download/$Version"
$tsUrl = "$base/tailscale-$platform.exe"
$tsdUrl = "$base/tailscaled-$platform.exe"

$temp = New-Item -ItemType Directory -Path ([System.IO.Path]::GetTempPath()) -Name ("ts-" + [System.Guid]::NewGuid())
try {
  $tsFile = Join-Path $temp 'tailscale.exe'
  $tsdFile = Join-Path $temp 'tailscaled.exe'
  Write-Info "Downloading $tsUrl"
  Invoke-WebRequest -UseBasicParsing -Uri $tsUrl -OutFile $tsFile
  Write-Info "Downloading $tsdUrl"
  Invoke-WebRequest -UseBasicParsing -Uri $tsdUrl -OutFile $tsdFile

  New-Item -ItemType Directory -Force -Path (Split-Path $tsPath) | Out-Null
  New-Item -ItemType Directory -Force -Path (Split-Path $tsdPath) | Out-Null
  Copy-Item -Force $tsFile $tsPath
  Copy-Item -Force $tsdFile $tsdPath
  Write-Ok 'Binaries installed'
}
finally {
  Remove-Item -Recurse -Force $temp
}

# (Re)create service if needed
$svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
if ($script:NeedsServiceCreate -and -not $svc) {
  Write-Info 'Registering Tailscale service...'
  New-Service -Name 'Tailscale' -BinaryPathName '"{0}"' -f $tsdPath -DisplayName 'Tailscale Daemon' -Description 'Tailscale WireGuard-based VPN' -StartupType Automatic | Out-Null
  $svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
}

# Restart service if available
if ($svc) {
  Write-Info 'Starting Tailscale service...'
  Start-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Quick Start:'
Write-Host '  tailscale up'
Write-Host '  tailscale amnezia-wg set'
Write-Host '  tailscale amnezia-wg get'
Write-Host '  tailscale amnezia-wg reset'
