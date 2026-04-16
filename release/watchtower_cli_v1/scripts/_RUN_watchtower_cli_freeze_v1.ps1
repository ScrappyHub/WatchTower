param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WT-Die([string]$m){
  throw ("WATCHTOWER_CLI_FREEZE_FAIL: " + $m)
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

function WT-AppendUtf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $dir = Split-Path -Parent $Path
  if($dir){ WT-EnsureDir $dir }
  [System.IO.File]::AppendAllText($Path,$t,$enc)
}

function WT-Sha256HexFile([string]$Path){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    try {
      return (($sha.ComputeHash($fs) | ForEach-Object { $_.ToString("x2") }) -join "")
    }
    finally {
      $fs.Dispose()
    }
  }
  finally {
    $sha.Dispose()
  }
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  WT-Die ("INVALID_REPO_ROOT: " + $RepoRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$Selftest = Join-Path $RepoRoot "scripts\_selftest_watchtower_cli_v1.ps1"

if(-not (Test-Path -LiteralPath $Selftest -PathType Leaf)){
  WT-Die ("SELFTEST_MISSING: " + $Selftest)
}

$FreezeRoot = Join-Path $RepoRoot "proofs\freeze\watchtower_cli_v1"
if(Test-Path -LiteralPath $FreezeRoot -PathType Container){
  Remove-Item -LiteralPath $FreezeRoot -Recurse -Force
}
WT-EnsureDir $FreezeRoot

$stdoutPath = Join-Path $FreezeRoot "stdout.txt"
$stderrPath = Join-Path $FreezeRoot "stderr.txt"
$shaPath = Join-Path $FreezeRoot "sha256sums.txt"
$receiptPath = Join-Path $RepoRoot "proofs\receipts\watchtower_cli_freeze.ndjson"

$p = Start-Process `
  -FilePath $PSExe `
  -ArgumentList @("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$Selftest,"-RepoRoot",$RepoRoot) `
  -RedirectStandardOutput $stdoutPath `
  -RedirectStandardError $stderrPath `
  -Wait `
  -PassThru `
  -NoNewWindow

if($p.ExitCode -ne 0){
  WT-Die ("SELFTEST_FAILED_EXIT_" + $p.ExitCode)
}

$out = [System.IO.File]::ReadAllText($stdoutPath,[System.Text.Encoding]::UTF8)
if($out -notmatch 'WATCHTOWER_CLI_SELFTEST_OK'){
  WT-Die "SELFTEST_TOKEN_MISSING"
}

$stdoutHash = WT-Sha256HexFile $stdoutPath
$stderrHash = WT-Sha256HexFile $stderrPath

$shaLines = @(
  ($stdoutHash + "  stdout.txt"),
  ($stderrHash + "  stderr.txt")
)
[System.IO.File]::WriteAllLines($shaPath,$shaLines,(New-Object System.Text.UTF8Encoding($false)))

$utc = [DateTime]::UtcNow.ToString("o")
$receipt = '{"schema":"watchtower.cli.freeze.receipt.v1","utc":"' + $utc + '","freeze_root":"' + $FreezeRoot.Replace('\','\\') + '","stdout_sha256":"' + $stdoutHash + '","stderr_sha256":"' + $stderrHash + '","status":"ok"}'
WT-AppendUtf8NoBomLf -Path $receiptPath -Text $receipt

Write-Host "WATCHTOWER_CLI_FREEZE_OK" -ForegroundColor Green
Write-Host ("FREEZE_ROOT: " + $FreezeRoot) -ForegroundColor Green
Write-Host ("STDOUT: " + $stdoutPath) -ForegroundColor Green
Write-Host ("STDERR: " + $stderrPath) -ForegroundColor Green
Write-Host ("SHA256SUMS: " + $shaPath) -ForegroundColor Green
Write-Host ("RECEIPT: " + $receiptPath) -ForegroundColor Green
