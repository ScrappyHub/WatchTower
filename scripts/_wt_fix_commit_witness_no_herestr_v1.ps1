$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Target = Join-Path (Split-Path -Parent $PSScriptRoot) "scripts\commit_witness.ps1"
if(-not(Test-Path -LiteralPath $Target)){ throw "Missing: $Target" }

$bak = $Target + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $Target -Destination $bak -Force
Write-Host ("OK: backup -> " + $bak)

# Rewrite commit_witness.ps1 without here-strings (line-array only)
$New = @(
  '$ErrorActionPreference="Stop"',
  'Set-StrictMode -Version Latest',
  '',
  'param(',
  '  [Parameter(Mandatory=$true)][string]$PacketId,',
  '  [Parameter(Mandatory=$true)][string]$CommitHash,',
  '  [Parameter(Mandatory=$true)][string]$SigPathRel,',
  '  [Parameter(Mandatory=$true)][string]$OutboxRel,',
  '  [Parameter(Mandatory=$true)][string]$NflInboxRel,',
  '  [Parameter(Mandatory=$true)][string]$PledgeLogHash',
  ')',
  '',
  'function Fail([string]$m){ throw $m }',
  'function Ok([string]$m){ Write-Host ("OK: " + $m) }',
  '',
  '# Root resolution (repo root)' ,
  '$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)',
  'Set-Location $RepoRoot',
  '',
  '# TODO: implement witness commit logic (packet constitution + nfl rules)' ,
  '# NOTE: This file is intentionally here-string-free to avoid parser corruption.' ,
  '',
  'Ok ("commit_witness invoked for PacketId=" + $PacketId)' ,
  'Ok ("CommitHash=" + $CommitHash)' ,
  'Ok ("SigPathRel=" + $SigPathRel)' ,
  'Ok ("OutboxRel=" + $OutboxRel)' ,
  'Ok ("NflInboxRel=" + $NflInboxRel)' ,
  'Ok ("PledgeLogHash=" + $PledgeLogHash)' ,
  '',
  '# Hard fail until implemented to avoid partial state.' ,
  'Fail "commit_witness.ps1: NOT IMPLEMENTED (skeleton written to remove here-string parser failure)."'
)

Set-Content -LiteralPath $Target -Value ($New -join "`n") -Encoding UTF8 -NoNewline
Ok "rewrote scripts\commit_witness.ps1 (no here-strings)"

# Parse check
pwsh -NoProfile -Command "[ScriptBlock]::Create((Get-Content -Raw -LiteralPath '$Target')) | Out-Null; 'OK: parse clean'"