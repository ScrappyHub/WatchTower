param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$TelemetryPath,
  [string]$ExpectedPolicyHash = "",
  [int]$HeartbeatStaleMinutes = 15
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$Verify = Join-Path $RepoRoot "scripts\watchtower_verify_telemetry_v1.ps1"
$Mat    = Join-Path $RepoRoot "scripts\watchtower_materialize_state_v1.ps1"
$Alert  = Join-Path $RepoRoot "scripts\watchtower_derive_alerts_v1.ps1"
$PSExe  = (Get-Command powershell.exe -ErrorAction Stop).Source

$StatePath  = Join-Path $RepoRoot "proofs\state\watchtower_state.json"
$AlertsPath = Join-Path $RepoRoot "proofs\state\watchtower_alerts.ndjson"

# --- VERIFY ---
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $Verify `
  -RepoRoot $RepoRoot `
  -TelemetryPath $TelemetryPath

if($LASTEXITCODE -ne 0){
  throw ("VERIFY_FAILED: " + $LASTEXITCODE)
}

# --- MATERIALIZE (FIXED) ---
$matArgs = @(
  "-NoProfile",
  "-NonInteractive",
  "-ExecutionPolicy","Bypass",
  "-File",$Mat,
  "-RepoRoot",$RepoRoot,
  "-TelemetryPath",$TelemetryPath,
  "-HeartbeatStaleMinutes",$HeartbeatStaleMinutes,
  "-OutPath",$StatePath
)

if(-not [string]::IsNullOrWhiteSpace($ExpectedPolicyHash)){
  $matArgs += @("-ExpectedPolicyHash",$ExpectedPolicyHash)
}

$proc = Start-Process `
  -FilePath $PSExe `
  -ArgumentList $matArgs `
  -Wait -PassThru -NoNewWindow

if($proc.ExitCode -ne 0){
  throw ("MATERIALIZE_FAILED: " + $proc.ExitCode)
}

# --- ALERT ---
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $Alert `
  -RepoRoot $RepoRoot `
  -StatePath $StatePath `
  -OutPath $AlertsPath

if($LASTEXITCODE -ne 0){
  throw ("ALERT_FAILED: " + $LASTEXITCODE)
}

Write-Host "WATCHTOWER_STATE_RUNNER_OK" -ForegroundColor Green
Write-Host ("STATE: " + $StatePath) -ForegroundColor Green
Write-Host ("ALERTS: " + $AlertsPath) -ForegroundColor Green
