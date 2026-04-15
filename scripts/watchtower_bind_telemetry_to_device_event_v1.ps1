param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TelemetryPath,
  [string]$DevicesRoot = "",
  [string]$PolicyHash = "",
  [string]$Status = "ok"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WT-Die([string]$m){ throw ("WATCHTOWER_BIND_TELEMETRY_FAIL: " + $m) }

function WT-EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function WT-EnsureString([object]$v){
  if($null -eq $v){ return "" }
  return [string]$v
}

function WT-AppendNdjson([string]$Path,[string]$Line){
  $dir = Split-Path -Parent $Path
  if($dir){ WT-EnsureDir $dir }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = (WT-EnsureString $Line).Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::AppendAllText($Path,$t,$enc)
}

function WT-ReadUtf8NoBomLf([string]$Path){
  return [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8).Replace("`r`n","`n").Replace("`r","`n")
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

function WT-CanonicalJson([hashtable]$Map){
  $keys = New-Object System.Collections.Generic.List[string]
  foreach($k in $Map.Keys){ [void]$keys.Add([string]$k) }
  $keys.Sort()

  $parts = New-Object System.Collections.Generic.List[string]
  foreach($k in $keys){
    $nameJson = ConvertTo-Json ([string]$k) -Compress
    $valJson  = ConvertTo-Json $Map[$k] -Compress -Depth 20
    [void]$parts.Add(($nameJson + ":" + $valJson))
  }
  return "{" + ($parts -join ",") + "}"
}

function WT-FindDeviceRoot([string]$Root,[string]$DeviceId){
  $candidate = Join-Path $Root $DeviceId
  if(Test-Path -LiteralPath $candidate -PathType Container){
    return $candidate
  }
  return $null
}

function WT-AppendDeviceEvent(
  [string]$Repo,
  [string]$DeviceRoot,
  [string]$EventType,
  [string]$ObservedUtc,
  [string]$PayloadHash,
  [string]$PolicyHash,
  [string]$Status
){
  $Append = Join-Path $Repo "scripts\watchtower_append_device_event_v1.ps1"
  if(-not (Test-Path -LiteralPath $Append -PathType Leaf)){
    WT-Die ("MISSING_APPEND_SCRIPT: " + $Append)
  }

  & $Append `
    -RepoRoot $Repo `
    -DeviceRoot $DeviceRoot `
    -EventType $EventType `
    -ObservedUtc $ObservedUtc `
    -PayloadHash $PayloadHash `
    -PolicyHash $PolicyHash `
    -Status $Status

  if(-not $?){
    WT-Die "APPEND_CHILD_FAILED"
  }
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  WT-Die ("INVALID_REPO_ROOT: " + $RepoRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if(-not (Test-Path -LiteralPath $TelemetryPath -PathType Leaf)){
  WT-Die ("MISSING_TELEMETRY: " + $TelemetryPath)
}
$TelemetryPath = (Resolve-Path -LiteralPath $TelemetryPath).Path

if([string]::IsNullOrWhiteSpace($DevicesRoot)){
  $DevicesRoot = Join-Path $RepoRoot "devices"
}
if(-not (Test-Path -LiteralPath $DevicesRoot -PathType Container)){
  WT-Die ("MISSING_DEVICES_ROOT: " + $DevicesRoot)
}
$DevicesRoot = (Resolve-Path -LiteralPath $DevicesRoot).Path

if([string]::IsNullOrWhiteSpace($Status)){
  WT-Die "MISSING_STATUS"
}

$raw = WT-ReadUtf8NoBomLf $TelemetryPath
$lines = @(@($raw -split "`n") | Where-Object { $_ -and $_.Trim().Length -gt 0 })
if(@($lines).Count -eq 0){
  WT-Die "EMPTY_TELEMETRY"
}

$expectedDeviceId = ""
$deviceRoot = ""
$receiptPath = Join-Path $RepoRoot "proofs\receipts\watchtower_bind_telemetry_to_device_event.ndjson"

foreach($line in $lines){
  $obj = $line | ConvertFrom-Json

  $deviceId = WT-EnsureString $obj.device_id
  $schema = WT-EnsureString $obj.schema
  $observedUtc = WT-EnsureString $obj.observed_utc

  if([string]::IsNullOrWhiteSpace($deviceId)){ WT-Die "MISSING_DEVICE_ID_IN_TELEMETRY" }
  if([string]::IsNullOrWhiteSpace($schema)){ WT-Die "MISSING_SCHEMA_IN_TELEMETRY" }
  if([string]::IsNullOrWhiteSpace($observedUtc)){ WT-Die "MISSING_OBSERVED_UTC_IN_TELEMETRY" }

  if([string]::IsNullOrWhiteSpace($expectedDeviceId)){
    $expectedDeviceId = $deviceId
    $deviceRoot = WT-FindDeviceRoot $DevicesRoot $expectedDeviceId
    if([string]::IsNullOrWhiteSpace($deviceRoot)){
      WT-Die ("DEVICE_NOT_FOUND: " + $expectedDeviceId)
    }
  }
  elseif($deviceId -ne $expectedDeviceId){
    WT-Die ("MULTI_DEVICE_TELEMETRY_NOT_ALLOWED: expected=" + $expectedDeviceId + " actual=" + $deviceId)
  }

  $payloadHash = WT-Sha256HexText $line
  $eventType = "telemetry/" + $schema

  WT-AppendDeviceEvent `
    -Repo $RepoRoot `
    -DeviceRoot $deviceRoot `
    -EventType $eventType `
    -ObservedUtc $observedUtc `
    -PayloadHash $payloadHash `
    -PolicyHash $PolicyHash `
    -Status $Status

  $receiptMap = [ordered]@{
    device_id = $deviceId
    device_root = $deviceRoot
    payload_hash = $payloadHash
    receipt_schema = "watchtower.bind_telemetry_to_device_event.receipt.v1"
    status = "ok"
    telemetry_path = $TelemetryPath
    telemetry_schema = $schema
  }

  $receiptJson = WT-CanonicalJson $receiptMap
  WT-AppendNdjson -Path $receiptPath -Line $receiptJson
}

Write-Host "WATCHTOWER_BIND_TELEMETRY_TO_DEVICE_EVENT_OK" -ForegroundColor Green
Write-Host ("DEVICE_ID: " + $expectedDeviceId) -ForegroundColor Green
Write-Host ("TELEMETRY: " + $TelemetryPath) -ForegroundColor Green
Write-Host ("DEVICES_ROOT: " + $DevicesRoot) -ForegroundColor Green
Write-Host ("RECEIPT: " + $receiptPath) -ForegroundColor Green