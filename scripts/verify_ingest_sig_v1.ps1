param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$PacketDir,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$AllowedSigners,
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
if (-not (Test-Path -LiteralPath $AllowedSigners)) { throw "Missing allowed_signers: $AllowedSigners" }

$commitHashPath = Join-Path $PacketDir "payload\commit_hash.txt"
$sigPath        = Join-Path $PacketDir "signatures\ingest.sig"

if (-not (Test-Path -LiteralPath $commitHashPath)) { throw "Missing: $commitHashPath" }
if (-not (Test-Path -LiteralPath $sigPath)) { throw "Missing: $sigPath" }

Push-Location $PacketDir
try {
  # IMPORTANT:
  # Use cmd.exe 'type' to feed stdin exactly as bytes from the file, avoiding PowerShell string/encoding edge cases.
  $cmdline = @(
    'type "payload\commit_hash.txt" ^| ssh-keygen -Y verify',
    ('-n "{0}"' -f $Namespace),
    ('-f "{0}"' -f $AllowedSigners),
    ('-I "{0}"' -f $Principal),
    ('-s "{0}"' -f "signatures\ingest.sig")
  ) -join " "

  cmd.exe /c $cmdline
  if ($LASTEXITCODE -ne 0) { throw "Signature verify FAILED (exit=$LASTEXITCODE)" }

  Write-Host "OK: Signature verify PASSED" -ForegroundColor Green
} finally {
  Pop-Location
}