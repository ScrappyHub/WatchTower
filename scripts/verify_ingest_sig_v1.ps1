param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$PacketDir,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Principal,
  [string]$Namespace = "nfl"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Tool([string]$exe) {
  $cmd = Get-Command $exe -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "Missing required tool in PATH: $exe" }
}

Assert-Tool "ssh-keygen"
Assert-Tool "cmd.exe"

if (-not (Test-Path -LiteralPath $PacketDir)) { throw "Missing PacketDir: $PacketDir" }

# We REQUIRE allowed_signers to be next to the packet root (relative-path verification)
$allowed = Join-Path $PacketDir "allowed_signers"
if (-not (Test-Path -LiteralPath $allowed)) { throw "Missing allowed_signers: $allowed" }

$commitHashPath = Join-Path $PacketDir "payload\commit_hash.txt"
$sigPath        = Join-Path $PacketDir "signatures\ingest.sig"

if (-not (Test-Path -LiteralPath $commitHashPath)) { throw "Missing: $commitHashPath" }
if (-not (Test-Path -LiteralPath $sigPath)) { throw "Missing: $sigPath" }

Push-Location $PacketDir
try {
  # IMPORTANT:
  # - Use cmd.exe so we can use native 'type | ssh-keygen ...' piping
  # - Use ONLY relative paths inside the packet root (avoids cmd path parsing bugs)
  # - Use /s so cmd preserves quoting rules
  $cmdline = 'type "payload\commit_hash.txt" | ssh-keygen -Y verify -n "' + $Namespace + '" -f "allowed_signers" -I "' + $Principal + '" -s "signatures\ingest.sig"'
  cmd.exe /s /c $cmdline | Out-Host

  if ($LASTEXITCODE -ne 0) { throw ("Signature verify FAILED (exit={0})" -f $LASTEXITCODE) }

  Write-Host "OK: Signature verify PASSED" -ForegroundColor Green
} finally {
  Pop-Location
}