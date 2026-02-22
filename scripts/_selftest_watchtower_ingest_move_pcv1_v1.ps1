param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw ("WT SELFTEST INGEST MOVE FAIL: " + $m) }
function ReadUtf8NoBom([string]$p){ [System.IO.File]::ReadAllText($p,(New-Object System.Text.UTF8Encoding($false))) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$VecRoot = Join-Path $RepoRoot "test_vectors\pcv1"
if (-not (Test-Path -LiteralPath $VecRoot -PathType Container)) { Die ("missing vectors dir: " + $VecRoot) }

$Ingest = Join-Path $RepoRoot "scripts\watchtower_ingest_inbox_verify_pcv1_v1.ps1"
if (-not (Test-Path -LiteralPath $Ingest -PathType Leaf)) { Die ("missing ingest script: " + $Ingest) }
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

$Inbox = Join-Path $RepoRoot "packets\inbox"
$Proc  = Join-Path $RepoRoot "packets\processed"
$Quar  = Join-Path $RepoRoot "packets\quarantine"
$Rec   = Join-Path $RepoRoot "packets\receipts"
foreach($p in @($Inbox,$Proc,$Quar,$Rec)){ if (-not (Test-Path -LiteralPath $p -PathType Container)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }

$pref = Join-Path $VecRoot "minimal_packet"
$vec = $null
$m0 = Join-Path $pref "manifest.json"
$p0 = Join-Path $pref "packet_id.txt"
$s0 = Join-Path $pref "sha256sums.txt"
if ( (Test-Path -LiteralPath $m0 -PathType Leaf) -and (Test-Path -LiteralPath $p0 -PathType Leaf) -and (Test-Path -LiteralPath $s0 -PathType Leaf) ) { $vec = $pref }
if (-not $vec) {
  $cands = @(@(Get-ChildItem -LiteralPath $VecRoot -Directory -ErrorAction SilentlyContinue))
  foreach($d in @($cands)){
    $m = Join-Path $d.FullName "manifest.json"
    $p = Join-Path $d.FullName "packet_id.txt"
    $s = Join-Path $d.FullName "sha256sums.txt"
    if ( (Test-Path -LiteralPath $m -PathType Leaf) -and (Test-Path -LiteralPath $p -PathType Leaf) -and (Test-Path -LiteralPath $s -PathType Leaf) ) { $vec = $d.FullName; break }
  }
}
if (-not $vec) { Die ("no suitable vector packet found under " + $VecRoot) }

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmssfff")
$testName = ("_selftest_pcv1_" + $stamp)
$dst = Join-Path $Inbox $testName
if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dst | Out-Null

Copy-Item -Path (Join-Path $vec "*") -Destination $dst -Recurse -Force

$PacketIdPath = Join-Path $dst "packet_id.txt"
if (-not (Test-Path -LiteralPath $PacketIdPath -PathType Leaf)) {
  $ls = @(@(Get-ChildItem -LiteralPath $dst -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name))
  Die ("packet_id.txt missing after copy. dst=" + $dst + " contents=[" + ($ls -join ",") + "] vec=" + $vec)
}
$PacketId = (ReadUtf8NoBom $PacketIdPath).Trim()
Write-Host ("SELFTEST_VECTOR=" + $vec) -ForegroundColor Cyan
Write-Host ("SELFTEST_PACKET=" + $dst + " PacketId=" + $PacketId) -ForegroundColor Cyan
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Ingest -RepoRoot $RepoRoot -PacketRoot $dst
if ($LASTEXITCODE -ne 0) { Die ("ingest exited nonzero: " + $LASTEXITCODE) }

if (Test-Path -LiteralPath $dst) { Die "packet dir still in inbox after ingest move" }

$movedOk = @(@(Get-ChildItem -LiteralPath $Proc -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like ("pcv1_OK_" + $PacketId + "_*") }))
if ($movedOk.Count -lt 1) {
  $movedFail = @(@(Get-ChildItem -LiteralPath $Quar -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like ("pcv1_FAIL_" + $PacketId + "_*") }))
  if ($movedFail.Count -ge 1) { Die ("vector packet quarantined (verify failed); PacketId=" + $PacketId) }
  Die ("packet not found in processed or quarantine by PacketId prefix; PacketId=" + $PacketId)
}

$rcps = @(@(Get-ChildItem -LiteralPath $Rec -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like ("pcv1_verify_" + $testName + "_*") }))
if ($rcps.Count -lt 1) { Die ("missing receipt matching pcv1_verify_" + $testName + "_* in " + $Rec) }
$txt = ReadUtf8NoBom $rcps[0].FullName
if ($txt -notmatch "RESULT=OK") { Die ("receipt does not contain RESULT=OK: " + $rcps[0].FullName) }
Write-Host "SELFTEST_OK: ingest moved packet to processed and wrote receipt." -ForegroundColor Green

