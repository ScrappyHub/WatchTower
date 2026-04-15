param(
  [Parameter(Mandatory=$true)]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WT-Die([string]$m){
  throw ("WATCHTOWER_PACKET_REPAIR_FAIL: " + $m)
}

function WT-EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function WT-WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }

  $dir = Split-Path -Parent $Path
  if($dir){ WT-EnsureDir $dir }

  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function WT-Sha256Hex([byte[]]$bytes){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace "-","").ToLowerInvariant()
  }
  finally {
    $sha.Dispose()
  }
}

function WT-ParseGateFile([string]$Path){
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $e = $err[0]
    throw ("PARSE_FAIL: {0}:{1}:{2}: {3}" -f $Path,$e.Extent.StartLineNumber,$e.Extent.StartColumnNumber,$e.Message)
  }
}

if($RepoRoot -is [System.IO.FileSystemInfo]){
  $RepoRoot = $RepoRoot.FullName
}
$RepoRoot = [string]$RepoRoot
if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  WT-Die ("INVALID_REPO_ROOT: " + $RepoRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$TvDir   = Join-Path $RepoRoot "test_vectors\watchtower\packet_v1\positive"
$GoodSrc = Join-Path $RepoRoot "test_vectors\watchtower\state\v1\ok.ndjson"
$Payload = Join-Path $TvDir "payload\telemetry.ndjson"
$ShaFile = Join-Path $TvDir "sha256sums.txt"

if(-not (Test-Path -LiteralPath $TvDir -PathType Container)){ WT-Die ("MISSING_PACKET_DIR: " + $TvDir) }
if(-not (Test-Path -LiteralPath $GoodSrc -PathType Leaf)){ WT-Die ("MISSING_GOOD_VECTOR: " + $GoodSrc) }
if(-not (Test-Path -LiteralPath $Payload -PathType Leaf)){ WT-Die ("MISSING_PAYLOAD: " + $Payload) }

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

Write-Host "PIPELINE_PHASE:PAYLOAD_REPLACE_START" -ForegroundColor Yellow

$good = [System.IO.File]::ReadAllText($GoodSrc,[System.Text.Encoding]::UTF8)
$good = ($good -replace "`r`n","`n") -replace "`r","`n"

WT-WriteUtf8NoBomLf -Path $Payload -Text $good

Write-Host "PIPELINE_PHASE:PAYLOAD_REPLACE_DONE" -ForegroundColor Yellow

Write-Host "PIPELINE_PHASE:SHA256_REBUILD_START" -ForegroundColor Yellow

$files = @(
  "manifest.json",
  "packet_id.txt",
  "payload\telemetry.ndjson"
)

$lines = @()

foreach($f in $files){
  $path = Join-Path $TvDir $f
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){
    WT-Die ("MISSING_FILE: " + $path)
  }

  $bytes = [System.IO.File]::ReadAllBytes($path)
  $hash = WT-Sha256Hex $bytes
  $rel = $f -replace "\\","/"
  $lines += ($hash + "  " + $rel)
}

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($ShaFile,$lines,$enc)

Write-Host "PIPELINE_PHASE:SHA256_REBUILD_DONE" -ForegroundColor Yellow

Write-Host "PIPELINE_PHASE:RESIGN_START" -ForegroundColor Yellow

$Sign = Join-Path $RepoRoot "scripts\watchtower_sign_telemetry_packet_v1.ps1"
if(-not (Test-Path -LiteralPath $Sign -PathType Leaf)){
  WT-Die ("SIGN_SCRIPT_MISSING: " + $Sign)
}

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Sign -RepoRoot $RepoRoot -PacketDir $TvDir
if($LASTEXITCODE -ne 0){
  WT-Die ("RESIGN_FAILED_EXIT_" + $LASTEXITCODE)
}

Write-Host "PIPELINE_PHASE:RESIGN_DONE" -ForegroundColor Yellow

Write-Host "PIPELINE_PHASE:VERIFY_START" -ForegroundColor Yellow

$Verify = Join-Path $RepoRoot "scripts\watchtower_verify_telemetry_packet_v1.ps1"
if(-not (Test-Path -LiteralPath $Verify -PathType Leaf)){
  WT-Die ("VERIFY_SCRIPT_MISSING: " + $Verify)
}

& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Verify -RepoRoot $RepoRoot -PacketDir $TvDir
if($LASTEXITCODE -ne 0){
  WT-Die ("VERIFY_FAILED_EXIT_" + $LASTEXITCODE)
}

Write-Host "PIPELINE_PHASE:VERIFY_DONE" -ForegroundColor Yellow
Write-Host "WATCHTOWER_PACKET_REPAIR_AND_VERIFY_OK" -ForegroundColor Green
