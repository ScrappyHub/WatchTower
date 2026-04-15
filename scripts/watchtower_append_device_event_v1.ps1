param(
  [Parameter(Mandatory=$true)]$RepoRoot,
  [Parameter(Mandatory=$true)]$DeviceRoot,
  [Parameter(Mandatory=$true)]$EventType,
  [Parameter(Mandatory=$true)]$ObservedUtc,
  $PayloadHash = "",
  $PolicyHash = "",
  $Status = "ok"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WT-Die([string]$m){
  throw ("WATCHTOWER_APPEND_DEVICE_EVENT_FAIL: " + $m)
}

function WT-EnsureString([object]$v){
  if($null -eq $v){ return "" }
  return [string]$v
}

function WT-EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function WT-WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = (WT-EnsureString $Text).Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $dir = Split-Path -Parent $Path
  if($dir){ WT-EnsureDir $dir }
  [System.IO.File]::WriteAllText($Path,$t,$enc)
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

function WT-ValidateUtc([string]$s,[string]$fieldName){
  if([string]::IsNullOrWhiteSpace($s)){ WT-Die ("EMPTY_" + $fieldName) }
  [void][datetime]::Parse(
    $s,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
  )
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

if($DeviceRoot -is [System.IO.FileSystemInfo]){
  $DeviceRoot = $DeviceRoot.FullName
} elseif($DeviceRoot -is [array]){
  if($DeviceRoot.Count -eq 0){ WT-Die "EMPTY_DEVICE_ROOT_ARG" }
  $DeviceRoot = $DeviceRoot[0]
}
$DeviceRoot = [string]$DeviceRoot
if(-not (Test-Path -LiteralPath $DeviceRoot -PathType Container)){
  WT-Die ("INVALID_DEVICE_ROOT: " + $DeviceRoot)
}
$DeviceRoot = (Resolve-Path -LiteralPath $DeviceRoot).Path

$EventType = WT-EnsureString $EventType
$ObservedUtc = WT-EnsureString $ObservedUtc
$PayloadHash = WT-EnsureString $PayloadHash
$PolicyHash = WT-EnsureString $PolicyHash
$Status = WT-EnsureString $Status

if([string]::IsNullOrWhiteSpace($EventType)){ WT-Die "MISSING_EVENT_TYPE" }
if([string]::IsNullOrWhiteSpace($Status)){ WT-Die "MISSING_STATUS" }

WT-ValidateUtc $ObservedUtc "OBSERVED_UTC"

$devicePath = Join-Path $DeviceRoot "device.json"
$eventsPath = Join-Path $DeviceRoot "events.ndjson"
$receiptPath = Join-Path $RepoRoot "proofs\receipts\watchtower_device_event_append.ndjson"

if(-not (Test-Path -LiteralPath $devicePath -PathType Leaf)){
  WT-Die ("MISSING_DEVICE_JSON: " + $devicePath)
}
if(-not (Test-Path -LiteralPath $eventsPath -PathType Leaf)){
  WT-Die ("MISSING_EVENTS_FILE: " + $eventsPath)
}

$deviceRaw = WT-ReadUtf8NoBomLf $devicePath
if([string]::IsNullOrWhiteSpace($deviceRaw)){ WT-Die "EMPTY_DEVICE_JSON" }

$deviceObj = $deviceRaw | ConvertFrom-Json
$deviceSchema = WT-EnsureString $deviceObj.schema
$deviceId = WT-EnsureString $deviceObj.device_id

if($deviceSchema -ne "watchtower.device.v1"){ WT-Die ("BAD_DEVICE_SCHEMA: " + $deviceSchema) }
if([string]::IsNullOrWhiteSpace($deviceId)){ WT-Die "MISSING_DEVICE_ID" }

$prevEventHash = ""
$eventsRaw = WT-ReadUtf8NoBomLf $eventsPath

if(-not [string]::IsNullOrWhiteSpace($eventsRaw)){
  $lines = @($eventsRaw -split "`n" | Where-Object { $_ -and $_.Trim().Length -gt 0 })
  if($lines.Count -gt 0){
    $lastLine = [string]$lines[$lines.Count - 1]
    $prevEventHash = WT-Sha256HexText $lastLine
  }
}

$eventMap = [ordered]@{
  device_id = $deviceId
  event_type = $EventType
  observed_utc = $ObservedUtc
  payload_hash = $PayloadHash
  policy_hash = $PolicyHash
  prev_event_hash = $prevEventHash
  schema = "watchtower.device_event.v1"
  status = $Status
}

$tempJson = WT-CanonicalJson $eventMap
$eventId = WT-Sha256HexText $tempJson

$eventMap.event_id = $eventId
$eventJson = WT-CanonicalJson $eventMap

WT-AppendNdjson -Path $eventsPath -Line $eventJson

$receiptMap = [ordered]@{
  device_id = $deviceId
  event_id = $eventId
  event_type = $EventType
  events_path = $eventsPath
  prev_event_hash = $prevEventHash
  receipt_schema = "watchtower.device_event_append.receipt.v1"
  status = "ok"
}

$receiptJson = WT-CanonicalJson $receiptMap
WT-AppendNdjson -Path $receiptPath -Line $receiptJson

Write-Host "WATCHTOWER_APPEND_DEVICE_EVENT_OK" -ForegroundColor Green
Write-Host ("DEVICE_ID: " + $deviceId) -ForegroundColor Green
Write-Host ("EVENT_ID: " + $eventId) -ForegroundColor Green
Write-Host ("PREV_EVENT_HASH: " + $prevEventHash) -ForegroundColor Green
Write-Host ("EVENTS: " + $eventsPath) -ForegroundColor Green
Write-Host ("RECEIPT: " + $receiptPath) -ForegroundColor Green
