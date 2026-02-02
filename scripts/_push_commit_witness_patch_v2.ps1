param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WriteUtf8NoBom([string]$Path, [string]$Text) {
  $enc  = New-Object System.Text.UTF8Encoding($false) # no BOM
  $norm = $Text.Replace("`r`n","`n").Replace("`r","`n")
  [System.IO.File]::WriteAllText($Path, $norm, $enc)
}
function ReadUtf8([string]$Path) {
  return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}
function BackupIfExists([string]$Path) {
  if (Test-Path -LiteralPath $Path) {
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
    $bak = "$Path.bak_$stamp"
    WriteUtf8NoBom $bak (ReadUtf8 $Path)
    Write-Host ("OK: backup: {0}" -f $bak) -ForegroundColor DarkGray
  }
}

function Exec {
  param(
    [Parameter(Mandatory=$true)][string]$File,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args
  )
  $cmd = $File + " " + ($Args -join " ")
  Write-Host ("RUN: {0}" -f $cmd) -ForegroundColor DarkGray

  $out = & $File @Args 2>&1
  $code = $LASTEXITCODE

  if ($out) {
    # keep it deterministic but visible
    $out | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
  }

  if ($code -ne 0) {
    throw ("Command failed (exit={0}): {1}" -f $code, $cmd)
  }
}

# --- validate ---
if (-not (Test-Path -LiteralPath $RepoRoot)) { throw "Missing RepoRoot: $RepoRoot" }
Set-Location $RepoRoot

$Target = Join-Path $RepoRoot "scripts\commit_witness.ps1"
if (-not (Test-Path -LiteralPath $Target)) { throw "Missing: $Target" }

# --- ensure git exists + repo looks like a repo ---
$git = (Get-Command git -ErrorAction SilentlyContinue)
if (-not $git) {
  throw "git not found in PATH for this PowerShell (powershell.exe). Install Git for Windows or add git.exe to PATH."
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ".git"))) {
  throw "No .git folder at RepoRoot: $RepoRoot (not a git repo)."
}

Exec git -C $RepoRoot rev-parse --is-inside-work-tree | Out-Null

# --- backup + rewrite commit_witness.ps1 deterministically ---
BackupIfExists $Target

$lines = @(
  '$ErrorActionPreference="Stop"',
  'Set-StrictMode -Version Latest',
  '',
  'param(',
  '  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$PacketId,',
  '  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$CommitHash,',
  '  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SigPathRel,',
  '  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$OutboxRel,',
  '  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$NflInboxRel,',
  '  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$PledgeLogHash',
  ')',
  '',
  'function Fail([string]$m){ throw $m }',
  'function Ok([string]$m){ Write-Host ("OK: " + $m) -ForegroundColor Green }',
  '',
  '# Repo root resolution (watchtower repo root)',
  '$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)',
  'Set-Location $RepoRoot',
  '',
  '# TODO: implement witness commit logic (Packet Constitution v1 + NFL rules)',
  '# NOTE: This file is intentionally here-string-free to avoid parser corruption.',
  '',
  'Ok ("commit_witness invoked for PacketId=" + $PacketId)',
  'Ok ("CommitHash=" + $CommitHash)',
  'Ok ("SigPathRel=" + $SigPathRel)',
  'Ok ("OutboxRel=" + $OutboxRel)',
  'Ok ("NflInboxRel=" + $NflInboxRel)',
  'Ok ("PledgeLogHash=" + $PledgeLogHash)',
  '',
  '# Hard fail until implemented to avoid partial state.',
  'Fail "commit_witness.ps1: NOT IMPLEMENTED (skeleton written; parser-safe; deterministic)."'
)

WriteUtf8NoBom $Target (($lines -join "`n") + "`n")

# prove file content + parse-check
[ScriptBlock]::Create((ReadUtf8 $Target)) | Out-Null
Write-Host ("OK: wrote + parsed: {0}" -f $Target) -ForegroundColor Green

# --- git stage/commit ---
Exec git -C $RepoRoot status --porcelain

Exec git -C $RepoRoot add -- scripts/commit_witness.ps1

# commit may legitimately fail if nothing changed; detect that deterministically
$st = & git -C $RepoRoot status --porcelain
if (-not ($st | Select-String -SimpleMatch "scripts/commit_witness.ps1")) {
  Write-Host "OK: nothing to commit (scripts/commit_witness.ps1 already matches target content)" -ForegroundColor Green
  exit 0
}

Exec git -C $RepoRoot commit -m "watchtower: add parser-safe commit_witness skeleton (no here-strings)"

# --- push: handle missing upstream cleanly ---
$origin = (& git -C $RepoRoot remote get-url origin 2>$null)
if (-not $origin) {
  throw "No git remote named 'origin'. Set it (git remote add origin <url>) then re-run."
}

# Try normal push; if upstream missing, do -u origin HEAD
$out = & git -C $RepoRoot push 2>&1
$code = $LASTEXITCODE
if ($out) { $out | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray } }

if ($code -ne 0) {
  Write-Host "WARN: git push failed; attempting: git push -u origin HEAD" -ForegroundColor Yellow
  Exec git -C $RepoRoot push -u origin HEAD
}

Write-Host "OK: pushed commit_witness patch" -ForegroundColor Green