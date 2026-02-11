param([Parameter(Mandatory=$true)][string]$PacketRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Die($m){ throw $m }

$manifest = Join-Path $PacketRoot "manifest.json"
$idPath   = Join-Path $PacketRoot "packet_id.txt"
$sums     = Join-Path $PacketRoot "sha256sums.txt"

if(-not (Test-Path $manifest)){ Die "missing manifest" }
if(-not (Test-Path $idPath)){ Die "missing packet_id.txt" }
if(-not (Test-Path $sums)){ Die "missing sha256sums.txt" }

$sha = [Security.Cryptography.SHA256]::Create()
$bytes = [IO.File]::ReadAllBytes($manifest)
$hash = $sha.ComputeHash($bytes)
$id = ($hash | ForEach-Object { $_.ToString("x2") }) -join ""

$expect = [IO.File]::ReadAllText($idPath).Trim()

if($id -ne $expect){ Die "PacketId mismatch" }

Write-Host "VERIFY_OK"