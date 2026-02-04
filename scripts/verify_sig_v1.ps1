param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoRoot,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Namespace,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$FilePath,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SigPath,
  [Parameter()][string]$TrustBundlePath,
  [Parameter()][string]$AllowedSignersPath,
  [Parameter()][string]$ReceiptsPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")
if (-not $TrustBundlePath)    { $TrustBundlePath    = Join-Path $RepoRoot "proofs\trust\trust_bundle.json" }
if (-not $AllowedSignersPath) { $AllowedSignersPath = Join-Path $RepoRoot "proofs\trust\allowed_signers" }
if (-not $ReceiptsPath)       { $ReceiptsPath       = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson" }
if (-not (Test-Path -LiteralPath $TrustBundlePath))    { throw "Missing trust_bundle.json: $TrustBundlePath" }
if (-not (Test-Path -LiteralPath $AllowedSignersPath)) { throw "Missing allowed_signers: $AllowedSignersPath" }
if (-not (Test-Path -LiteralPath $FilePath)) { throw "Missing file: $FilePath" }
if (-not (Test-Path -LiteralPath $SigPath))  { throw "Missing sig:  $SigPath" }

# Load trust bundle directly (avoid loader wrappers)
$tb = (Read-Utf8 $TrustBundlePath) | ConvertFrom-Json
try { $null = $tb.principals } catch { throw "trust_bundle missing principals" }
$candidates = @()
foreach ($p in @($tb.principals)) {
  if (-not $p.principal) { continue }
  foreach ($k in @($p.keys)) {
    foreach ($n in @($k.namespaces)) {
      if ($n -eq $Namespace) { $candidates += $p.principal; break }
    }
  }
}
$candidates = @($candidates | Select-Object -Unique)
if ($candidates.Count -eq 0) { throw "no principals in trust_bundle allow namespace: $Namespace" }

$fileHash = Sha256HexPath $FilePath
$sigHash  = Sha256HexPath $SigPath
$tbHash   = Sha256HexPath $TrustBundlePath

$ok = $false; $reason = ""; $identity = ""
foreach ($id in $candidates) {
  try {
    $out = SshYVerifyFile -AllowedSignersPath $AllowedSignersPath -Namespace $Namespace -Identity $id -InFile $FilePath -SigPath $SigPath
    # If it didn't throw, verification passed for this identity
    $ok = $true; $identity = $id
    break
  } catch {
    $reason = $_.Exception.Message
  }
}

$r = @{
  schema = "neverlost.receipt.v1"
  action = "verify_sig"
  time_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  repo_root = $RepoRoot
  namespace = $Namespace
  identity = $identity
  file_path = (RelPathUnix $RepoRoot $FilePath)
  file_sha256 = $fileHash
  sig_path = (RelPathUnix $RepoRoot $SigPath)
  sig_sha256 = $sigHash
  trust_bundle_sha256 = $tbHash
  ok = $ok
  reason = $reason
}
$rh = Write-NeverLostReceipt -ReceiptsPath $ReceiptsPath -Receipt $r
if ($ok) { Write-Host ("OK: verify_sig: PASS as {0}" -f $identity) -ForegroundColor Green } else { Write-Host ("FAIL: verify_sig: {0}" -f $reason) -ForegroundColor Red }
Write-Host ("OK: receipt_hash: {0}" -f $rh) -ForegroundColor DarkGray
if (-not $ok) { exit 2 }
