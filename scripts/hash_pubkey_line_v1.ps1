param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$PubKeyPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $PubKeyPath)) { throw "Missing pubkey: $PubKeyPath" }
$line = ([System.IO.File]::ReadAllText($PubKeyPath, [System.Text.Encoding]::UTF8)).Trim()
$bytes = [System.Text.Encoding]::UTF8.GetBytes($line + "`n")
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $h = $sha.ComputeHash($bytes); $hex = ([BitConverter]::ToString($h) -replace "-", "").ToLowerInvariant() } finally { $sha.Dispose() }
Write-Host ("PUBKEY: {0}" -f $line) -ForegroundColor Cyan
Write-Host ("PUBKEY_SHA256: {0}" -f $hex) -ForegroundColor Green
