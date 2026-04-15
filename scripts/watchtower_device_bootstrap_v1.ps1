param(
  [Parameter(Mandatory=$true)]$RepoRoot,
  [Parameter(Mandatory=$true)]$DevicePubKey,
  [Parameter(Mandatory=$true)]$HardwareFingerprint,
  [Parameter(Mandatory=$true)]$Manufacturer,
  [Parameter(Mandatory=$true)]$Serial,
  [Parameter(Mandatory=$true)]$OsFamily,
  [Parameter(Mandatory=$true)]$FirstSeenUtc,
  $ProvisioningPolicyHash = "",
  $TrustLevel = "T0",
  $Status = "enrolled",
  $DeviceRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WT-Die([string]$m){
  throw ("WATCHTOWER_DEVICE_BOOTSTRAP_FAIL: " + $m)
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

function WT-Sha256HexBytes([byte[]]$b){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($b)) -replace "-","").ToLowerInvariant()
  }
  finally {
    $sha.Dispose()
  }
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

function WT-ValidateUtc([string]$s){
  if([string]::IsNullOrWhiteSpace($s)){ WT-Die "EMPTY_FIRST_SEEN_UTC" }
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

$DevicePubKey = WT-EnsureString $DevicePubKey
$HardwareFingerprint = WT-EnsureString $HardwareFingerprint
$Manufacturer = WT-EnsureString $Manufacturer
$Serial = WT-EnsureString $Serial
$OsFamily = WT-EnsureString $OsFamily
$FirstSeenUtc = WT-EnsureString $FirstSeenUtc
$ProvisioningPolicyHash = WT-EnsureString $ProvisioningPolicyHash
$TrustLevel = WT-EnsureString $TrustLevel
$Status = WT-EnsureString $Status
$DeviceRoot = WT-EnsureString $DeviceRoot

foreach($pair in @(
  @{ Name="DEVICE_PUBKEY"; Value=$DevicePubKey },
  @{ Name="HARDWARE_FINGERPRINT"; Value=$HardwareFingerprint },
  @{ Name="MANUFACTURER"; Value=$Manufacturer },
  @{ Name="SERIAL"; Value=$Serial },
  @{ Name="OS_FAMILY"; Value=$OsFamily },
  @{ Name="TRUST_LEVEL"; Value=$TrustLevel },
  @{ Name="STATUS"; Value=$Status }
)){
  if([string]::IsNullOrWhiteSpace([string]$pair.Value)){
    WT-Die ("MISSING_" + [string]$pair.Name)
  }
}

WT-ValidateUtc $FirstSeenUtc

$identityMap = [ordered]@{
  device_pubkey = $DevicePubKey
  first_seen_utc = $FirstSeenUtc
  hardware_fingerprint = $HardwareFingerprint
  manufacturer = $Manufacturer
  serial = $Serial
}

$identityJson = WT-CanonicalJson $identityMap
$deviceId = WT-Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($identityJson))

if([string]::IsNullOrWhiteSpace($DeviceRoot)){
  $DeviceRoot = Join-Path $RepoRoot ("devices\" + $deviceId)
}

$DeviceRoot = [string]$DeviceRoot
WT-EnsureDir $DeviceRoot

$devicePath  = Join-Path $DeviceRoot "device.json"
$eventsPath  = Join-Path $DeviceRoot "events.ndjson"
$receiptPath = Join-Path $RepoRoot "proofs\receipts\watchtower_device_bootstrap.ndjson"

$deviceMap = [ordered]@{
  device_id = $deviceId
  device_pubkey = $DevicePubKey
  first_seen_utc = $FirstSeenUtc
  hardware_fingerprint = $HardwareFingerprint
  manufacturer = $Manufacturer
  os_family = $OsFamily
  provisioning_policy_hash = $ProvisioningPolicyHash
  schema = "watchtower.device.v1"
  serial = $Serial
  status = $Status
  trust_level = $TrustLevel
}

$deviceJson = WT-CanonicalJson $deviceMap
WT-WriteUtf8NoBomLf -Path $devicePath -Text $deviceJson

if(-not (Test-Path -LiteralPath $eventsPath -PathType Leaf)){
  WT-WriteUtf8NoBomLf -Path $eventsPath -Text ""
}

$receiptMap = [ordered]@{
  device_id = $deviceId
  device_path = $devicePath
  device_root = $DeviceRoot
  events_path = $eventsPath
  receipt_schema = "watchtower.device.bootstrap.receipt.v1"
  status = "ok"
}

$receiptJson = WT-CanonicalJson $receiptMap
WT-AppendNdjson -Path $receiptPath -Line $receiptJson

Write-Host "WATCHTOWER_DEVICE_BOOTSTRAP_OK" -ForegroundColor Green
Write-Host ("DEVICE_ID: " + $deviceId) -ForegroundColor Green
Write-Host ("DEVICE_ROOT: " + $DeviceRoot) -ForegroundColor Green
Write-Host ("DEVICE_JSON: " + $devicePath) -ForegroundColor Green
Write-Host ("EVENTS: " + $eventsPath) -ForegroundColor Green
Write-Host ("RECEIPT: " + $receiptPath) -ForegroundColor Green
