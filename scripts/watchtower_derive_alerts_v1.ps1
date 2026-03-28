param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$StatePath,
  [string]$OutPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function WT-Die([string]$m){ throw ("WATCHTOWER_ALERT_FAIL: " + $m) }

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
  $txt = (($Line -replace "`r`n","`n") -replace "`r","`n")
  if(-not $txt.EndsWith("`n")){ $txt += "`n" }
  [System.IO.File]::AppendAllText($Path,$txt,$enc)
}

if(-not (Test-Path -LiteralPath $StatePath -PathType Leaf)){
  WT-Die ("MISSING_STATE: " + $StatePath)
}

if([string]::IsNullOrWhiteSpace($OutPath)){
  $OutPath = Join-Path $RepoRoot "proofs\state\watchtower_alerts.ndjson"
}

if(Test-Path -LiteralPath $OutPath -PathType Leaf){
  Remove-Item -LiteralPath $OutPath -Force
}

$raw = Get-Content -LiteralPath $StatePath -Raw
if([string]::IsNullOrWhiteSpace($raw)){
  WT-Die "EMPTY_STATE"
}

$stateObj = $raw | ConvertFrom-Json

if($null -eq $stateObj){ WT-Die "NULL_STATE_OBJECT" }
if([string]::IsNullOrWhiteSpace([string]$stateObj.state)){ WT-Die "MISSING_STATE_VALUE" }
if(-not ($stateObj.PSObject.Properties.Name -contains "device_id")){ WT-Die "MISSING_DEVICE_ID" }
if(-not ($stateObj.PSObject.Properties.Name -contains "observed_utc")){ WT-Die "MISSING_OBSERVED_UTC" }
if(-not ($stateObj.PSObject.Properties.Name -contains "reason")){ WT-Die "MISSING_REASON" }

$state = [string]$stateObj.state

$alerts = @()

if($state -ne "ok"){
  $severity = "warning"
  $alertType = "telemetry_unknown"

  if($state -eq "stale"){
    $severity = "warning"
    $alertType = "heartbeat_stale"
  }
  elseif($state -eq "drift"){
    $severity = "warning"
    $alertType = "policy_drift"
  }
  elseif($state -eq "degraded"){
    $severity = "warning"
    $alertType = "health_degraded"
  }
  elseif($state -eq "broken"){
    $severity = "critical"
    $alertType = "health_failed"
  }
  elseif($state -eq "unknown"){
    $severity = "warning"
    $alertType = "telemetry_unknown"
  }

  $alert = [pscustomobject]@{
    schema       = "watchtower.alert.v1"
    device_id    = [string]$stateObj.device_id
    observed_utc = [string]$stateObj.observed_utc
    alert_type   = $alertType
    severity     = $severity
    state        = $state
    reason       = [string]$stateObj.reason
  } | ConvertTo-Json -Compress -Depth 10

  $alerts = @($alert)
}

foreach($a in @($alerts)){
  WT-AppendNdjson -Path $OutPath -Line $a
}

Write-Host "WATCHTOWER_ALERT_DERIVE_OK" -ForegroundColor Green
Write-Host ("ALERTS: " + $OutPath) -ForegroundColor Green
Write-Host ("ALERT_COUNT: " + (@($alerts)).Count) -ForegroundColor Green