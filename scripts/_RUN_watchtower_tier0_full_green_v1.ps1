param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Die([string]$m){ throw ("WT FULL_GREEN FAIL: " + $m) }
function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null }
}
function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  EnsureDir (Split-Path -Parent $Path)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}
function Sha256HexBytes([byte[]]$b){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $h = $sha.ComputeHash($b)
    return ([System.BitConverter]::ToString($h) -replace "-","").ToLowerInvariant()
  } finally { $sha.Dispose() }
}
function Sha256HexFile([string]$Path){
  return (Sha256HexBytes ([System.IO.File]::ReadAllBytes($Path)))
}
function ParseGateFile([string]$Path){
  $t=$null; $e=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$t,[ref]$e)
  if(@(@($e)).Count -gt 0){ Die ("PARSE_GATE_FAIL: " + (@(@($e))[0].Message) + " @ " + $Path) }
}
function JsonEscape([string]$s){
  if($null -eq $s){ return "" }
  $x = $s.Replace('\','\\').Replace('"','\"')
  $x = $x.Replace("`r","").Replace("`n","\n").Replace("`t","\t")
  return $x
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

# product surface
$Verify = Join-Path $RepoRoot "scripts\watchtower_verify_packet_v1.ps1"
$Ingest = Join-Path $RepoRoot "scripts\watchtower_ingest_inbox_verify_pcv1_v1.ps1"
$Self   = Join-Path $RepoRoot "scripts\_selftest_watchtower_ingest_move_pcv1_v1.ps1"

foreach($p in @($Verify,$Ingest,$Self)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_FILE: " + $p) }
  ParseGateFile $p
}
Write-Host "PARSE_OK: verify+ingest+selftest" -ForegroundColor Green

# receipts root
$utc = (Get-Date).ToUniversalTime()
$runId = $utc.ToString("yyyyMMdd_HHmmssfffZ")
$RunDir = Join-Path $RepoRoot ("proofs\receipts\watchtower_tier0\" + $runId)
EnsureDir $RunDir

$psExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$stdoutPath = Join-Path $RunDir "selftest.stdout.txt"
$stderrPath = Join-Path $RunDir "selftest.stderr.txt"

# Run selftest in fresh child powershell.exe and capture output deterministically.
$p = Start-Process -FilePath $psExe -ArgumentList @(
  "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
  "-File",$Self,
  "-RepoRoot",$RepoRoot
) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

$exitCode = [int]$p.ExitCode

# Normalize newlines to LF + ensure trailing LF (deterministic text discipline)
$enc = New-Object System.Text.UTF8Encoding($false)
$so = ""
$se = ""
if(Test-Path -LiteralPath $stdoutPath -PathType Leaf){ $so = [System.IO.File]::ReadAllText($stdoutPath,$enc) }
if(Test-Path -LiteralPath $stderrPath -PathType Leaf){ $se = [System.IO.File]::ReadAllText($stderrPath,$enc) }
WriteUtf8NoBomLf $stdoutPath $so
WriteUtf8NoBomLf $stderrPath $se

# Extract key markers
$packetId = ""
$movedTo  = ""
$foundIn  = ""
if($so -match '(?im)^\s*SELFTEST_PACKET=.*?\bPacketId=(?<id>[0-9a-f]{64})\b'){ $packetId = $Matches["id"].ToLowerInvariant() }
if($so -match '(?im)^\s*MOVED_TO_RECEIPTS:\s*(?<p>.+?)\s*$'){ $movedTo = $Matches["p"] }
if($so -match '(?im)^\s*FOUND_IN_RECEIPTS:\s*(?<p>.+?)\s*$'){ $foundIn = $Matches["p"] }

# Git head (best-effort; blank if git unavailable)
$gitHead = ""
try {
  Push-Location -LiteralPath $RepoRoot
  try {
    $gh = & git rev-parse HEAD
    if($LASTEXITCODE -eq 0){ $gitHead = ("" + $gh).Trim() }
  } finally { Pop-Location }
} catch { $gitHead = "" }

# Hash key artifacts (stable list order)
$files = @(
  "docs\WATCHTOWER_TERMINAL_STATE_LAW_PCV1_V1.md",
  "scripts\watchtower_verify_packet_v1.ps1",
  "scripts\watchtower_ingest_inbox_verify_pcv1_v1.ps1",
  "scripts\_selftest_watchtower_ingest_move_pcv1_v1.ps1",
  "test_vectors\pcv1\minimal_packet\manifest.json",
  "test_vectors\pcv1\minimal_packet\sha256sums.txt",
  "test_vectors\pcv1\minimal_packet\packet_id.txt"
)

$items = @()
foreach($rel in $files){
  $abs = Join-Path $RepoRoot $rel
  if(Test-Path -LiteralPath $abs -PathType Leaf){
    $items += @{ rel=$rel; sha256=(Sha256HexFile $abs) }
  } else {
    $items += @{ rel=$rel; sha256="" }
  }
}

# Write a single deterministic NDJSON receipt line (stable key order)
$nd = Join-Path $RepoRoot "proofs\receipts\watchtower_tier0.ndjson"
EnsureDir (Split-Path -Parent $nd)

# Build files JSON array (stable order)
$fJson = ""
for($i=0;$i -lt @(@($items)).Count;$i++){
  $it = $items[$i]
  $one = ('{"path":"' + (JsonEscape $it.rel) + '","sha256":"' + (JsonEscape $it.sha256) + '"}')
  if($i -eq 0){ $fJson = $one } else { $fJson = $fJson + "," + $one }
}
$line =
  '{"schema":"watchtower.tier0.run.v1"' +
  ',"run_id":"' + (JsonEscape $runId) + '"' +
  ',"utc":"' + (JsonEscape ($utc.ToString("o"))) + '"' +
  ',"git_head":"' + (JsonEscape $gitHead) + '"' +
  ',"selftest_exit":' + $exitCode +
  ',"packet_id":"' + (JsonEscape $packetId) + '"' +
  ',"moved_to_receipts":"' + (JsonEscape $movedTo) + '"' +
  ',"found_in_receipts":"' + (JsonEscape $foundIn) + '"' +
  ',"stdout_path":"' + (JsonEscape ("proofs/receipts/watchtower_tier0/" + $runId + "/selftest.stdout.txt")) + '"' +
  ',"stderr_path":"' + (JsonEscape ("proofs/receipts/watchtower_tier0/" + $runId + "/selftest.stderr.txt")) + '"' +
  ',"files":[' + $fJson + ']' +
  '}'

# Append-only
$prev = ""
if(Test-Path -LiteralPath $nd -PathType Leaf){ $prev = [System.IO.File]::ReadAllText($nd,$enc) }
$append = $prev
if(-not [string]::IsNullOrEmpty($append) -and -not $append.EndsWith("`n")){ $append += "`n" }
$append += $line + "`n"
WriteUtf8NoBomLf $nd $append

Write-Host ("RECEIPT_OK: " + $nd) -ForegroundColor Green
Write-Host ("RUN_DIR: " + $RunDir) -ForegroundColor Green

if($exitCode -ne 0){
  Die ("SELFTEST_FAIL exit=" + $exitCode)
}

Write-Host "FULL_GREEN_OK: WatchTower Tier-0 runner + receipt bundle emitted." -ForegroundColor Green
