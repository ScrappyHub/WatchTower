param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw ("WT_PCV1_SELFTEST_FAIL: " + $m) }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$verify = Join-Path $RepoRoot "scripts\watchtower_verify_packet_v1.ps1"
if(-not (Test-Path -LiteralPath $verify -PathType Leaf)) { Die "missing verify script" }
$vecRoot = Join-Path $RepoRoot "test_vectors\pcv1"
$pos = Join-Path $vecRoot "signed_packet"
$neg = Join-Path $vecRoot "tampered_manifest"
$psExe = (Get-Command powershell.exe -ErrorAction Stop).Source

Write-Host "PCV1_SELFTEST: positive vector..." -ForegroundColor Cyan
& $psExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $verify -PacketRoot $pos
if ($LASTEXITCODE -ne 0) { Die ("positive vector failed (exit=" + $LASTEXITCODE + ")") }

Write-Host "PCV1_SELFTEST: negative vector (must fail)..." -ForegroundColor Cyan
$failedAsExpected = $false
$old = $ErrorActionPreference
try {
  $ErrorActionPreference="Continue"
  & $psExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $verify -PacketRoot $neg 1> $null 2> $null
  if ($LASTEXITCODE -ne 0) { $failedAsExpected = $true }
} catch { $failedAsExpected = $true } finally { $ErrorActionPreference=$old }
if (-not $failedAsExpected) { Die "negative vector unexpectedly passed" }
Write-Host "PCV1_SELFTEST: EXPECTED_FAIL (negative vector)" -ForegroundColor DarkYellow
Write-Host "SELFTEST_OK" -ForegroundColor Green
