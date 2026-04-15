param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function WT-Die([string]$m){
  throw ("WATCHTOWER_LIVE_STATE_FULL_GREEN_FAIL: " + $m)
}

function WT-RequireFile([string]$Path,[string]$Code){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    WT-Die ($Code + ": " + $Path)
  }
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  WT-Die ("INVALID_REPO_ROOT: " + $RepoRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

$PacketPipeline    = Join-Path $RepoRoot "scripts\watchtower_packet_repair_and_verify_v1.ps1"
$PacketSelf        = Join-Path $RepoRoot "scripts\_selftest_watchtower_packet_verify_v1.ps1"
$StateSelf         = Join-Path $RepoRoot "scripts\_selftest_watchtower_state_v1.ps1"
$DeviceChainSelf   = Join-Path $RepoRoot "scripts\_selftest_watchtower_device_chain_v1.ps1"
$DeviceBindingSelf = Join-Path $RepoRoot "scripts\_selftest_watchtower_device_binding_v1.ps1"

WT-RequireFile -Path $PacketPipeline -Code "WATCHTOWER_PACKET_PIPELINE_MISSING"
WT-RequireFile -Path $PacketSelf -Code "WATCHTOWER_PACKET_SELFTEST_MISSING"
WT-RequireFile -Path $StateSelf -Code "WATCHTOWER_STATE_SELFTEST_MISSING"

Write-Host "PHASE:WATCHTOWER_PACKET_PIPELINE" -ForegroundColor Yellow
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $PacketPipeline `
  -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){
  WT-Die ("WATCHTOWER_PACKET_PIPELINE_FAILED: " + $LASTEXITCODE)
}

Write-Host "PHASE:WATCHTOWER_PACKET_SELFTEST" -ForegroundColor Yellow
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $PacketSelf `
  -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){
  WT-Die ("WATCHTOWER_PACKET_SELFTEST_FAILED: " + $LASTEXITCODE)
}

Write-Host "PHASE:WATCHTOWER_STATE_SELFTEST" -ForegroundColor Yellow
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File $StateSelf `
  -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){
  WT-Die ("WATCHTOWER_STATE_SELFTEST_FAILED: " + $LASTEXITCODE)
}

if(Test-Path -LiteralPath $DeviceChainSelf -PathType Leaf){
  Write-Host "PHASE:WATCHTOWER_DEVICE_CHAIN_SELFTEST" -ForegroundColor Yellow
  & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $DeviceChainSelf `
    -RepoRoot $RepoRoot
  if($LASTEXITCODE -ne 0){
    WT-Die ("WATCHTOWER_DEVICE_CHAIN_SELFTEST_FAILED: " + $LASTEXITCODE)
  }
}

if(Test-Path -LiteralPath $DeviceBindingSelf -PathType Leaf){
  Write-Host "PHASE:WATCHTOWER_DEVICE_BINDING_SELFTEST" -ForegroundColor Yellow
  & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $DeviceBindingSelf `
    -RepoRoot $RepoRoot
  if($LASTEXITCODE -ne 0){
    WT-Die ("WATCHTOWER_DEVICE_BINDING_SELFTEST_FAILED: " + $LASTEXITCODE)
  }
}

Write-Host "WATCHTOWER_LIVE_STATE_FULL_GREEN_OK" -ForegroundColor Green
$global:LASTEXITCODE = 0
return
