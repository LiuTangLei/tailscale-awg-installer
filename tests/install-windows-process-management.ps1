[CmdletBinding()]
param(
  [string]$InstallerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'install-windows.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedInstallerPath = (Resolve-Path -LiteralPath $InstallerPath).Path
$tokens = $null
$parseErrors = $null
$script:InstallerAst = [System.Management.Automation.Language.Parser]::ParseFile(
  $resolvedInstallerPath,
  [ref]$tokens,
  [ref]$parseErrors
)
if ($parseErrors.Count -ne 0) {
  $details = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
  throw "PowerShell parser errors in ${resolvedInstallerPath}: $details"
}

function Import-InstallerFunction([string]$Name) {
  $matches = @($script:InstallerAst.FindAll({
    param($node)
    return ($node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name)
  }, $true))
  if ($matches.Count -ne 1) {
    throw "Expected exactly one function named '$Name' in $resolvedInstallerPath; found $($matches.Count)"
  }

  # Define only the selected function body in this test script's scope. This
  # avoids executing the installer's top-level download and service mutations.
  $definition = $matches[0].Extent.Text
  $pattern = '(?i)^\s*function\s+' + [regex]::Escape($Name)
  $definition = [regex]::Replace($definition, $pattern, "function script:$Name", 1)
  Invoke-Expression $definition
}

Import-InstallerFunction -Name 'Get-TailscaledProcessValidationError'
Import-InstallerFunction -Name 'Assert-TailscaledProcessesManaged'
Import-InstallerFunction -Name 'Wait-TailscaledProcessesAbsent'

$script:ExpectedServicePath = 'C:\Program Files\Tailscale\tailscaled.exe'

# These two helpers isolate the process-tree policy from filesystem/path
# semantics so this test can also run under PowerShell Core on non-Windows CI.
function script:Get-SafeTailscaledServicePath([string]$CommandLine) {
  return $script:ExpectedServicePath
}

function script:Test-SamePath([string]$Left, [string]$Right) {
  if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
    return $false
  }
  $normalizedLeft = $Left.Replace('/', '\').TrimEnd('\')
  $normalizedRight = $Right.Replace('/', '\').TrimEnd('\')
  return [string]::Equals(
    $normalizedLeft,
    $normalizedRight,
    [System.StringComparison]::OrdinalIgnoreCase
  )
}

function New-TestService([uint32]$ProcessId) {
  return [pscustomobject]@{
    ProcessId = $ProcessId
    PathName = '"C:\Program Files\Tailscale\tailscaled.exe"'
  }
}

function New-TestProcess([uint32]$ProcessId, [uint32]$ParentProcessId, [AllowNull()][string]$ExecutablePath) {
  return [pscustomobject]@{
    ProcessId = $ProcessId
    ParentProcessId = $ParentProcessId
    ExecutablePath = $ExecutablePath
  }
}

$script:CimServiceResults = New-Object System.Collections.Queue
$script:CimProcessResults = New-Object System.Collections.Queue
$script:ProcessLookupResults = New-Object System.Collections.Queue
$script:SleepCallCount = 0

function script:Get-CimInstance {
  param(
    [string]$ClassName,
    [string]$Filter,
    $ErrorAction
  )

  if ($ClassName -eq 'Win32_Service') {
    if ($script:CimServiceResults.Count -eq 0) {
      throw 'The test did not provide enough Win32_Service snapshots'
    }
    return $script:CimServiceResults.Dequeue()
  }
  if ($ClassName -eq 'Win32_Process') {
    if ($script:CimProcessResults.Count -eq 0) {
      throw 'The test did not provide enough Win32_Process snapshots'
    }
    return $script:CimProcessResults.Dequeue()
  }
  throw "Unexpected CIM class in test: $ClassName"
}

function script:Get-Process {
  param(
    [string[]]$Name,
    $ErrorAction
  )
  if ($script:ProcessLookupResults.Count -eq 0) { return $null }
  return $script:ProcessLookupResults.Dequeue()
}

function script:Start-Sleep {
  param(
    [int]$Milliseconds,
    [int]$Seconds
  )
  $script:SleepCallCount++
}

function Reset-TestDoubles {
  $script:CimServiceResults.Clear()
  $script:CimProcessResults.Clear()
  $script:ProcessLookupResults.Clear()
  $script:SleepCallCount = 0
}

function Assert-Null($Actual, [string]$Message) {
  if ($null -ne $Actual) {
    throw "$Message. Expected no validation error, got: $Actual"
  }
}

function Assert-True([bool]$Actual, [string]$Message) {
  if (-not $Actual) { throw "$Message. Expected true, got false" }
}

function Assert-False([bool]$Actual, [string]$Message) {
  if ($Actual) { throw "$Message. Expected false, got true" }
}

function Assert-Equal($Expected, $Actual, [string]$Message) {
  if ($Expected -ne $Actual) {
    throw "$Message. Expected '$Expected', got '$Actual'"
  }
}

function Assert-Matches([string]$Pattern, [string]$Actual, [string]$Message) {
  if ($Actual -notmatch $Pattern) {
    throw "$Message. '$Actual' does not match '$Pattern'"
  }
}

function Assert-ThrowsMatches([scriptblock]$Body, [string]$Pattern, [string]$Message) {
  $exceptionMessage = $null
  try {
    & $Body
  } catch {
    $exceptionMessage = $_.Exception.Message
  }
  if ([string]::IsNullOrWhiteSpace([string]$exceptionMessage)) {
    throw "$Message. Expected an exception, but none was thrown"
  }
  Assert-Matches -Pattern $Pattern -Actual $exceptionMessage -Message $Message
}

$script:Passed = 0
$script:Failed = 0

function Invoke-Test([string]$Name, [scriptblock]$Body) {
  Reset-TestDoubles
  try {
    & $Body
    $script:Passed++
    Write-Host "[PASS] $Name"
  } catch {
    $script:Failed++
    Write-Host "[FAIL] $Name" -ForegroundColor Red
    Write-Host "       $($_.Exception.Message)" -ForegroundColor Red
  }
}

Invoke-Test 'accepts the service root and its /subproc child' {
  $service = New-TestService -ProcessId 100
  $processes = @(
    (New-TestProcess -ProcessId 100 -ParentProcessId 4 -ExecutablePath $script:ExpectedServicePath),
    (New-TestProcess -ProcessId 110 -ParentProcessId 100 -ExecutablePath $script:ExpectedServicePath)
  )
  $errorText = Get-TailscaledProcessValidationError -Processes $processes -Service $service
  Assert-Null -Actual $errorText -Message 'A normal /subproc child must be accepted'
}

Invoke-Test 'accepts an empty snapshot when no service is running' {
  $errorText = Get-TailscaledProcessValidationError -Processes @() -Service $null
  Assert-Null -Actual $errorText -Message 'No service and no daemon processes is a safe state'
}

Invoke-Test 'rejects an empty process snapshot for a nonzero service PID' {
  $service = New-TestService -ProcessId 150
  $errorText = Get-TailscaledProcessValidationError -Processes @() -Service $service
  Assert-Matches -Pattern 'reports PID 150, but no tailscaled\.exe process could be inspected' -Actual $errorText -Message 'A missing live service process must fail closed'
}

Invoke-Test 'accepts a /firewall descendant below /subproc' {
  $service = New-TestService -ProcessId 200
  # Put the grandchild first to exercise repeated descendant-closure passes.
  $processes = @(
    (New-TestProcess -ProcessId 220 -ParentProcessId 210 -ExecutablePath $script:ExpectedServicePath),
    (New-TestProcess -ProcessId 200 -ParentProcessId 4 -ExecutablePath $script:ExpectedServicePath),
    (New-TestProcess -ProcessId 210 -ParentProcessId 200 -ExecutablePath $script:ExpectedServicePath)
  )
  $errorText = Get-TailscaledProcessValidationError -Processes $processes -Service $service
  Assert-Null -Actual $errorText -Message 'The service-owned /firewall descendant must be accepted'
}

Invoke-Test 'accepts managed descendants when CIM omits ExecutablePath' {
  $service = New-TestService -ProcessId 300
  $processes = @(
    (New-TestProcess -ProcessId 300 -ParentProcessId 4 -ExecutablePath $null),
    (New-TestProcess -ProcessId 310 -ParentProcessId 300 -ExecutablePath ''),
    (New-TestProcess -ProcessId 320 -ParentProcessId 310 -ExecutablePath '   ')
  )
  $errorText = Get-TailscaledProcessValidationError -Processes $processes -Service $service
  Assert-Null -Actual $errorText -Message 'Missing ExecutablePath alone must not reject a service-owned process'
}

Invoke-Test 'rejects an independent same-path tailscaled root' {
  $service = New-TestService -ProcessId 400
  $processes = @(
    (New-TestProcess -ProcessId 400 -ParentProcessId 4 -ExecutablePath $script:ExpectedServicePath),
    (New-TestProcess -ProcessId 499 -ParentProcessId 4 -ExecutablePath $script:ExpectedServicePath)
  )
  $errorText = Get-TailscaledProcessValidationError -Processes $processes -Service $service
  Assert-Matches -Pattern 'extra unmanaged.*PID 499' -Actual $errorText -Message 'An independent daemon must remain fail-closed'
}

Invoke-Test 'rejects a service descendant running from another path' {
  $service = New-TestService -ProcessId 500
  $processes = @(
    (New-TestProcess -ProcessId 500 -ParentProcessId 4 -ExecutablePath $script:ExpectedServicePath),
    (New-TestProcess -ProcessId 510 -ParentProcessId 500 -ExecutablePath 'C:\Temp\tailscaled.exe')
  )
  $errorText = Get-TailscaledProcessValidationError -Processes $processes -Service $service
  Assert-Matches -Pattern 'descendant uses an unexpected executable path \(PID 510\)' -Actual $errorText -Message 'A wrong-path descendant must be rejected'
}

Invoke-Test 'retries when the service PID changes during the snapshot' {
  $script:CimServiceResults.Enqueue((New-TestService -ProcessId 600))
  $script:CimServiceResults.Enqueue((New-TestService -ProcessId 601))
  $script:CimServiceResults.Enqueue((New-TestService -ProcessId 700))
  $script:CimServiceResults.Enqueue((New-TestService -ProcessId 700))
  $script:CimProcessResults.Enqueue(@(
    (New-TestProcess -ProcessId 600 -ParentProcessId 4 -ExecutablePath $script:ExpectedServicePath)
  ))
  $script:CimProcessResults.Enqueue(@(
    (New-TestProcess -ProcessId 700 -ParentProcessId 4 -ExecutablePath $script:ExpectedServicePath),
    (New-TestProcess -ProcessId 710 -ParentProcessId 700 -ExecutablePath $script:ExpectedServicePath)
  ))

  Assert-TailscaledProcessesManaged
  Assert-Equal -Expected 1 -Actual $script:SleepCallCount -Message 'A changed service PID should cause exactly one retry delay'
  Assert-Equal -Expected 0 -Actual $script:CimServiceResults.Count -Message 'The stable retry service snapshots should be consumed'
  Assert-Equal -Expected 0 -Actual $script:CimProcessResults.Count -Message 'The stable retry process snapshot should be consumed'
}

Invoke-Test 'throws after three unstable service snapshots' {
  $script:CimServiceResults.Enqueue((New-TestService -ProcessId 800))
  $script:CimServiceResults.Enqueue((New-TestService -ProcessId 801))
  $script:CimServiceResults.Enqueue((New-TestService -ProcessId 810))
  $script:CimServiceResults.Enqueue((New-TestService -ProcessId 811))
  $script:CimServiceResults.Enqueue((New-TestService -ProcessId 820))
  $script:CimServiceResults.Enqueue((New-TestService -ProcessId 821))
  $script:CimProcessResults.Enqueue(@(
    (New-TestProcess -ProcessId 800 -ParentProcessId 4 -ExecutablePath $script:ExpectedServicePath)
  ))
  $script:CimProcessResults.Enqueue(@(
    (New-TestProcess -ProcessId 810 -ParentProcessId 4 -ExecutablePath $script:ExpectedServicePath)
  ))
  $script:CimProcessResults.Enqueue(@(
    (New-TestProcess -ProcessId 820 -ParentProcessId 4 -ExecutablePath $script:ExpectedServicePath)
  ))

  Assert-ThrowsMatches -Body { Assert-TailscaledProcessesManaged } -Pattern 'service restarted while its processes were being inspected' -Message 'Repeated PID races must fail closed after the retry limit'
  Assert-Equal -Expected 2 -Actual $script:SleepCallCount -Message 'Three attempts should have two retry delays'
}

Invoke-Test 'waits for delayed tailscaled process exit' {
  $script:ProcessLookupResults.Enqueue([pscustomobject]@{ Id = 800 })
  $script:ProcessLookupResults.Enqueue([pscustomobject]@{ Id = 800 })
  $script:ProcessLookupResults.Enqueue($null)

  $result = Wait-TailscaledProcessesAbsent -TimeoutSec 5
  Assert-True -Actual $result -Message 'The wait should succeed after a delayed process exit'
  Assert-Equal -Expected 2 -Actual $script:SleepCallCount -Message 'The wait should poll until the process disappears'
}

Invoke-Test 'returns false when tailscaled remains at timeout' {
  $script:ProcessLookupResults.Enqueue([pscustomobject]@{ Id = 900 })

  $result = Wait-TailscaledProcessesAbsent -TimeoutSec 0
  Assert-False -Actual $result -Message 'The wait must fail closed when the process is still present at timeout'
  Assert-Equal -Expected 0 -Actual $script:SleepCallCount -Message 'A zero-second timeout should perform only the final check'
}

Write-Host ''
Write-Host "Passed: $($script:Passed); Failed: $($script:Failed)"
if ($script:Failed -ne 0) {
  throw "$($script:Failed) Windows process-management regression test(s) failed"
}
