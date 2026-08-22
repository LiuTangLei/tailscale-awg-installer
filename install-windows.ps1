# Windows-only installer (PowerShell): replace official Tailscale with AWG v2/v3-enabled binaries
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
  [switch]$PreRelease,
  [string]$MirrorPrefix = ''
)

$ErrorActionPreference = 'Stop'
$AwgCRemovedVersion = [version]'1.98.1'
$AwgV3MinVersion = [version]'1.102.2'
$LegacyCpsCounterDetected = $false

#region Output Functions
function Write-Info($m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok($m) { Write-Host "[SUCCESS] $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "[WARNING] $m" -ForegroundColor Yellow }
function Write-Err($m) { Write-Host "[ERROR] $m" -ForegroundColor Red }
#endregion

# Support environment variable override for one-liner usage
if ([string]::IsNullOrEmpty($MirrorPrefix) -and $env:MIRROR_PREFIX) {
  $MirrorPrefix = $env:MIRROR_PREFIX
  Write-Info "Using mirror from environment: $MirrorPrefix"
}
if ($MirrorPrefix) { $MirrorPrefix = $MirrorPrefix.TrimEnd('/') }

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
if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
  Write-Err 'This installer only supports Windows; no applications, services, binaries, or state were changed.'
  throw 'Unsupported operating system'
}
try { $osVer = [version]((Get-CimInstance Win32_OperatingSystem).Version) }
catch { $osVer = [System.Environment]::OSVersion.Version }

if ($osVer.Major -lt 10) {
  Write-Err "Unsupported Windows version ($osVer). Requires Windows 10+."
  throw "Unsupported Windows version: $osVer"
}
if (-not [Environment]::Is64BitOperatingSystem) {
  Write-Err 'Unsupported 32-bit Windows. Only 64-bit (amd64/arm64) is supported.'
  throw 'Unsupported 32-bit Windows'
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Err "Please run this script as Administrator"
  throw 'Administrator privileges are required'
}

# Architecture detection
$arch = switch ((Get-CimInstance Win32_Processor).Architecture) {
  9 { 'amd64' }
  12 { 'arm64' }
  default { Write-Err "Unsupported arch: $_"; throw "Unsupported processor architecture: $_" }
}
$platform = "windows-$arch"
#endregion

#region Web Helper Functions
$UA = @{ 'User-Agent' = "tailscale-installer pwsh/$($PSVersionTable.PSVersion)"; 'Accept' = 'application/vnd.github+json' }
$script:LastRestUsedMirror = $false

function Invoke-RestCompat([string]$Uri) {
  $script:LastRestUsedMirror = $false
  $p = @{ Uri = $Uri; Headers = $UA }
  if (-not $IsCore -and (Get-Command Invoke-RestMethod).Parameters.Keys -contains 'UseBasicParsing') {
    $p.UseBasicParsing = $true
  }
  try {
    Invoke-RestMethod @p
  } catch {
    if ($MirrorPrefix -and $Uri.StartsWith('https://api.github.com/', [System.StringComparison]::OrdinalIgnoreCase)) {
      $p.Uri = "$MirrorPrefix/$Uri"
      $script:LastRestUsedMirror = $true
      return Invoke-RestMethod @p
    }
    throw
  }
}

function Invoke-WebRequestCompat([string]$Uri, [string]$OutFile) {
  $p = @{ Uri = $Uri; OutFile = $OutFile; Headers = $UA }
  if (-not $IsCore -and (Get-Command Invoke-WebRequest).Parameters.Keys -contains 'UseBasicParsing') {
    $p.UseBasicParsing = $true
  }
  Invoke-WebRequest @p
}

function Add-MirrorPrefixToGitHubUrl([string]$Uri) {
  if ([string]::IsNullOrWhiteSpace($Uri) -or -not $MirrorPrefix) { return $Uri }
  $githubPrefix = 'https://github.com'
  if ($Uri.StartsWith($githubPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    return "$MirrorPrefix/$githubPrefix$($Uri.Substring($githubPrefix.Length))"
  }
  return $Uri
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

function Get-VersionObjectFromTag([string]$Tag) {
  if ($Tag -match '^v?(\d+\.\d+\.\d+)') {
    return [version]$Matches[1]
  }
  return [version]'0.0.0'
}

function Get-ReleasePublishedAt($Release) {
  if ($Release -and $Release.published_at) {
    try { return [datetime]$Release.published_at } catch { }
  }
  return [datetime]::MinValue
}

function Select-FirstItem($Value) {
  $items = @($Value)
  if ($items.Count -eq 0) { return $null }
  return $items[0]
}

function Get-ReleaseTagName($Release) {
  $firstRelease = Select-FirstItem -Value $Release
  if (-not $firstRelease) { return $null }
  return Select-FirstItem -Value $firstRelease.tag_name
}

function Select-HighestVersionRelease($Releases, [bool]$Prerelease) {
  $sorted = @(
    @($Releases) |
      Where-Object { $_.prerelease -eq $Prerelease -and $_.tag_name -match '^v?\d+\.\d+\.\d+' } |
      Sort-Object -Property @{ Expression = { Get-VersionObjectFromTag -Tag $_.tag_name }; Descending = $true }, @{ Expression = { Get-ReleasePublishedAt -Release $_ }; Descending = $true }
  )
  if ($sorted.Count -eq 0) { return $null }
  return Select-FirstItem -Value $sorted
}

function Get-ExePathFromCommandLine([string]$CommandLine) {
  if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
  if ($CommandLine -match '^\s*"([^"]+)"') { return $Matches[1] }
  if ($CommandLine -match '^\s*(.+?\.exe)(?:\s+.*)?$') { return $Matches[1].Trim() }
  if ($CommandLine -match '^\s*([^\s]+)') { return $Matches[1] }
  return $null
}

function Get-ArgumentsFromCommandLine([string]$CommandLine) {
  if ([string]::IsNullOrWhiteSpace($CommandLine)) { return '' }
  if ($CommandLine -match '^\s*"[^"]+"\s*(.*)$') { return $Matches[1] }
  if ($CommandLine -match '^\s*.+?\.exe(?:\s+(.*))?$') { return [string]$Matches[1] }
  if ($CommandLine -match '^\s*[^\s]+\s*(.*)$') { return $Matches[1] }
  return ''
}

function Get-SafeTailscaledServicePath([string]$CommandLine) {
  $path = Get-ExePathFromCommandLine -CommandLine $CommandLine
  if ([string]::IsNullOrWhiteSpace($path)) {
    throw 'The Tailscale service executable path could not be parsed safely'
  }
  $path = [System.Environment]::ExpandEnvironmentVariables($path)
  if (-not [System.IO.Path]::IsPathRooted($path)) {
    throw "The Tailscale service executable path is not absolute: $path"
  }
  if (-not [string]::Equals([System.IO.Path]::GetFileName($path), 'tailscaled.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The Tailscale service uses a custom wrapper instead of tailscaled.exe: $path"
  }
  try {
    return [System.IO.Path]::GetFullPath($path)
  } catch {
    throw "The Tailscale service executable path is invalid: $path"
  }
}

function Get-TailscaledProcessValidationError([object[]]$Processes, [object]$Service) {
  $processes = @($Processes)
  $servicePid = if ($service) { [uint32]$service.ProcessId } else { [uint32]0 }
  if ($processes.Count -eq 0) {
    if ($servicePid -ne 0) {
      return "The Tailscale service reports PID $servicePid, but no tailscaled.exe process could be inspected"
    }
    return
  }

  if ($servicePid -eq 0) {
    return 'An unmanaged tailscaled.exe process is running; stop it before retrying'
  }

  $servicePath = Get-SafeTailscaledServicePath -CommandLine $service.PathName
  $processesByPid = @{}
  foreach ($process in $processes) {
    $processesByPid[[string][uint32]$process.ProcessId] = $process
  }
  if (-not $processesByPid.ContainsKey([string]$servicePid)) {
    return "The Tailscale service reports PID $servicePid, but that tailscaled.exe process could not be inspected"
  }

  $serviceProcess = $processesByPid[[string]$servicePid]
  if (-not [string]::IsNullOrWhiteSpace([string]$serviceProcess.ExecutablePath) -and
      -not (Test-SamePath -Left $serviceProcess.ExecutablePath -Right $servicePath)) {
    return "The Tailscale service PID $servicePid uses an unexpected executable path"
  }

  # SCM tracks the tailscaled service parent. That parent normally starts
  # same-binary /subproc (and sometimes /firewall) descendants, so their PIDs
  # are expected to differ from Win32_Service.ProcessId. Accept only the
  # descendant tree; when CIM exposes ExecutablePath, require the same binary.
  # An independent tailscaled root remains unsafe.
  $managedPids = @{}
  $managedPids[[string]$servicePid] = $true
  $added = $true
  while ($added) {
    $added = $false
    foreach ($process in $processes) {
      $processId = [uint32]$process.ProcessId
      $processIdKey = [string]$processId
      if ($managedPids.ContainsKey($processIdKey)) { continue }

      $parentKey = [string][uint32]$process.ParentProcessId
      if (-not $managedPids.ContainsKey($parentKey)) { continue }
      if (-not [string]::IsNullOrWhiteSpace([string]$process.ExecutablePath) -and
          -not (Test-SamePath -Left $process.ExecutablePath -Right $servicePath)) {
        return "A tailscaled.exe descendant uses an unexpected executable path (PID $processId)"
      }
      $managedPids[$processIdKey] = $true
      $added = $true
    }
  }

  foreach ($process in $processes) {
    $processId = [uint32]$process.ProcessId
    if (-not $managedPids.ContainsKey([string]$processId)) {
      return "An extra unmanaged tailscaled.exe process is running (PID $processId, parent PID $($process.ParentProcessId)); stop it before retrying"
    }
  }
}

function Assert-TailscaledProcessesManaged {
  $lastError = $null
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      # Read the service on both sides of the process snapshot. If its PID
      # changed, SCM restarted it mid-query and the snapshot is not reliable.
      $serviceBefore = Get-CimInstance Win32_Service -Filter "Name='Tailscale'" -ErrorAction Stop
      $processes = @(Get-CimInstance Win32_Process -Filter "Name='tailscaled.exe'" -ErrorAction Stop)
      $serviceAfter = Get-CimInstance Win32_Service -Filter "Name='Tailscale'" -ErrorAction Stop
    } catch {
      throw "Could not inspect running tailscaled processes safely: $($_.Exception.Message)"
    }

    $beforePid = if ($serviceBefore) { [uint32]$serviceBefore.ProcessId } else { [uint32]0 }
    $afterPid = if ($serviceAfter) { [uint32]$serviceAfter.ProcessId } else { [uint32]0 }
    if ($beforePid -ne $afterPid) {
      $lastError = 'The Tailscale service restarted while its processes were being inspected'
    } else {
      $lastError = Get-TailscaledProcessValidationError -Processes $processes -Service $serviceAfter
      if ([string]::IsNullOrWhiteSpace([string]$lastError)) { return }
    }

    if ($attempt -lt 3) { Start-Sleep -Milliseconds 200 }
  }
  throw $lastError
}

function Get-TailscaleGuiPaths {
  $candidates = @()
  if ($defaultDir) {
    $candidates += (Join-Path $defaultDir 'tailscale-ipn.exe')
  }
  if ($Env:ProgramFiles) {
    $candidates += (Join-Path $Env:ProgramFiles 'Tailscale\tailscale-ipn.exe')
  }
  @($candidates | Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ })
}

function Get-InstalledTailscaleVersion {
  # A GUI install must be identified from the GUI itself. Falling back to the
  # CLI when a GUI exists can hide an incompatible GUI/daemon version pair.
  $guiPaths = @(Get-TailscaleGuiPaths)
  foreach ($ipnPath in $guiPaths) {
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
  if ($guiPaths.Count -gt 0) { return $null }

  # CLI/service-only installs do not have a GUI compatibility requirement.
  try {
    $cliPath = if ($tsPath -and (Test-Path $tsPath)) { $tsPath } else { 'tailscale.exe' }
    $output = & $cliPath version 2>&1 | Select-Object -First 1
    if ($output -match '(\d+\.\d+\.\d+)') {
      return $Matches[1]
    }
  } catch { }

  return $null
}

function Test-LegacyCpsCounterTag {
  $cmd = Get-Command tailscale.exe -ErrorAction SilentlyContinue
  if (-not $cmd) { return $false }
  try {
    $text = (& $cmd.Source awg get 2>$null | Out-String)
    if (-not $text) {
      $text = (& $cmd.Source amnezia-wg get 2>$null | Out-String)
    }
    return $text.Contains('<c>')
  } catch {
    return $false
  }
}

function Show-AwgGuidance([string]$ReleaseTag, [bool]$LegacyCounterDetected) {
  $releaseVersion = Get-VersionObjectFromTag -Tag $ReleaseTag
  $supportsV3 = $releaseVersion -ge $AwgV3MinVersion
  Write-Host 'Amnezia-WG commands (awg = amnezia-wg):'
  if ($supportsV3) {
    Write-Ok 'AWG v3 is available; existing AWG v2 profiles remain supported.'
    Write-Host '  tailscale awg set        # Enter = generate AWG v3; choose 2 for AWG v2'
  } else {
    Write-Warn "This release predates AWG v3; install v$AwgV3MinVersion or newer for the v3 generator."
    Write-Host '  tailscale awg set        # Configure the AWG version supported by this release'
  }
  if ($LegacyCounterDetected) {
    if ($releaseVersion -ge $AwgCRemovedVersion) {
      Write-Warn "Legacy CPS tag <c> was detected. It is unsupported by the selected release (v$AwgCRemovedVersion+); remove only <c> from i1-i5."
    } else {
      Write-Warn "Legacy CPS tag <c> was detected. This old release accepts it, but v$AwgCRemovedVersion+ does not."
    }
  }
  Write-Host '  tailscale awg get        # Show the current profile and JSON'
  if ($supportsV3) {
    Write-Host '  tailscale awg validate   # Validate the current profile'
    Write-Host '  tailscale awg sync       # Sync a compatible v2/v3 profile'
  } else {
    Write-Host '  tailscale awg sync       # Sync a compatible AWG v2 profile'
  }
  Write-Host '  tailscale awg reset      # Disable AWG and use standard WireGuard'
}

function Wait-ServiceStatus([string]$Name, [ValidateSet('Running', 'Stopped')][string]$Status, [int]$TimeoutSec = 30) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    $s = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq $Status) { return $true }
    Start-Sleep -Milliseconds 400
  }
  $s = Get-Service -Name $Name -ErrorAction SilentlyContinue
  return [bool]($s -and $s.Status -eq $Status)
}

