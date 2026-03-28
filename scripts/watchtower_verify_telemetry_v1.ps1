param(
  [Parameter(Mandatory=$true)]$RepoRoot,
  [Parameter(Mandatory=$true)]$TelemetryPath,
  $ReceiptPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function WT-Die([string]$m){ throw ("WATCHTOWER_VERIFY_FAIL: " + $m) }

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

function WT-AppendNdjson([string]$Path,[string]$Line){
  $dir = Split-Path -Parent $Path
  if($dir){ WT-EnsureDir $dir }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $txt = (WT-EnsureString $Line).Replace("`r`n","`n").Replace("`r","`n")
  if(-not $txt.EndsWith("`n")){ $txt += "`n" }
  [System.IO.File]::AppendAllText($Path,$txt,$enc)
}

function WT-ReadRawText([string]$Path){
  return [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8).Replace("`r`n","`n").Replace("`r","`n")
}

function WT-ValidateTelemetryObject([object]$o){
  if($null -eq $o){ WT-Die "NULL_TELEMETRY_OBJECT" }

  $schema = WT-EnsureString $o.schema
  $device = WT-EnsureString $o.device_id
  $obsUtc = WT-EnsureString $o.observed_utc

  if([string]::IsNullOrWhiteSpace($schema)){ WT-Die "MISSING_SCHEMA" }
  if([string]::IsNullOrWhiteSpace($device)){ WT-Die "MISSING_DEVICE_ID" }
  if([string]::IsNullOrWhiteSpace($obsUtc)){ WT-Die "MISSING_OBSERVED_UTC" }

  if(
    ($schema -ne "watchtower.heartbeat.v1") -and
    ($schema -ne "watchtower.health_report.v1") -and
    ($schema -ne "watchtower.policy_attest.v1")
  ){
    WT-Die ("UNSUPPORTED_SCHEMA: " + $schema)
  }

  [void][datetime]::Parse(
    $obsUtc,
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

if($TelemetryPath -is [System.IO.FileSystemInfo]){
  $TelemetryPath = $TelemetryPath.FullName
} elseif($TelemetryPath -is [array]){
  if($TelemetryPath.Count -eq 0){ WT-Die "EMPTY_TELEMETRY_ARG" }
  $TelemetryPath = $TelemetryPath[0]
}
$TelemetryPath = [string]$TelemetryPath

if($ReceiptPath -is [System.IO.FileSystemInfo]){
  $ReceiptPath = $ReceiptPath.FullName
} elseif($ReceiptPath -is [array]){
  if($ReceiptPath.Count -gt 0){ $ReceiptPath = $ReceiptPath[0] } else { $ReceiptPath = "" }
}
$ReceiptPath = [string]$ReceiptPath

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  WT-Die ("INVALID_REPO_ROOT: " + $RepoRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if(-not (Test-Path -LiteralPath $TelemetryPath -PathType Leaf)){
  WT-Die ("MISSING_TELEMETRY: " + $TelemetryPath)
}
$TelemetryPath = (Resolve-Path -LiteralPath $TelemetryPath).Path

if([string]::IsNullOrWhiteSpace($ReceiptPath)){
  $ReceiptPath = Join-Path $RepoRoot "proofs\receipts\watchtower_telemetry_verify.ndjson"
}

Write-Host "VERIFY_PHASE:READ_START" -ForegroundColor Yellow
$raw = WT-ReadRawText $TelemetryPath
if([string]::IsNullOrWhiteSpace($raw)){ WT-Die "EMPTY_TELEMETRY" }

$lines = @($raw -split "`n" | Where-Object { $_ -and $_.Trim().Length -gt 0 })
if($lines.Count -lt 1){ WT-Die "EMPTY_TELEMETRY_LINES" }
Write-Host "VERIFY_PHASE:READ_DONE" -ForegroundColor Yellow

foreach($line in $lines){
  $obj = $null
  try {
    $obj = $line | ConvertFrom-Json
  }
  catch {
    WT-Die ("BAD_JSON_LINE: " + $_.Exception.Message)
  }

  WT-ValidateTelemetryObject $obj

  $receipt = [pscustomobject]@{
    schema              = "watchtower.telemetry.verify.receipt.v1"
    verify_mode         = "direct_ndjson"
    device_id           = (WT-EnsureString $obj.device_id)
    telemetry_schema    = (WT-EnsureString $obj.schema)
    observed_utc        = (WT-EnsureString $obj.observed_utc)
    verify_status       = "verified"
    reason              = "schema+shape verified"
    source_path         = $TelemetryPath
    packet_root         = ""
    packet_id           = ""
    signature_path      = ""
    verify_namespace    = ""
    verify_principal    = ""
    trust_bundle_sha256 = ""
    allowed_sha256      = ""
    source_object_json  = ($obj | ConvertTo-Json -Compress -Depth 20)
  } | ConvertTo-Json -Compress -Depth 20

  WT-AppendNdjson -Path $ReceiptPath -Line $receipt
}

Write-Host "WATCHTOWER_TELEMETRY_VERIFY_OK" -ForegroundColor Green
Write-Host ("TELEMETRY: " + $TelemetryPath) -ForegroundColor Green
Write-Host ("RECEIPT: " + $ReceiptPath) -ForegroundColor Green
Write-Host "MODE: direct_ndjson" -ForegroundColor Green
