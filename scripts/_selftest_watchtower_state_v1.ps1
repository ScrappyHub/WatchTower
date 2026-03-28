param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$PSExe      = (Get-Command powershell.exe -ErrorAction Stop).Source
$Runner     = Join-Path $RepoRoot "scripts\_RUN_watchtower_state_engine_v1.ps1"
$VecRoot    = Join-Path $RepoRoot "test_vectors\watchtower\state\v1"
$StatePath  = Join-Path $RepoRoot "proofs\state\watchtower_state.json"
$AlertsPath = Join-Path $RepoRoot "proofs\state\watchtower_alerts.ndjson"

function Run-Case(
  [string]$Name,
  [string]$Vec,
  [string]$ExpectedState,
  [string]$ExpectedAlertType,
  [string]$ExpectedPolicyHash
){
  if(Test-Path -LiteralPath $StatePath -PathType Leaf){
    Remove-Item -LiteralPath $StatePath -Force
  }
  if(Test-Path -LiteralPath $AlertsPath -PathType Leaf){
    Remove-Item -LiteralPath $AlertsPath -Force
  }

  $argList = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy","Bypass",
    "-File",$Runner,
    "-RepoRoot",$RepoRoot,
    "-TelemetryPath",$Vec,
    "-HeartbeatStaleMinutes","15"
  )

  if(-not [string]::IsNullOrWhiteSpace($ExpectedPolicyHash)){
    $argList += @("-ExpectedPolicyHash",$ExpectedPolicyHash)
  }

  & $PSExe @argList
  if($LASTEXITCODE -ne 0){
    throw ("CASE_FAILED: " + $Name)
  }

  if(-not (Test-Path -LiteralPath $StatePath -PathType Leaf)){
    throw ("STATE_MISSING: " + $Name)
  }

  $s = ([System.IO.File]::ReadAllText($StatePath,[System.Text.Encoding]::UTF8) | ConvertFrom-Json)
  if([string]$s.state -ne $ExpectedState){
    throw ("BAD_STATE_" + $Name + ": got=" + [string]$s.state + " expected=" + $ExpectedState)
  }

  if([string]::IsNullOrWhiteSpace($ExpectedAlertType)){
    if(Test-Path -LiteralPath $AlertsPath -PathType Leaf){
      $raw = [System.IO.File]::ReadAllText($AlertsPath,[System.Text.Encoding]::UTF8)
      if(($raw.Trim()).Length -gt 0){
        throw ("UNEXPECTED_ALERTS: " + $Name)
      }
    }
  }
  else {
    if(-not (Test-Path -LiteralPath $AlertsPath -PathType Leaf)){
      throw ("ALERTS_MISSING: " + $Name)
    }

    $raw = [System.IO.File]::ReadAllText($AlertsPath,[System.Text.Encoding]::UTF8).Replace("`r`n","`n").Replace("`r","`n")
    $lines = @($raw -split "`n" | Where-Object { $_.Trim().Length -gt 0 })
    if($lines.Count -lt 1){
      throw ("ALERTS_EMPTY: " + $Name)
    }

    $a = ($lines[0] | ConvertFrom-Json)
    if([string]$a.alert_type -ne $ExpectedAlertType){
      throw ("BAD_ALERT_" + $Name + ": got=" + [string]$a.alert_type + " expected=" + $ExpectedAlertType)
    }
  }

  Write-Host ("CASE_OK: " + $Name + " => " + $ExpectedState) -ForegroundColor Green
}

Run-Case -Name "ok"      -Vec (Join-Path $VecRoot "ok.ndjson")      -ExpectedState "ok"      -ExpectedAlertType ""                -ExpectedPolicyHash "abc123"
Run-Case -Name "stale"   -Vec (Join-Path $VecRoot "stale.ndjson")   -ExpectedState "stale"   -ExpectedAlertType "heartbeat_stale" -ExpectedPolicyHash ""
Run-Case -Name "drift"   -Vec (Join-Path $VecRoot "drift.ndjson")   -ExpectedState "drift"   -ExpectedAlertType "policy_drift"    -ExpectedPolicyHash "abc123"
Run-Case -Name "failure" -Vec (Join-Path $VecRoot "failure.ndjson") -ExpectedState "broken"  -ExpectedAlertType "health_failed"   -ExpectedPolicyHash ""

Write-Host "WATCHTOWER_STATE_SELFTEST_OK" -ForegroundColor Green