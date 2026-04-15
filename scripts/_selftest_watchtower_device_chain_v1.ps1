param(
  [Parameter(Mandatory=$true)]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WT-Die([string]$m){
  throw ("WATCHTOWER_DEVICE_CHAIN_SELFTEST_FAIL: " + $m)
}

function WT-EnsureString([object]$v){
  if($null -eq $v){ return "" }
  return [string]$v
}

function WT-ReadUtf8NoBomLf([string]$Path){
  return [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8).Replace("`r`n","`n").Replace("`r","`n")
}

function WT-WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = (WT-EnsureString $Text).Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function WT-Sha256HexBytes([byte[]]$b){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($b)) -replace "-","").ToLowerInvariant()
  }
  finally {
    $sha.Dispose()
  }
}

function WT-Sha256HexText([string]$Text){
  $t = (WT-EnsureString $Text).Replace("`r`n","`n").Replace("`r","`n")
  return WT-Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($t))
}

function WT-InvokeChild([string]$PSExe,[string]$File,[string[]]$ScriptArgs){
  $oldPref = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    $argList = @(
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy","Bypass",
      "-File",$File
    ) + @($ScriptArgs)
    $output = & $PSExe @argList 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $oldPref
  }

  $txt = ""
  if($null -ne $output){
    $txt = (($output | ForEach-Object { [string]$_ }) -join "`n")
    $txt = ($txt -replace "`r`n","`n") -replace "`r","`n"
  }

  return [pscustomobject]@{
    ExitCode = $exitCode
    Output = $txt
  }
}

function WT-VerifyDeviceChain([string]$EventsPath){
  if(-not (Test-Path -LiteralPath $EventsPath -PathType Leaf)){
    WT-Die ("MISSING_EVENTS_FILE: " + $EventsPath)
  }

  $raw = WT-ReadUtf8NoBomLf $EventsPath
  $lines = @($raw -split "`n" | Where-Object { $_ -and $_.Trim().Length -gt 0 })

  if($lines.Count -lt 2){
    WT-Die "INSUFFICIENT_EVENTS_FOR_CHAIN_TEST"
  }

  $prevHash = ""
  for($i = 0; $i -lt $lines.Count; $i++){
    $line = [string]$lines[$i]
    $obj = $line | ConvertFrom-Json

    $schema = WT-EnsureString $obj.schema
    if($schema -ne "watchtower.device_event.v1"){
      WT-Die ("BAD_EVENT_SCHEMA_AT_INDEX_" + $i + ": " + $schema)
    }

    $storedPrev = WT-EnsureString $obj.prev_event_hash
    if($storedPrev -ne $prevHash){
      WT-Die ("CHAIN_MISMATCH_AT_INDEX_" + $i)
    }

    $prevHash = WT-Sha256HexText $line
  }

  return $true
}