function Wait-ServiceExists([string]$Name, [int]$TimeoutSec = 30) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    if (Get-Service -Name $Name -ErrorAction SilentlyContinue) { return $true }
    Start-Sleep -Milliseconds 400
  }
  return [bool](Get-Service -Name $Name -ErrorAction SilentlyContinue)
}

function Wait-ServiceAbsent([string]$Name, [int]$TimeoutSec = 30) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    if (-not (Get-Service -Name $Name -ErrorAction SilentlyContinue)) { return $true }
    Start-Sleep -Milliseconds 400
  }
  return -not [bool](Get-Service -Name $Name -ErrorAction SilentlyContinue)
}

function Wait-TailscaledProcessesAbsent([int]$TimeoutSec = 15) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
    if (-not (Get-Process -Name 'tailscaled' -ErrorAction SilentlyContinue)) { return $true }
    Start-Sleep -Milliseconds 200
  }
  return -not [bool](Get-Process -Name 'tailscaled' -ErrorAction SilentlyContinue)
}

function Test-SamePath([string]$Left, [string]$Right) {
  if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
  try {
    $Left = [System.Environment]::ExpandEnvironmentVariables($Left)
    $Right = [System.Environment]::ExpandEnvironmentVariables($Right)
    if (Test-Path -LiteralPath $Left) { $Left = (Get-Item -LiteralPath $Left).FullName }
    if (Test-Path -LiteralPath $Right) { $Right = (Get-Item -LiteralPath $Right).FullName }
    $Left = [System.IO.Path]::GetFullPath($Left)
    $Right = [System.IO.Path]::GetFullPath($Right)
  } catch { }
  return [string]::Equals($Left.TrimEnd('\'), $Right.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)
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

function Stop-ServiceAndWait([string]$Name, [int]$TimeoutSec = 30) {
  $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
  if (-not $service -or $service.Status -eq 'Stopped') { return $true }
  Stop-ServiceCompat -Name $Name | Out-Null
  return Wait-ServiceStatus -Name $Name -Status 'Stopped' -TimeoutSec $TimeoutSec
}

function Start-ServiceAndWait([string]$Name, [int]$TimeoutSec = 30) {
  $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
  if ($service -and $service.Status -eq 'Running') { return $true }
  Start-ServiceCompat -Name $Name | Out-Null
  return Wait-ServiceStatus -Name $Name -Status 'Running' -TimeoutSec $TimeoutSec
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

function Assert-ReleaseDigest([string]$Path, [string]$AssetName, [string]$Digest) {
  if ([string]::IsNullOrWhiteSpace($Digest)) {
    Write-Warn "No GitHub SHA-256 digest is published for $AssetName; relying on PE and version validation"
    return
  }
  if ($Digest -notmatch '^sha256:([0-9a-fA-F]{64})$') {
    throw "Unsupported digest for ${AssetName}: $Digest"
  }
  $expected = $Matches[1].ToLowerInvariant()
  $actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $expected) {
    throw "SHA-256 mismatch for $AssetName"
  }
  Write-Ok "SHA-256 verified: $AssetName"
}

function Get-BinaryVersion([string]$Path, [switch]$Daemon) {
  try {
    $output = if ($Daemon) { & $Path --version 2>&1 | Out-String } else { & $Path version 2>&1 | Out-String }
    if ($output -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
  } catch { }
  return $null
}

function Get-LiveDaemonVersion([string]$ClientPath) {
  try {
    $output = (& $ClientPath version --daemon 2>&1 | Out-String)
    if ($output -match '(?m)^Daemon:\s*v?(\d+\.\d+\.\d+)') {
      return $Matches[1]
    }
  } catch { }
  return $null
}
#endregion

#region Path Resolution and Official Install
# Resolve install paths
$LegacyCpsCounterDetected = Test-LegacyCpsCounterTag
$defaultDir = if ($InstallDir -and $InstallDir.Trim()) { $InstallDir } else { "$Env:ProgramFiles\Tailscale" }
$tsCmd = Get-Command tailscale.exe -ErrorAction SilentlyContinue
$tsPath = if ($tsCmd) { $tsCmd.Source } else { "$defaultDir\tailscale.exe" }
$tsdCmd = Get-Command tailscaled.exe -ErrorAction SilentlyContinue
$tsdPath = if ($tsdCmd) { $tsdCmd.Source } else { "$defaultDir\tailscaled.exe" }

# Use service-configured path if available
$svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
if ($svc) {
  $svcCfg = Get-CimInstance Win32_Service -Filter "Name='Tailscale'" -ErrorAction SilentlyContinue
  if (-not $svcCfg -or [string]::IsNullOrWhiteSpace($svcCfg.PathName)) {
    throw 'The existing Tailscale service command line could not be read safely'
  }
  $exePath = Get-SafeTailscaledServicePath -CommandLine $svcCfg.PathName
  $tsdPath = $exePath
  $defaultDir = Split-Path -Path $tsdPath -Parent
  $serviceClientPath = "$defaultDir\tailscale.exe"
  if ($tsCmd -and (Test-Path -LiteralPath $tsCmd.Source) -and -not (Test-SamePath -Left $tsCmd.Source -Right $serviceClientPath)) {
    throw "The active tailscale.exe is outside the managed service directory: $($tsCmd.Source). Fix PATH or remove that split installation before retrying."
  }
  $tsPath = $serviceClientPath
}
Assert-TailscaledProcessesManaged

# Detect fork version to match official Tailscale version
$officialVersion = $null
$forkTag = $Version
if ($Version -eq 'latest') {
  try {
    Write-Info "Detecting fork version..."
    if ($PreRelease) {
      $allReleases = @(Invoke-RestCompat -Uri "https://api.github.com/repos/$Repo/releases?per_page=100")
      $resp = Select-FirstItem -Value (Select-HighestVersionRelease -Releases $allReleases -Prerelease $true)
      if (-not $resp) {
        Write-Warn "No pre-release found, falling back to latest stable"
        $resp = Select-FirstItem -Value (Select-HighestVersionRelease -Releases $allReleases -Prerelease $false)
      }
    } else {
      $resp = Invoke-RestCompat -Uri "https://api.github.com/repos/$Repo/releases/latest"
    }
    $forkTag = Get-ReleaseTagName -Release $resp
    if (-not $forkTag) { throw 'No tag_name in response' }
    $officialVersion = Get-OfficialVersionFromTag -Tag $forkTag
    if ($officialVersion) {
      Write-Info "Fork version: $forkTag (official Tailscale: $officialVersion)"
    }
  } catch {
    Write-Err "Could not detect fork version: $($_.Exception.Message)"
    throw
  }
} else {
  $officialVersion = Get-OfficialVersionFromTag -Tag $Version
  if ($officialVersion) {
    Write-Info "Fork version: $forkTag (official Tailscale: $officialVersion)"
  }
}
if (-not $officialVersion) {
  Write-Err "Invalid release tag '$forkTag'; expected a tag beginning with vMAJOR.MINOR.PATCH"
  throw "Cannot determine the official Tailscale base version from '$forkTag'"
}

# Check if we need to install or upgrade official Tailscale
$existingGuiPaths = @(Get-TailscaleGuiPaths)
$hasExistingGui = $existingGuiPaths.Count -gt 0
$hasExistingCli = [bool](Get-Command tailscale.exe -ErrorAction SilentlyContinue)
if ($hasExistingGui -and -not $svc) {
  # Without a service path, keep GUI, CLI, and daemon in the same directory;
  # a stale tailscale.exe earlier on PATH must not split the installation.
  $defaultDir = Split-Path -Path $existingGuiPaths[0] -Parent
  $guiClientPath = Join-Path $defaultDir 'tailscale.exe'
  if ($tsCmd -and (Test-Path -LiteralPath $tsCmd.Source) -and -not (Test-SamePath -Left $tsCmd.Source -Right $guiClientPath)) {
    throw "The active tailscale.exe is outside the existing GUI directory: $($tsCmd.Source). Fix PATH or remove that split installation before retrying."
  }
  $tsPath = $guiClientPath
  $tsdPath = Join-Path $defaultDir 'tailscaled.exe'
  $hasExistingCli = Test-Path -LiteralPath $tsPath
}
$needsServiceCreate = -not [bool]$svc
$needsInstallOrUpgrade = $false
$hadExistingInstall = [bool]($hasExistingCli -or $svc -or $hasExistingGui)

if (-not $hasExistingCli -and -not $svc -and -not $hasExistingGui) {
  Write-Warn 'Tailscale not found. Installing official version...'
  $needsInstallOrUpgrade = $true
} elseif ($hasExistingGui) {
  # GUI and daemon must have the same official base version.
  $installedVersion = Get-InstalledTailscaleVersion
  if ($installedVersion) {
    if ($installedVersion -ne $officialVersion) {
      Write-Warn "Installed Tailscale GUI version ($installedVersion) differs from fork version ($officialVersion)"
      Write-Info "Will upgrade official Tailscale to $officialVersion to match fork"
      $needsInstallOrUpgrade = $true
    } else {
      Write-Info "Tailscale GUI version ($installedVersion) matches fork; will replace binaries only"
    }
  } else {
    Write-Warn 'The installed Tailscale GUI version could not be determined'
    Write-Info "Will reinstall the exact official Tailscale $officialVersion package before replacing binaries"
    $needsInstallOrUpgrade = $true
  }
} else {
  Write-Info 'CLI/service-only Tailscale found; will replace binaries without adding a GUI'
}

#endregion

#region Binary Download and Installation
# Resolve version and download URLs (reuse forkTag if already resolved)
if ($Version -eq 'latest') {
  if ($forkTag -and $forkTag -ne 'latest') {
    $Version = $forkTag
    Write-Info "Latest$(if ($PreRelease) { ' (pre-release)' }): $Version"
  } else {
    Write-Info 'Resolving latest release...'
    try {
      if ($PreRelease) {
        $allReleases = @(Invoke-RestCompat -Uri "https://api.github.com/repos/$Repo/releases?per_page=100")
        $resp = Select-FirstItem -Value (Select-HighestVersionRelease -Releases $allReleases -Prerelease $true)
        if (-not $resp) {
          Write-Warn "No pre-release found, falling back to latest stable"
          $resp = Select-FirstItem -Value (Select-HighestVersionRelease -Releases $allReleases -Prerelease $false)
        }
      } else {
        $resp = Invoke-RestCompat -Uri "https://api.github.com/repos/$Repo/releases/latest"
      }
      $Version = Get-ReleaseTagName -Release $resp
      if (-not $Version) { throw 'No tag_name in response' }
      Write-Info "Latest$(if ($PreRelease) { ' (pre-release)' }): $Version"
    } catch {
      Write-Err "Failed to resolve latest release: $($_.Exception.Message)"
      throw
    }
  }
}

# Try to resolve asset URLs from release
$tsUrl = $tsdUrl = $null
$tsDigest = $tsdDigest = $null
try {
  $rel = Invoke-RestCompat -Uri "https://api.github.com/repos/$Repo/releases/tags/$Version"
  $releaseMetadataTrusted = -not $script:LastRestUsedMirror
  $ap = if ($arch -eq 'amd64') { 'amd64|x86_64|x64' } else { 'arm64|aarch64' }
  $ts = $rel.assets | Where-Object { $_.name -match '(?i)^tailscale.*\.exe$' -and $_.name -notmatch '(?i)^tailscaled' -and $_.name -match '(?i)(windows|win)' -and $_.name -match "(?i)($ap)" } | Select-Object -First 1
  $tsd = $rel.assets | Where-Object { $_.name -match '(?i)^tailscaled.*\.exe$' -and $_.name -match '(?i)(windows|win)' -and $_.name -match "(?i)($ap)" } | Select-Object -First 1
  if ($ts -and $tsd) {
    $tsUrl = Add-MirrorPrefixToGitHubUrl -Uri $ts.browser_download_url
    $tsdUrl = Add-MirrorPrefixToGitHubUrl -Uri $tsd.browser_download_url
    if ($releaseMetadataTrusted) {
      $tsDigest = $ts.digest
      $tsdDigest = $tsd.digest
    } else {
      Write-Warn 'Release metadata came through the configured mirror; SHA-256 values from the same mirror are not treated as trusted'
    }
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

# Download, validate, replace, and start as one rollback-capable transaction.
$temp = New-Item -ItemType Directory -Path $env:TEMP -Name "ts-$([System.Guid]::NewGuid())"
$transactionStarted = $false
$binariesModified = $false
$preserveTemp = $false
$serviceCreated = $false
$serviceCommandChanged = $false
$svcBefore = $null
$serviceExistedBefore = $false
$serviceWasRunning = $false
$guiPathsBeforeTransaction = @()
$guiWasRunning = $false
$oldServicePathName = $null
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
    throw "Invalid binaries: tailscale=$($tsValid.Reason), tailscaled=$($tsdValid.Reason)"
  }

  $tsAssetName = if ($ts) { $ts.name } else { "tailscale-$platform.exe" }
  $tsdAssetName = if ($tsd) { $tsd.name } else { "tailscaled-$platform.exe" }
  Assert-ReleaseDigest -Path $tsFile -AssetName $tsAssetName -Digest $tsDigest
  Assert-ReleaseDigest -Path $tsdFile -AssetName $tsdAssetName -Digest $tsdDigest

  $expectedBinaryVersion = Get-OfficialVersionFromTag -Tag $Version
  $downloadedTsVersion = Get-BinaryVersion -Path $tsFile
  $downloadedTsdVersion = Get-BinaryVersion -Path $tsdFile -Daemon
  if (-not $expectedBinaryVersion -or $downloadedTsVersion -ne $expectedBinaryVersion -or $downloadedTsdVersion -ne $expectedBinaryVersion) {
    throw "Downloaded binary version mismatch: expected $expectedBinaryVersion, tailscale=$downloadedTsVersion, tailscaled=$downloadedTsdVersion"
  }
  Write-Ok 'Downloaded binaries passed PE, published-digest (when available), and version validation'

  # All fork assets are fully validated before an official MSI is allowed to
  # change GUI/service state. The post-MSI installation becomes the rollback
  # baseline for the binary replacement transaction below.
  if ($needsInstallOrUpgrade) {
    $installed = $false
    if ($EnableMsiFallback) {
      $msiRequiresRestart = $false
      $tmpMsi = $null
      $msiUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-$officialVersion-$arch.msi"
      try {
        Write-Info "Trying exact MSI installer from $msiUrl..."
        $tmpMsi = "$env:TEMP\tailscale-$([guid]::NewGuid()).msi"
        Invoke-WebRequestCompat -Uri $msiUrl -OutFile $tmpMsi
        $p = Start-Process msiexec.exe -ArgumentList @('/i', "`"$tmpMsi`"", '/qn', '/norestart') -Wait -PassThru
        if ($p.ExitCode -eq 3010) {
          $msiRequiresRestart = $true
        } elseif ($p.ExitCode -eq 0) {
          $guiPathsAfterMsi = @(Get-TailscaleGuiPaths)
          if ($guiPathsAfterMsi.Count -eq 0) {
            throw 'MSI completed without installing the Tailscale GUI'
          }
          $installedGuiVersion = Get-InstalledTailscaleVersion
          if ($installedGuiVersion -ne $officialVersion) {
            throw "MSI installed GUI version $installedGuiVersion, expected $officialVersion"
          }
          $installed = $true
        } else {
          throw "msiexec exited with code $($p.ExitCode)"
        }
      } catch {
        Write-Warn "Exact MSI installation failed for $msiUrl : $($_.Exception.Message)"
        $installed = $false
      } finally {
        if ($tmpMsi) { Remove-Item -Force $tmpMsi -ErrorAction SilentlyContinue }
      }
      if ($msiRequiresRestart) {
        Write-Err 'The exact Tailscale MSI requires a reboot. Reboot Windows, then rerun this installer; no fork binaries were installed.'
        throw 'Tailscale MSI returned 3010 (restart required)'
      }
    }

    # A fresh machine can use a CLI/service-only install. Never combine a
    # mismatched or partially installed GUI with newer fork binaries.
    if (-not $installed) {
      $guiPathsAfterFailure = @(Get-TailscaleGuiPaths)
      $serviceAfterFailure = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
      if ($hadExistingInstall -or $guiPathsAfterFailure.Count -gt 0 -or $serviceAfterFailure) {
        Write-Err "Cannot align the existing Tailscale GUI with fork version $officialVersion; no fork binaries were installed"
        throw 'Official Tailscale GUI alignment failed'
      }
      Write-Warn 'Falling back to minimal local install'
      New-Item -ItemType Directory -Force -Path $defaultDir | Out-Null
      $needsServiceCreate = $true
    }
  }

  $svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
  if ($svc) {
    $svcCfg = Get-CimInstance Win32_Service -Filter "Name='Tailscale'" -ErrorAction SilentlyContinue
    if (-not $svcCfg -or [string]::IsNullOrWhiteSpace($svcCfg.PathName)) {
      throw 'The Tailscale service command line could not be read safely after MSI alignment'
    }
    $tsdPath = Get-SafeTailscaledServicePath -CommandLine $svcCfg.PathName
    $defaultDir = Split-Path -Path $tsdPath -Parent
    $activeTsCmd = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    $serviceClientPath = "$defaultDir\tailscale.exe"
    if ($activeTsCmd -and (Test-Path -LiteralPath $activeTsCmd.Source) -and -not (Test-SamePath -Left $activeTsCmd.Source -Right $serviceClientPath)) {
      throw "The active tailscale.exe is outside the post-MSI service directory: $($activeTsCmd.Source). Fix PATH before retrying."
    }
    $tsPath = $serviceClientPath
  }
  Assert-TailscaledProcessesManaged

  $svcBefore = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
  $serviceExistedBefore = [bool]$svcBefore
  $serviceWasRunning = [bool]($svcBefore -and $svcBefore.Status -eq 'Running')
  $guiPathsBeforeTransaction = @(Get-TailscaleGuiPaths)
  $guiWasRunning = [bool](Get-Process -Name 'tailscale-ipn' -ErrorAction SilentlyContinue)
  if ($serviceExistedBefore) {
    $oldServiceCfg = Get-CimInstance Win32_Service -Filter "Name='Tailscale'" -ErrorAction SilentlyContinue
    if (-not $oldServiceCfg -or [string]::IsNullOrWhiteSpace($oldServiceCfg.PathName)) {
      throw 'The post-MSI Tailscale service command line could not be captured for rollback'
    }
    $oldServicePathName = $oldServiceCfg.PathName
  }

  New-Item -ItemType Directory -Force -Path (Split-Path $tsPath), (Split-Path $tsdPath) | Out-Null
  $backupDir = New-Item -ItemType Directory -Path $temp -Name 'backup'
  $tsExisted = Test-Path $tsPath
  $tsdExisted = Test-Path $tsdPath
  if ($tsExisted) { Copy-Item -Force $tsPath "$backupDir\tailscale.exe" }
  if ($tsdExisted) { Copy-Item -Force $tsdPath "$backupDir\tailscaled.exe" }

  $transactionStarted = $true
  if ($svcBefore -and $svcBefore.Status -ne 'Stopped') {
    Write-Info 'Stopping Tailscale service...'
    if (-not (Stop-ServiceAndWait -Name 'Tailscale' -TimeoutSec 60)) { throw 'Tailscale service did not stop within 60 seconds' }
  }
  if (-not (Wait-TailscaledProcessesAbsent -TimeoutSec 15)) {
    throw 'tailscaled.exe is still running 15 seconds after the managed service stopped; refusing to overwrite a live daemon'
  }
  Get-Process -Name 'tailscale','tailscale-ipn' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 800

  $binariesModified = $true
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

  $installedTsVersion = Get-BinaryVersion -Path $tsPath
  $installedTsdVersion = Get-BinaryVersion -Path $tsdPath -Daemon
  if ($installedTsVersion -ne $expectedBinaryVersion -or $installedTsdVersion -ne $expectedBinaryVersion) {
    throw "Installed binary version mismatch: expected $expectedBinaryVersion, tailscale=$installedTsVersion, tailscaled=$installedTsdVersion"
  }

  $svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
  if ($needsServiceCreate -and -not $svc) {
    Write-Info 'Registering Tailscale service with upstream dependencies and recovery policy...'
    $daemonInstall = Start-Process -FilePath $tsdPath -ArgumentList @('install-system-daemon') -NoNewWindow -Wait -PassThru
    $serviceAppeared = Wait-ServiceExists -Name 'Tailscale' -TimeoutSec 15
    if (-not $serviceExistedBefore -and ($serviceAppeared -or (Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue))) { $serviceCreated = $true }
    if ($daemonInstall.ExitCode -ne 0) {
      throw "tailscaled install-system-daemon failed with exit code $($daemonInstall.ExitCode)"
    }
    if (-not $serviceAppeared) { throw 'tailscaled did not register the Tailscale service' }
    $svc = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
  }
  if (-not $svc) { throw 'Tailscale service is unavailable after binary installation' }

  $configuredService = Get-CimInstance Win32_Service -Filter "Name='Tailscale'" -ErrorAction Stop
  $configuredExe = Get-SafeTailscaledServicePath -CommandLine $configuredService.PathName
  if (-not (Test-SamePath -Left $configuredExe -Right $tsdPath)) {
    if ($serviceExistedBefore -and [string]::IsNullOrWhiteSpace($oldServicePathName)) {
      throw 'Cannot safely update the existing service because its previous command line is unavailable'
    }
    $previousServiceArguments = if ($serviceExistedBefore) { Get-ArgumentsFromCommandLine -CommandLine $oldServicePathName } else { '' }
    $desiredServicePathName = "`"$tsdPath`""
    if (-not [string]::IsNullOrWhiteSpace($previousServiceArguments)) {
      $desiredServicePathName += " $previousServiceArguments"
    }
    & sc.exe config Tailscale binPath= $desiredServicePathName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "sc.exe config failed with exit code $LASTEXITCODE" }
    if ($serviceExistedBefore) { $serviceCommandChanged = $true }
    $configuredService = Get-CimInstance Win32_Service -Filter "Name='Tailscale'" -ErrorAction Stop
    $configuredExe = Get-SafeTailscaledServicePath -CommandLine $configuredService.PathName
    if ($serviceExistedBefore) {
      $configuredArguments = Get-ArgumentsFromCommandLine -CommandLine $configuredService.PathName
      if (-not [string]::Equals($configuredArguments, $previousServiceArguments, [System.StringComparison]::Ordinal)) {
        throw 'Service executable arguments changed while updating its path'
      }
    }
  }
  if (-not (Test-SamePath -Left $configuredExe -Right $tsdPath)) {
    throw "Service path verification failed: expected $tsdPath, got $configuredExe"
  }

  Write-Info 'Starting Tailscale service...'
  if (-not (Start-ServiceAndWait -Name 'Tailscale' -TimeoutSec 30)) {
    throw 'Tailscale service did not reach Running state within 30 seconds'
  }
  $liveDaemonVersion = Get-LiveDaemonVersion -ClientPath $tsPath
  if ($liveDaemonVersion -ne $expectedBinaryVersion) {
    throw "Live daemon version mismatch: expected $expectedBinaryVersion, got $liveDaemonVersion"
  }
  Write-Ok "Binaries installed and live daemon verified at $liveDaemonVersion"
} catch {
  $installError = $_
  if ($transactionStarted) {
    Write-Warn 'Installation failed after replacement began; restoring previous binaries and service state'
    $rollbackFailed = $false
    $guiRestoreFailed = $false
    $serviceSafeForFiles = $true
    $canRestartPreviousService = $true
    $currentService = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue

    # install-system-daemon may create the service and then fail before the
    # success path records it. Never mistake that partial service for a
    # pre-existing installation during rollback.
    if (-not $serviceExistedBefore -and $currentService) {
      $serviceCreated = $true
    }

    if ($serviceCreated) {
      $createdServiceStopped = $true
      if ($currentService -and $currentService.Status -ne 'Stopped') {
        if (-not (Stop-ServiceAndWait -Name 'Tailscale' -TimeoutSec 30)) {
          Write-Err 'Could not stop the newly created service during rollback'
          $rollbackFailed = $true
          $serviceSafeForFiles = $false
          $canRestartPreviousService = $false
          $createdServiceStopped = $false
        }
      }

      if ($createdServiceStopped) {
        $daemonUninstallExit = -1
        if (Test-Path -LiteralPath $tsdPath) {
          try {
            $daemonUninstall = Start-Process -FilePath $tsdPath -ArgumentList @('uninstall-system-daemon') -NoNewWindow -Wait -PassThru
            $daemonUninstallExit = $daemonUninstall.ExitCode
          } catch {
            Write-Warn "tailscaled uninstall-system-daemon could not run: $($_.Exception.Message)"
          }
        }
        if ($daemonUninstallExit -ne 0 -or -not (Wait-ServiceAbsent -Name 'Tailscale' -TimeoutSec 15)) {
          & sc.exe delete Tailscale | Out-Null
          if ($LASTEXITCODE -ne 0 -and (Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue)) {
            Write-Err "Could not remove the newly created service (exit $LASTEXITCODE)"
          }
        }
        if (-not (Wait-ServiceAbsent -Name 'Tailscale' -TimeoutSec 30)) {
          Write-Err 'The newly created service is still registered after rollback'
          $rollbackFailed = $true
          $serviceSafeForFiles = $false
        }
      }
    } elseif ($serviceExistedBefore -and ($binariesModified -or $serviceCommandChanged)) {
      $currentService = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
      if ($currentService -and $currentService.Status -ne 'Stopped') {
        if (-not (Stop-ServiceAndWait -Name 'Tailscale' -TimeoutSec 30)) {
          Write-Err 'Could not stop the existing service to restore its previous binaries'
          $rollbackFailed = $true
          $serviceSafeForFiles = $false
          $canRestartPreviousService = $false
        }
      }
    }

    if ($serviceSafeForFiles -and -not (Wait-TailscaledProcessesAbsent -TimeoutSec 15)) {
      Write-Err 'A tailscaled.exe process is still running; binary restoration was skipped to avoid overwriting a live executable'
      $rollbackFailed = $true
      $serviceSafeForFiles = $false
      $canRestartPreviousService = $false
    }

    if ($binariesModified -and $serviceSafeForFiles) {
      try {
        if ($tsExisted) { Copy-Item -Force "$backupDir\tailscale.exe" $tsPath } else { Remove-Item -Force $tsPath -ErrorAction SilentlyContinue }
        if (-not $tsExisted -and (Test-Path $tsPath)) { throw "File still exists: $tsPath" }
      } catch {
        Write-Err "Could not restore tailscale.exe: $($_.Exception.Message)"
        $rollbackFailed = $true
        $canRestartPreviousService = $false
      }
      try {
        if ($tsdExisted) { Copy-Item -Force "$backupDir\tailscaled.exe" $tsdPath } else { Remove-Item -Force $tsdPath -ErrorAction SilentlyContinue }
        if (-not $tsdExisted -and (Test-Path $tsdPath)) { throw "File still exists: $tsdPath" }
      } catch {
        Write-Err "Could not restore tailscaled.exe: $($_.Exception.Message)"
        $rollbackFailed = $true
        $canRestartPreviousService = $false
      }
    } elseif ($binariesModified) {
      Write-Err 'Skipped binary restoration because the service could not be stopped or removed'
      $rollbackFailed = $true
      $canRestartPreviousService = $false
    }

    $serviceAfterFileRestore = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
    if ($serviceExistedBefore -and -not $serviceAfterFileRestore) {
      Write-Err 'The previous service disappeared during rollback'
      $rollbackFailed = $true
      $canRestartPreviousService = $false
    }

    if ($serviceCommandChanged -and $serviceExistedBefore -and $serviceAfterFileRestore) {
      if ([string]::IsNullOrWhiteSpace($oldServicePathName)) {
        Write-Err 'Could not restore the previous service command line because it was not captured'
        $rollbackFailed = $true
        $canRestartPreviousService = $false
      } else {
        & sc.exe config Tailscale binPath= $oldServicePathName | Out-Null
        if ($LASTEXITCODE -ne 0) {
          Write-Err "Could not restore the previous service command line (exit $LASTEXITCODE)"
          $rollbackFailed = $true
          $canRestartPreviousService = $false
        } else {
          $restoredService = Get-CimInstance Win32_Service -Filter "Name='Tailscale'" -ErrorAction SilentlyContinue
          $restoredExe = if ($restoredService) { Get-ExePathFromCommandLine -CommandLine $restoredService.PathName } else { $null }
          $oldServiceExe = Get-ExePathFromCommandLine -CommandLine $oldServicePathName
          $restoredArguments = if ($restoredService) { Get-ArgumentsFromCommandLine -CommandLine $restoredService.PathName } else { '' }
          $oldServiceArguments = Get-ArgumentsFromCommandLine -CommandLine $oldServicePathName
          if (-not $restoredService -or -not (Test-SamePath -Left $restoredExe -Right $oldServiceExe) -or -not [string]::Equals($restoredArguments, $oldServiceArguments, [System.StringComparison]::Ordinal)) {
            Write-Err 'The previous service command line did not verify after rollback'
            $rollbackFailed = $true
            $canRestartPreviousService = $false
          }
        }
      }
    }

    if ($serviceWasRunning -and $serviceExistedBefore -and $canRestartPreviousService) {
      $restoredServiceState = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
      if (-not $restoredServiceState) {
        $rollbackFailed = $true
      } elseif (-not (Start-ServiceAndWait -Name 'Tailscale' -TimeoutSec 30)) {
        Write-Err 'Previous binaries were restored, but the previous service could not be restarted'
        $rollbackFailed = $true
      }
    }
    if ($guiWasRunning -and $canRestartPreviousService -and -not (Get-Process -Name 'tailscale-ipn' -ErrorAction SilentlyContinue)) {
      $previousGuiPath = Select-FirstItem -Value ($guiPathsBeforeTransaction | Where-Object { Test-Path -LiteralPath $_ })
      if ($previousGuiPath) {
        try {
          Start-Process -FilePath $previousGuiPath -WindowStyle Hidden -ErrorAction Stop
        } catch {
          Write-Err "Previous binaries and service were restored, but the GUI could not be relaunched: $($_.Exception.Message)"
          $guiRestoreFailed = $true
        }
      } else {
        Write-Err 'Previous binaries and service were restored, but the prior GUI executable is no longer available'
        $guiRestoreFailed = $true
      }
    }
    if ($rollbackFailed) {
      $preserveTemp = $true
      Write-Err "Rollback was incomplete; recovery copies are preserved in $backupDir"
    }
    if ($guiRestoreFailed) {
      Write-Err 'Rollback could not restore the previous GUI process; launch tailscale-ipn.exe manually after resolving the installation error'
    }
  }
  throw $installError
} finally {
  if (-not $preserveTemp) {
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
  }
}
#endregion

#region Launch GUI
Write-Info 'Launching Tailscale GUI client (if available)...'
$guiPaths = @(Get-TailscaleGuiPaths)
$ipnPath = Select-FirstItem -Value $guiPaths
if ($ipnPath) {
  try {
    # Do not redirect a long-running GUI to temporary files: Windows keeps the
    # handles open for the lifetime of the tray process and the files leak.
    Start-Process -FilePath $ipnPath -WindowStyle Hidden -ErrorAction Stop
    Write-Ok 'Tailscale GUI launched'
  } catch {
    Write-Warn "Failed to launch GUI: $($_.Exception.Message)"
  }
} else {
  Write-Warn 'Tailscale GUI (tailscale-ipn.exe) not found; skipping launch'
}
#endregion

Write-Host ''
Write-Host 'Quick Start:'
Write-Host '  tailscale up'
Write-Host ''
Show-AwgGuidance -ReleaseTag $Version -LegacyCounterDetected $LegacyCpsCounterDetected
Write-Host ''
