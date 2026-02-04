param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here "_lib_neverlost_v1.ps1")
$trust = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$as    = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$tbHash = Sha256HexPath $trust
$asHash = if (Test-Path -LiteralPath $as) { Sha256HexPath $as } else { "" }
Write-Host "NeverLost v1"
Write-Host ("trust_bundle_sha256    : " + $tbHash)
Write-Host ("allowed_signers_sha256 : " + $asHash)