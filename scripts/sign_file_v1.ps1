param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoRoot,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Namespace,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$FilePath,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SigPath,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Principal,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$KeyId,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$KeyPriv,
  [Parameter()][string]$TrustBundlePath,
  [Parameter()][string]$ReceiptsPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")
if (-not $TrustBundlePath) { $TrustBundlePath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json" }
if (-not $ReceiptsPath)    { $ReceiptsPath    = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson" }
if (-not (Test-Path -LiteralPath $TrustBundlePath)) { throw "Missing trust_bundle.json: $TrustBundlePath" }
if (-not (Test-Path -LiteralPath $FilePath)) { throw "Missing file: $FilePath" }
if (-not (Test-Path -LiteralPath $KeyPriv))  { throw "Missing key:  $KeyPriv" }

# Load trust_bundle directly; validate principal->keys->key_id exists
$tb = (Read-Utf8 $TrustBundlePath) | ConvertFrom-Json
try { $null = $tb.principals } catch { throw "trust_bundle missing principals" }
$p = @($tb.principals) | Where-Object { $_.principal -eq $Principal } | Select-Object -First 1
if (-not $p) { throw "principal not found in trust_bundle: $Principal" }
$k = @($p.keys) | Where-Object { $_.key_id -eq $KeyId } | Select-Object -First 1
if (-not $k) { throw "key_id not found for principal in trust_bundle: $KeyId" }
$ns = @($k.namespaces)

# Sign using stdin-compatible wrapper
$out = SshYSignFile -KeyPriv $KeyPriv -Namespace $Namespace -InFile $FilePath -SigOut $SigPath

$fileHash = Sha256HexPath $FilePath
$sigHash  = Sha256HexPath $SigPath
$tbHash   = Sha256HexPath $TrustBundlePath
$r = @{
  schema = "neverlost.receipt.v1"
  action = "sign_file"
  time_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  repo_root = $RepoRoot
  namespace = $Namespace
  principal = $Principal
  key_id = $KeyId
  file_path = (RelPathUnix $RepoRoot $FilePath)
  file_sha256 = $fileHash
  sig_path = (RelPathUnix $RepoRoot $SigPath)
  sig_sha256 = $sigHash
  trust_bundle_sha256 = $tbHash
  ok = $true
  reason = ""
}
$rh = Write-NeverLostReceipt -ReceiptsPath $ReceiptsPath -Receipt $r
Write-Host ("OK: sign_file: {0}" -f (RelPathUnix $RepoRoot $SigPath)) -ForegroundColor Green
Write-Host ("OK: receipt_hash: {0}" -f $rh) -ForegroundColor DarkGray
