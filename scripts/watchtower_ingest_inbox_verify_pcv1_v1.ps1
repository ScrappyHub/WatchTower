param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$false)][string]$InboxRel = "packets/inbox",
  [Parameter(Mandatory=$false)][string]$ReceiptsRel = "packets/receipts"
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw ("WT_INGEST_PCV1_FAIL: " + $m) }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Inbox = Join-Path $RepoRoot ($InboxRel.Replace("/","\"))
$Rec   = Join-Path $RepoRoot ($ReceiptsRel.Replace("/","\"))
if(-not (Test-Path -LiteralPath $Inbox -PathType Container)) { Write-Host "NO_INBOX_DIR" -ForegroundColor DarkYellow; return }
if(-not (Test-Path -LiteralPath $Rec -PathType Container)) { New-Item -ItemType Directory -Force -Path $Rec | Out-Null }
$verify = Join-Path $RepoRoot "scripts\watchtower_verify_packet_v1.ps1"
if(-not (Test-Path -LiteralPath $verify -PathType Leaf)) { Die "missing verify script" }
$psExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$dirs = @(@(Get-ChildItem -LiteralPath $Inbox -Directory -ErrorAction SilentlyContinue))
Write-Host ("INBOX_PACKET_DIRS: " + $dirs.Count) -ForegroundColor Cyan
foreach($d in @($dirs)){
  $pkt = $d.FullName
  $idp = Join-Path $pkt "packet_id.txt"
  $PacketId = ""
  if (Test-Path -LiteralPath $idp -PathType Leaf) { $PacketId = [System.IO.File]::ReadAllText($idp,(New-Object System.Text.UTF8Encoding($false))).Trim() }
  $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
  $rcp = Join-Path $Rec ("pcv1_verify_" + ($d.Name) + "_" + $stamp + ".txt")
  $old = $ErrorActionPreference
  try {
    $ErrorActionPreference="Continue"
    & $psExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $verify -PacketRoot $pkt 1> $rcp 2>> $rcp
    $ec = $LASTEXITCODE
    if ($ec -eq 0) { Write-Host ("PCV1_OK: " + $d.Name + " PacketId=" + $PacketId) -ForegroundColor Green } else { Write-Host ("PCV1_FAIL: " + $d.Name + " exit=" + $ec + " PacketId=" + $PacketId) -ForegroundColor Red }
  } finally { $ErrorActionPreference=$old }
}
