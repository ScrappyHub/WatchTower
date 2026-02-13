param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$InboxRel = "packets/inbox",
  [Parameter(Mandatory=$false)][string]$ReceiptsRel = "packets/receipts"
)

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

$dirs = @(@(Get-ChildItem -LiteralPath $Inbox -Directory -ErrorAction SilentlyContinue))
Write-Host ("INBOX_PACKET_DIRS: " + $dirs.Count) -ForegroundColor Cyan
foreach($d in @($dirs)){
  $pkt = $d.FullName
  $idp = Join-Path $pkt "packet_id.txt"
  $pid = ""
  if (Test-Path -LiteralPath $idp -PathType Leaf) { $pid = (ReadUtf8NoBom $idp).Trim() }
  $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
  $rcp = Join-Path $Rec ("pcv1_verify_" + $d.Name + "_" + $stamp + ".txt")
  $old = $ErrorActionPreference
  try {
    $ErrorActionPreference="Continue"
    & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Verify -PacketRoot $pkt 1> $rcp 2>> $rcp
    $ec = $LASTEXITCODE
    if ($ec -eq 0) { Write-Host ("PCV1_OK: " + $d.Name + " PacketId=" + $pid) -ForegroundColor Green } else { Write-Host ("PCV1_FAIL: " + $d.Name + " exit=" + $ec + " PacketId=" + $pid) -ForegroundColor Red }
  } finally { $ErrorActionPreference=$old }
}
