param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$Self  = Join-Path $RepoRoot "scripts\_selftest_watchtower_state_v1.ps1"

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Self -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ throw ("WATCHTOWER_STATE_SELFTEST_FAILED: " + $LASTEXITCODE) }

Write-Host "WATCHTOWER_LIVE_STATE_FULL_GREEN_OK" -ForegroundColor Green
