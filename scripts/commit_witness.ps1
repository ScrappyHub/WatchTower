$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Repo = Split-Path -Parent $PSScriptRoot
Set-Location $Repo

function Assert-GitRepo([string]$Path){
  $p = $Path
  while($true){
    if(Test-Path -LiteralPath (Join-Path $p ".git")){ return }
    $parent = Split-Path -Parent $p
    if(-not $parent -or $parent -eq $p){ break }
    $p = $parent
  }
  throw "Not a git repository: $Path (missing .git). Run: git init (and commit baseline) in repo root."
}

# Ensure bootstrap exists
$Bootstrap = Join-Path $Repo "scripts\bootstrap_nfl_skeleton.ps1"
if(-not(Test-Path -LiteralPath $Bootstrap)){ throw "Missing: scripts\bootstrap_nfl_skeleton.ps1" }

# Overwrite commit_witness.ps1 with hardened canonical version
$Commit = Join-Path $Repo "scripts\commit_witness.ps1"

@'
param(
  [Parameter(Mandatory=$true)][string]$PacketId,
  [Parameter(Mandatory=$true)][string]$CommitHash,
  [Parameter(Mandatory=$true)][string]$SigPathRel,
  [Parameter(Mandatory=$true)][string]$OutboxRel,
  [Parameter(Mandatory=$false)][string]$NflInboxRel="",
  [Parameter(Mandatory=$false)][string]$PledgeLogHash=""
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Repo = Split-Path -Parent $PSScriptRoot
Set-Location $Repo

function Assert-GitRepo([string]$Path){
  $p = $Path
  while($true){
    if(Test-Path -LiteralPath (Join-Path $p ".git")){ return }
    $parent = Split-Path -Parent $p
    if(-not $parent -or $parent -eq $p){ break }
    $p = $parent
  }
  throw "Not a git repository: $Path (missing .git). Run: git init in repo root."
}

# 0) Ensure folders + witness ledger exist
& (Join-Path $Repo "scripts\bootstrap_nfl_skeleton.ps1")

# 1) Append witness IN-PROCESS (prevents empty-string CLI collapse)
& (Join-Path $Repo "scripts\append_witness.ps1") `
  -PacketId $PacketId `
  -CommitHash $CommitHash `
  -SigPathRel $SigPathRel `
  -OutboxRel $OutboxRel `
  -NflInboxRel $NflInboxRel `
  -PledgeLogHash $PledgeLogHash

# 2) Git commit witness (fail-fast if not repo)
Assert-GitRepo $Repo

git add witness/witness.ndjson | Out-Null
git commit -m ("NFL Witness: packet {0} commit {1}" -f $PacketId, $CommitHash) | Out-Null

Write-Host "OK: witness appended + committed to repo"