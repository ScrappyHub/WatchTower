param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoRoot,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$PacketPath,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$EnvelopePath,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SigPath,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Identity,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Namespace,
  [Parameter(Mandatory=$true)][bool]$Ok,
  [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Reason
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Sha256Hex([string]$p) { (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant() }

function AppendLineLfNoBom([string]$path, [string]$line) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  $bytes = $enc.GetBytes($line + "`n")

  if (-not (Test-Path -LiteralPath $path)) {
    [System.IO.File]::WriteAllBytes($path, $bytes)
    return
  }

  $needsLf = $false
  $fsr = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  try {
    if ($fsr.Length -gt 0) {
      $fsr.Position = $fsr.Length - 1
      $last = $fsr.ReadByte()
      if ($last -ne 10) { $needsLf = $true } # 10 = '\n'
    }
  } finally { $fsr.Dispose() }

  $fsw = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
  try {
    if ($needsLf) {
      $lf = $enc.GetBytes("`n")
      $fsw.Write($lf, 0, $lf.Length)
    }
    $fsw.Write($bytes, 0, $bytes.Length)
  } finally { $fsw.Dispose() }
}

if (-not (Test-Path -LiteralPath $RepoRoot))     { throw "Missing RepoRoot: $RepoRoot" }
if (-not (Test-Path -LiteralPath $PacketPath))   { throw "Missing PacketPath: $PacketPath" }
if (-not (Test-Path -LiteralPath $EnvelopePath)) { throw "Missing EnvelopePath: $EnvelopePath" }
if (-not (Test-Path -LiteralPath $SigPath))      { throw "Missing SigPath: $SigPath" }

$TrustDir = Join-Path $RepoRoot "proofs\trust"
$TrustBundlePath = Join-Path $TrustDir "trust_bundle.json"
$AllowedSigners  = Join-Path $TrustDir "allowed_signers"

$tbSha = ""
if (Test-Path -LiteralPath $TrustBundlePath) { $tbSha = Sha256Hex $TrustBundlePath }
$asSha = ""
if (Test-Path -LiteralPath $AllowedSigners)  { $asSha = Sha256Hex $AllowedSigners }

function Rel([string]$abs) {
  $r = $abs
  if ($r.StartsWith($RepoRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
    $r = $r.Substring(($RepoRoot + "\").Length)
  }
  return $r.Replace("\","/")
}

$receipt = [ordered]@{
  schema = "neverlost.receipt.v1"
  action = "nfl/ingest-receipt"
  time_utc = (Get-Date).ToUniversalTime().ToString("o")
  repo_root = $RepoRoot
  ok = [bool]$Ok
  reason = [string]$Reason

  namespace = [string]$Namespace
  identity  = [string]$Identity

  packet_path   = Rel $PacketPath
  envelope_path = Rel $EnvelopePath
  sig_path      = Rel $SigPath

  packet_sha256   = Sha256Hex $PacketPath
  envelope_sha256 = Sha256Hex $EnvelopePath
  sig_sha256      = Sha256Hex $SigPath

  trust_bundle_sha256    = $tbSha
  allowed_signers_sha256 = $asSha
}

$ReceiptsDir = Join-Path $RepoRoot "proofs\receipts"
if (-not (Test-Path -LiteralPath $ReceiptsDir)) { [System.IO.Directory]::CreateDirectory($ReceiptsDir) | Out-Null }
$ReceiptsPath = Join-Path $ReceiptsDir "neverlost.ndjson"

$line = ($receipt | ConvertTo-Json -Depth 50 -Compress)
AppendLineLfNoBom -path $ReceiptsPath -line $line

Write-Host ("OK: ingest-receipt appended: {0}" -f $ReceiptsPath) -ForegroundColor Green
