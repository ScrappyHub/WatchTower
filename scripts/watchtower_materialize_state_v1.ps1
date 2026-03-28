param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TelemetryPath,
  [string]$ExpectedPolicyHash = "",
  [Parameter(Mandatory=$true)][string]$HeartbeatStaleMinutes,
  [string]$OutPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function WT-Die([string]$m){ throw ("WATCHTOWER_MATERIALIZE_FAIL: " + $m) }

function WT-EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function WT-WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ WT-EnsureDir $dir }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

try {
  $StaleMinutes = [int]$HeartbeatStaleMinutes
} catch {
  WT-Die "INVALID_STALE_MINUTES"
}

if($StaleMinutes -le 0){
  WT-Die "INVALID_STALE_MINUTES"
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$TelemetryPath = (Resolve-Path -LiteralPath $TelemetryPath).Path

if([string]::IsNullOrWhiteSpace($OutPath)){
  $OutPath = Join-Path $RepoRoot "proofs\state\watchtower_state.json"
}

if(-not (Test-Path -LiteralPath $TelemetryPath -PathType Leaf)){
  WT-Die ("MISSING_TELEMETRY: " + $TelemetryPath)
}

$raw = Get-Content -LiteralPath $TelemetryPath -Raw
if([string]::IsNullOrWhiteSpace($raw)){
  WT-Die "EMPTY_TELEMETRY"
}

$lines = @($raw.Replace("`r`n","`n").Replace("`r","`n") -split "`n" | Where-Object { $_.Trim().Length -gt 0 })
if($lines.Count -eq 0){
  WT-Die "EMPTY_LINES"
}

$objects = New-Object System.Collections.Generic.List[object]
foreach($line in $lines){
  $o = $line | ConvertFrom-Json
  if($null -eq $o){ WT-Die "NULL_TELEMETRY_OBJECT" }
  if([string]::IsNullOrWhiteSpace([string]$o.schema)){ WT-Die "MISSING_SCHEMA" }
  if([string]::IsNullOrWhiteSpace([string]$o.device_id)){ WT-Die "MISSING_DEVICE_ID" }
  if([string]::IsNullOrWhiteSpace([string]$o.observed_utc)){ WT-Die "MISSING_OBSERVED_UTC" }
  [void]$objects.Add($o)
}

$deviceId = [string]$objects[0].device_id
$latestHeartbeat = $null
$latestHealth = $null
$latestPolicy = $null
$latestObserved = $null

foreach($o in $objects){
  if([string]$o.device_id -ne $deviceId){
    WT-Die "MIXED_DEVICE_IDS"
  }

  $obs = [datetime]::Parse(
    [string]$o.observed_utc,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
  )

  if(($null -eq $latestObserved) -or ($obs -gt $latestObserved)){
    $latestObserved = $obs
  }

  if([string]$o.schema -eq "watchtower.heartbeat.v1"){
    if(
      ($null -eq $latestHeartbeat) -or
      ($obs -gt ([datetime]::Parse(
        [string]$latestHeartbeat.observed_utc,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
      )))
    ){
      $latestHeartbeat = $o
    }
  }
  elseif([string]$o.schema -eq "watchtower.health_report.v1"){
    if(
      ($null -eq $latestHealth) -or
      ($obs -gt ([datetime]::Parse(
        [string]$latestHealth.observed_utc,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
      )))
    ){
      $latestHealth = $o
    }
  }
  elseif([string]$o.schema -eq "watchtower.policy_attest.v1"){
    if(
      ($null -eq $latestPolicy) -or
      ($obs -gt ([datetime]::Parse(
        [string]$latestPolicy.observed_utc,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
      )))
    ){
      $latestPolicy = $o
    }
  }
}

$state = "unknown"
$reason = "no telemetry"
$observedUtc = "1970-01-01T00:00:00Z"

if($null -ne $latestHeartbeat){
  $hbUtc = [datetime]::Parse(
    [string]$latestHeartbeat.observed_utc,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
  )

  $deltaMin = [math]::Floor(($latestObserved - $hbUtc).TotalMinutes)

  if($deltaMin -ge $StaleMinutes){
    $state = "stale"
    $reason = "heartbeat stale"
    $observedUtc = [string]$latestHeartbeat.observed_utc
  }
  elseif($null -ne $latestHealth){
    if(
      (($latestHealth.PSObject.Properties.Name -contains "health_ok") -and (-not [bool]$latestHealth.health_ok)) -or
      (($latestHealth.PSObject.Properties.Name -contains "failure_count") -and ([int]$latestHealth.failure_count -gt 0))
    ){
      $state = "broken"
      $reason = "health report indicates failure"
      $observedUtc = [string]$latestHealth.observed_utc
    }
    elseif(
      ($latestHealth.PSObject.Properties.Name -contains "degraded") -and
      ([bool]$latestHealth.degraded)
    ){
      $state = "degraded"
      $reason = "health report indicates degraded"
      $observedUtc = [string]$latestHealth.observed_utc
    }
    elseif($null -ne $latestPolicy){
      $actual = [string]$latestPolicy.policy_hash
      $expected = $ExpectedPolicyHash

      if(
        [string]::IsNullOrWhiteSpace($expected) -and
        ($latestPolicy.PSObject.Properties.Name -contains "expected_policy_hash")
      ){
        $expected = [string]$latestPolicy.expected_policy_hash
      }

      if(
        (($latestPolicy.PSObject.Properties.Name -contains "policy_ok") -and (-not [bool]$latestPolicy.policy_ok)) -or
        ((-not [string]::IsNullOrWhiteSpace($expected)) -and ($actual -ne $expected))
      ){
        $state = "drift"
        $reason = "policy hash drift"
        $observedUtc = [string]$latestPolicy.observed_utc
      }
      else {
        $state = "ok"
        $reason = "all checks green"
        $observedUtc = $latestObserved.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
      }
    }
    else {
      $state = "ok"
      $reason = "all checks green"
      $observedUtc = $latestObserved.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
  }
  elseif($null -ne $latestPolicy){
    $actual = [string]$latestPolicy.policy_hash
    $expected = $ExpectedPolicyHash

    if(
      [string]::IsNullOrWhiteSpace($expected) -and
      ($latestPolicy.PSObject.Properties.Name -contains "expected_policy_hash")
    ){
      $expected = [string]$latestPolicy.expected_policy_hash
    }

    if(
      (($latestPolicy.PSObject.Properties.Name -contains "policy_ok") -and (-not [bool]$latestPolicy.policy_ok)) -or
      ((-not [string]::IsNullOrWhiteSpace($expected)) -and ($actual -ne $expected))
    ){
      $state = "drift"
      $reason = "policy hash drift"
      $observedUtc = [string]$latestPolicy.observed_utc
    }
    else {
      $state = "ok"
      $reason = "heartbeat green"
      $observedUtc = $latestObserved.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
  }
  else {
    $state = "ok"
    $reason = "heartbeat green"
    $observedUtc = $latestObserved.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  }
}

$out = [pscustomobject]@{
  schema        = "watchtower.state.v1"
  device_id     = $deviceId
  observed_utc  = $observedUtc
  evaluated_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  state         = $state
  reason        = $reason
  source        = $TelemetryPath
} | ConvertTo-Json -Compress -Depth 10

WT-WriteUtf8NoBomLf -Path $OutPath -Text $out

Write-Host "WATCHTOWER_STATE_OK" -ForegroundColor Green
Write-Host ("STATE=" + $state) -ForegroundColor Green
Write-Host ("OUT=" + $OutPath) -ForegroundColor Green