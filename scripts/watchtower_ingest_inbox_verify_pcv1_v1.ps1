param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$InboxRel = "packets/inbox",
  [Parameter(Mandatory=$false)][string]$ReceiptsRel = "packets/receipts"
,
  [string]$PacketRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw ("WT_INGEST_PCV1_FAIL: " + $m) }
function ReadUtf8NoBom([string]$p){ return [System.IO.File]::ReadAllText($p,(New-Object System.Text.UTF8Encoding($false))) }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Inbox = Join-Path $RepoRoot (($InboxRel -replace "/","\") )
$Rec   = Join-Path $RepoRoot (($ReceiptsRel -replace "/","\") )
$Verify = Join-Path $RepoRoot "scripts\watchtower_verify_packet_v1.ps1"
if (-not (Test-Path -LiteralPath $Verify -PathType Leaf)) { Die ("missing verify script: " + $Verify) }
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

if (-not (Test-Path -LiteralPath $Inbox -PathType Container)) { Write-Host "NO_INBOX_DIR" -ForegroundColor DarkYellow; return }
if (-not (Test-Path -LiteralPath $Rec -PathType Container)) { New-Item -ItemType Directory -Force -Path $Rec | Out-Null }

$OnlyPkt = $null
if (-not [string]::IsNullOrWhiteSpace($PacketRoot)) { $OnlyPkt = (Resolve-Path -LiteralPath $PacketRoot).Path }
if ($OnlyPkt) {
  $dirs = @(@(Get-Item -LiteralPath $OnlyPkt -ErrorAction Stop))
} else {
$dirs = @(@(Get-ChildItem -LiteralPath $Inbox -Directory -ErrorAction SilentlyContinue))
}
Write-Host ("INBOX_PACKET_DIRS: " + $dirs.Count) -ForegroundColor Cyan
foreach($d in @($dirs)){
  $pkt = $d.FullName
  $idp = Join-Path $pkt "packet_id.txt"
  $pktId = ""
  if (Test-Path -LiteralPath $idp -PathType Leaf) { $pktId = (ReadUtf8NoBom $idp).Trim() }
  $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
  $rcp = Join-Path $Rec ("pcv1_verify_" + $d.Name + "_" + $stamp + ".txt")
  $old = $ErrorActionPreference
  try {
    $ErrorActionPreference="Continue"
    $global:LASTEXITCODE = 0
    try { & $Verify -PacketRoot $pkt | Out-Host } catch { Die ("verify failed: " + $_.Exception.Message) }
    $global:LASTEXITCODE = 0
    $ec = $LASTEXITCODE
    if ($ec -eq 0) { Write-Host ("PCV1_OK: " + $d.Name + " PacketId=" + $pktId) -ForegroundColor Green } else { Write-Host ("PCV1_FAIL: " + $d.Name + " exit=" + $ec + " PacketId=" + $pktId) -ForegroundColor Red }
    # --- PacketRoot move (deterministic): if caller pinned a packet dir, move it out of inbox ---
    if (-not [string]::IsNullOrWhiteSpace($PacketRoot)) {
      $src = (Resolve-Path -LiteralPath $PacketRoot -ErrorAction Stop).Path
      $receipts = Join-Path $RepoRoot "packets\receipts"
      if (-not (Test-Path -LiteralPath $receipts -PathType Container)) { New-Item -ItemType Directory -Force -Path $receipts | Out-Null }
      $name = Split-Path -Leaf $src
      $dst = Join-Path $receipts $name
      if (Test-Path -LiteralPath $dst) { throw ("WT INGEST PCV1 FAIL: receipts destination already exists: "+$dst) }
      Move-Item -LiteralPath $src -Destination $dst -Force
      Write-Host ("MOVED_TO_RECEIPTS: "+$dst) -ForegroundColor Green
    }
  } finally { $ErrorActionPreference=$old }
}
