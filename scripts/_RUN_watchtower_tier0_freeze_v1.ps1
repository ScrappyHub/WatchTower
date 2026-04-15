param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WT-Die([string]$m){
  throw ("WATCHTOWER_TIER0_FREEZE_FAIL: " + $m)
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

function WT-AppendNdjson([string]$Path,[string]$Line){
  $dir = Split-Path -Parent $Path
  if($dir){ WT-EnsureDir $dir }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = ($Line -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::AppendAllText($Path,$t,$enc)
}

function WT-Sha256HexBytes([byte[]]$b){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($b)) -replace "-","").ToLowerInvariant()
  }
  finally {
    $sha.Dispose()
  }
}

function WT-Sha256HexFile([string]$Path){
  return WT-Sha256HexBytes ([System.IO.File]::ReadAllBytes($Path))
}

function WT-CanonicalJson([hashtable]$Map){
  $keys = New-Object System.Collections.Generic.List[string]
  foreach($k in $Map.Keys){ [void]$keys.Add([string]$k) }
  $keys.Sort()

  $parts = New-Object System.Collections.Generic.List[string]
  foreach($k in $keys){
    $nameJson = ConvertTo-Json ([string]$k) -Compress
    $valJson  = ConvertTo-Json $Map[$k] -Compress -Depth 20
    [void]$parts.Add(($nameJson + ":" + $valJson))
  }
  return "{" + ($parts -join ",") + "}"
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

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  WT-Die ("INVALID_REPO_ROOT: " + $RepoRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$FullGreen = Join-Path $RepoRoot "scripts\_RUN_watchtower_live_state_full_green_v1.ps1"
$BindingSelf = Join-Path $RepoRoot "scripts\_selftest_watchtower_device_binding_v1.ps1"

foreach($p in @($FullGreen,$BindingSelf)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    WT-Die ("MISSING_REQUIRED_SCRIPT: " + $p)
  }
  WT-ParseGateFile $p
}

$FreezeRoot = Join-Path $RepoRoot "proofs\freeze\watchtower_tier0_v1"
if(Test-Path -LiteralPath $FreezeRoot -PathType Container){
  Remove-Item -LiteralPath $FreezeRoot -Recurse -Force
}
WT-EnsureDir $FreezeRoot

$RunUtc = [datetime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
$StdoutPath = Join-Path $FreezeRoot "full_green.stdout.txt"
$StderrPath = Join-Path $FreezeRoot "full_green.stderr.txt"
$BindingStdout = Join-Path $FreezeRoot "device_binding.stdout.txt"
$BindingStderr = Join-Path $FreezeRoot "device_binding.stderr.txt"
$ShaPath = Join-Path $FreezeRoot "sha256sums.txt"
$ManifestPath = Join-Path $FreezeRoot "freeze_manifest.json"
$ReceiptPath = Join-Path $RepoRoot "proofs\receipts\watchtower_tier0_freeze.ndjson"

Write-Host "FREEZE_PHASE:FULL_GREEN_START" -ForegroundColor Yellow
$p = Start-Process `
  -FilePath $PSExe `
  -ArgumentList @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy","Bypass",
    "-File",$FullGreen,
    "-RepoRoot",$RepoRoot
  ) `
  -NoNewWindow `
  -RedirectStandardOutput $StdoutPath `
  -RedirectStandardError $StderrPath `
  -PassThru `
  -Wait

if($null -eq $p){
  WT-Die "FULL_GREEN_NO_PROCESS"
}
if($p.ExitCode -ne 0){
  WT-Die ("FULL_GREEN_FAILED_EXIT_" + $p.ExitCode)
}

$stdout = [System.IO.File]::ReadAllText($StdoutPath,[System.Text.Encoding]::UTF8)
if($stdout -notmatch 'WATCHTOWER_LIVE_STATE_FULL_GREEN_OK'){
  WT-Die "FULL_GREEN_TOKEN_MISSING"
}
Write-Host "FREEZE_PHASE:FULL_GREEN_DONE" -ForegroundColor Yellow

Write-Host "FREEZE_PHASE:BINDING_SELFTEST_START" -ForegroundColor Yellow
$p2 = Start-Process `
  -FilePath $PSExe `
  -ArgumentList @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy","Bypass",
    "-File",$BindingSelf,
    "-RepoRoot",$RepoRoot
  ) `
  -NoNewWindow `
  -RedirectStandardOutput $BindingStdout `
  -RedirectStandardError $BindingStderr `
  -PassThru `
  -Wait

if($null -eq $p2){
  WT-Die "BINDING_SELFTEST_NO_PROCESS"
}
if($p2.ExitCode -ne 0){
  WT-Die ("BINDING_SELFTEST_FAILED_EXIT_" + $p2.ExitCode)
}

$stdout2 = [System.IO.File]::ReadAllText($BindingStdout,[System.Text.Encoding]::UTF8)
if($stdout2 -notmatch 'WATCHTOWER_DEVICE_BINDING_SELFTEST_OK'){
  WT-Die "BINDING_SELFTEST_TOKEN_MISSING"
}
Write-Host "FREEZE_PHASE:BINDING_SELFTEST_DONE" -ForegroundColor Yellow

$EvidenceFiles = @(
  "full_green.stdout.txt",
  "full_green.stderr.txt",
  "device_binding.stdout.txt",
  "device_binding.stderr.txt"
)

$shaLines = @()
foreach($rel in $EvidenceFiles){
  $path = Join-Path $FreezeRoot $rel
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){
    WT-Die ("MISSING_EVIDENCE_FILE: " + $path)
  }
  $shaLines += (WT-Sha256HexFile $path) + "  " + $rel
}
[System.IO.File]::WriteAllLines($ShaPath,$shaLines,(New-Object System.Text.UTF8Encoding($false)))

$manifestMap = [ordered]@{
  freeze_schema = "watchtower.tier0.freeze.manifest.v1"
  generated_utc = $RunUtc
  binding_selftest_stdout_sha256 = WT-Sha256HexFile $BindingStdout
  full_green_stdout_sha256 = WT-Sha256HexFile $StdoutPath
  sha256sums_sha256 = WT-Sha256HexFile $ShaPath
  status = "ok"
}
$manifestJson = WT-CanonicalJson $manifestMap
WT-WriteUtf8NoBomLf -Path $ManifestPath -Text $manifestJson

$receiptMap = [ordered]@{
  receipt_schema = "watchtower.tier0.freeze.receipt.v1"
  freeze_root = $FreezeRoot
  generated_utc = $RunUtc
  full_green_stdout_sha256 = WT-Sha256HexFile $StdoutPath
  binding_selftest_stdout_sha256 = WT-Sha256HexFile $BindingStdout
  manifest_sha256 = WT-Sha256HexFile $ManifestPath
  sha256sums_sha256 = WT-Sha256HexFile $ShaPath
  status = "ok"
}
$receiptJson = WT-CanonicalJson $receiptMap
WT-AppendNdjson -Path $ReceiptPath -Line $receiptJson

Write-Host "WATCHTOWER_TIER0_FREEZE_OK" -ForegroundColor Green
Write-Host ("FREEZE_ROOT: " + $FreezeRoot) -ForegroundColor Green
Write-Host ("MANIFEST: " + $ManifestPath) -ForegroundColor Green
Write-Host ("SHA256SUMS: " + $ShaPath) -ForegroundColor Green
Write-Host ("RECEIPT: " + $ReceiptPath) -ForegroundColor Green
