param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WriteUtf8NoBom([string]$Path, [string]$Text) {
  $enc = New-Object System.Text.UTF8Encoding($false) # no BOM
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

function Exec([string]$File, [string[]]$Args) {
  & $File @Args
  if ($LASTEXITCODE -ne 0) { throw "Command failed: $File $($Args -join ' ') (exit=$LASTEXITCODE)" }
}

# --- resolve & validate ---
if (-not (Test-Path -LiteralPath $RepoRoot)) { throw "Missing RepoRoot: $RepoRoot" }
Set-Location $RepoRoot

$Target = Join-Path $RepoRoot "scripts\commit_witness.ps1"
if (-not (Test-Path -LiteralPath $Target)) { throw "Missing: $Target" }

# --- backup then rewrite deterministically (no here-strings inside target file) ---
BackupIfExists $Target

# IMPORTANT: file content is built as a line array to avoid parser corruption in the generator.
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

# --- prove file content + parse-check deterministically ---
[ScriptBlock]::Create((ReadUtf8 $Target)) | Out-Null
Write-Host ("OK: wrote + parsed: {0}" -f $Target) -ForegroundColor Green

# --- git: status -> add -> commit -> push ---
Exec "git" @("rev-parse","--is-inside-work-tree") | Out-Null
$st = & git status --porcelain
if (-not ($st | Select-String -SimpleMatch "scripts/commit_witness.ps1")) {
  Write-Host "WARN: no detected change for scripts/commit_witness.ps1 in git status." -ForegroundColor Yellow
}

Exec "git" @("add","--","scripts/commit_witness.ps1")
Exec "git" @("commit","-m","watchtower: add parser-safe commit_witness skeleton (no here-strings)")
Exec "git" @("push")

Write-Host "OK: pushed commit_witness patch" -ForegroundColor Green