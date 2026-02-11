param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$vec = Join-Path $RepoRoot "test_vectors\pcv1\minimal_packet"
New-Item -ItemType Directory -Force -Path $vec | Out-Null

$manifest = Join-Path $vec "manifest.json"
$idPath   = Join-Path $vec "packet_id.txt"
$sums     = Join-Path $vec "sha256sums.txt"

[IO.File]::WriteAllText($manifest,'{"schema":"minimal"}',[Text.UTF8Encoding]::new($false))

$sha = [Security.Cryptography.SHA256]::Create()
$id  = ($sha.ComputeHash([IO.File]::ReadAllBytes($manifest)) | % { $_.ToString("x2") }) -join ""

[IO.File]::WriteAllText($idPath,$id,[Text.UTF8Encoding]::new($false))

$sum = "$id  manifest.json`n"
[IO.File]::WriteAllText($sums,$sum,[Text.UTF8Encoding]::new($false))

$verify = Join-Path $RepoRoot "scripts\watchtower_verify_packet_v1.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verify -PacketRoot $vec

if($LASTEXITCODE -ne 0){ throw "selftest failed" }

Write-Host "SELFTEST_OK"