if($RepoRoot -is [System.IO.FileSystemInfo]){
  $RepoRoot = $RepoRoot.FullName
} elseif($RepoRoot -is [array]){
  if($RepoRoot.Count -eq 0){ WT-Die "EMPTY_REPO_ROOT_ARG" }
  $RepoRoot = $RepoRoot[0]
}
$RepoRoot = [string]$RepoRoot

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  WT-Die ("INVALID_REPO_ROOT: " + $RepoRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$Bootstrap = Join-Path $RepoRoot "scripts\watchtower_device_bootstrap_v1.ps1"
$Append = Join-Path $RepoRoot "scripts\watchtower_append_device_event_v1.ps1"

if(-not (Test-Path -LiteralPath $Bootstrap -PathType Leaf)){ WT-Die "MISSING_BOOTSTRAP_SCRIPT" }
if(-not (Test-Path -LiteralPath $Append -PathType Leaf)){ WT-Die "MISSING_APPEND_SCRIPT" }

$ScratchRoot = Join-Path $RepoRoot "proofs\scratch\watchtower_device_chain_selftest"
if(Test-Path -LiteralPath $ScratchRoot -PathType Container){
  Remove-Item -LiteralPath $ScratchRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $ScratchRoot | Out-Null

$deviceRoot = Join-Path $ScratchRoot "device_under_test"

Write-Host "DEVICE_CHAIN_PHASE:BOOTSTRAP" -ForegroundColor Yellow
$r = WT-InvokeChild $PSExe $Bootstrap @(
  "-RepoRoot",$RepoRoot,
  "-DevicePubKey","ssh-ed25519 AAAATESTDEVICEKEY watchtower-device-chain-selftest",
  "-HardwareFingerprint","hwfp-chain-selftest-001",
  "-Manufacturer","Lenovo",
  "-Serial","SN-CHAIN-001",
  "-OsFamily","windows",
  "-FirstSeenUtc","2026-03-01T00:00:00Z",
  "-ProvisioningPolicyHash","policyhash-chain-selftest-001",
  "-TrustLevel","T1",
  "-Status","enrolled",
  "-DeviceRoot",$deviceRoot
)
if($r.ExitCode -ne 0){ WT-Die ("BOOTSTRAP_FAILED: " + $r.Output) }
if($r.Output -notmatch 'WATCHTOWER_DEVICE_BOOTSTRAP_OK'){ WT-Die "BOOTSTRAP_TOKEN_MISSING" }

Write-Host "DEVICE_CHAIN_PHASE:APPEND_1" -ForegroundColor Yellow
$r = WT-InvokeChild $PSExe $Append @(
  "-RepoRoot",$RepoRoot,
  "-DeviceRoot",$deviceRoot,
  "-EventType","device.enrolled",
  "-ObservedUtc","2026-03-01T00:05:00Z",
  "-PayloadHash","payloadhash-chain-001",
  "-PolicyHash","policyhash-chain-selftest-001",
  "-Status","ok"
)
if($r.ExitCode -ne 0){ WT-Die ("APPEND_1_FAILED: " + $r.Output) }
if($r.Output -notmatch 'WATCHTOWER_APPEND_DEVICE_EVENT_OK'){ WT-Die "APPEND_1_TOKEN_MISSING" }

Write-Host "DEVICE_CHAIN_PHASE:APPEND_2" -ForegroundColor Yellow
$r = WT-InvokeChild $PSExe $Append @(
  "-RepoRoot",$RepoRoot,
  "-DeviceRoot",$deviceRoot,
  "-EventType","device.heartbeat",
  "-ObservedUtc","2026-03-01T00:10:00Z",
  "-PayloadHash","payloadhash-chain-002",
  "-PolicyHash","policyhash-chain-selftest-001",
  "-Status","ok"
)
if($r.ExitCode -ne 0){ WT-Die ("APPEND_2_FAILED: " + $r.Output) }
if($r.Output -notmatch 'WATCHTOWER_APPEND_DEVICE_EVENT_OK'){ WT-Die "APPEND_2_TOKEN_MISSING" }

$eventsPath = Join-Path $deviceRoot "events.ndjson"

Write-Host "DEVICE_CHAIN_PHASE:VERIFY_GOOD" -ForegroundColor Yellow
[void](WT-VerifyDeviceChain $eventsPath)
Write-Host "WATCHTOWER_DEVICE_CHAIN_OK" -ForegroundColor Green

Write-Host "DEVICE_CHAIN_PHASE:TAMPER" -ForegroundColor Yellow
$raw = WT-ReadUtf8NoBomLf $eventsPath
$lines = @($raw -split "`n" | Where-Object { $_ -and $_.Trim().Length -gt 0 })
if($lines.Count -lt 2){ WT-Die "TAMPER_PRECONDITION_FAILED" }

$firstObj = $lines[0] | ConvertFrom-Json
$firstObj.status = "tampered"
$lines[0] = ($firstObj | ConvertTo-Json -Compress -Depth 20)

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($eventsPath,$lines,$enc)

Write-Host "DEVICE_CHAIN_PHASE:VERIFY_TAMPER" -ForegroundColor Yellow
$detected = $false
try {
  [void](WT-VerifyDeviceChain $eventsPath)
}
catch {
  $msg = [string]$_.Exception.Message
  if($msg -match 'CHAIN_MISMATCH_AT_INDEX_'){
    $detected = $true
  }
  else {
    throw
  }
}

if(-not $detected){
  WT-Die "TAMPER_NOT_DETECTED"
}

Write-Host "WATCHTOWER_DEVICE_CHAIN_TAMPER_DETECTED" -ForegroundColor Green
Write-Host "WATCHTOWER_DEVICE_CHAIN_SELFTEST_OK" -ForegroundColor Green
