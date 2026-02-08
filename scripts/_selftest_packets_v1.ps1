param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoRoot,

  # IMPORTANT: This must be the PRIVATE KEY that corresponds to the Watchtower authority pubkey in proofs/trust/trust_bundle.json.
  [Parameter()][ValidateNotNullOrEmpty()][string]$SigningKey = (Join-Path $RepoRoot "proofs\keys\watchtower_authority_ed25519"),

  [Parameter()][ValidateNotNullOrEmpty()][string]$Identity   = "single-tenant/watchtower_authority/authority/watchtower",
  [Parameter()][ValidateNotNullOrEmpty()][string]$Namespace  = "packet/envelope"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $norm = $Text.Replace("`r`n","`n").Replace("`r","`n")
  [System.IO.File]::WriteAllText($Path,$norm,$enc)
}
function ReadUtf8([string]$Path){
  [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8)
}
function Sha256Hex([string]$Path){
  (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
function EnsureDir([string]$p){
  if (-not (Test-Path -LiteralPath $p -PathType Container)) { [System.IO.Directory]::CreateDirectory($p) | Out-Null }
}
function RelSlash([string]$abs,[string]$root){
  $r = $abs
  if ($r.StartsWith($root + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
    $r = $r.Substring(($root + "\").Length)
  }
  return $r.Replace("\","/")
}

# ---- preflight ----
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Die "Missing RepoRoot: $RepoRoot" }

$VerifyScript = Join-Path $RepoRoot "scripts\verify_packet_envelope_v1.ps1"
if (-not (Test-Path -LiteralPath $VerifyScript -PathType Leaf)) { Die "Missing: $VerifyScript" }

$TrustBundlePath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
if (-not (Test-Path -LiteralPath $TrustBundlePath -PathType Leaf)) { Die "Missing trust_bundle.json: $TrustBundlePath" }

$AllowedSigners = Join-Path $RepoRoot "proofs\trust\allowed_signers"
if (-not (Test-Path -LiteralPath $AllowedSigners -PathType Leaf)) { Die "Missing allowed_signers (run make_allowed_signers_v1.ps1): $AllowedSigners" }

$ReceiptPath = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"
EnsureDir (Split-Path -Parent $ReceiptPath)

$sshkeygen = (Get-Command ssh-keygen -ErrorAction SilentlyContinue)
if (-not $sshkeygen) { Die "ssh-keygen not found on PATH." }

if (-not (Test-Path -LiteralPath $SigningKey -PathType Leaf)) { Die "SigningKey missing: $SigningKey" }
$SigningPub = $SigningKey + ".pub"
if (-not (Test-Path -LiteralPath $SigningPub -PathType Leaf)) { Die "SigningKey pub missing: $SigningPub" }

# ---- enforce: SigningKey.pub MUST match trust bundle pubkey for Identity ----
$tb = (ReadUtf8 $TrustBundlePath) | ConvertFrom-Json
if (-not $tb) { Die "Could not parse trust_bundle.json" }

$principals = @(@($tb.principals))
if ($principals.Count -lt 1) { Die "trust_bundle.json principals empty" }

$match = $null
foreach ($p in $principals) {
  if ([string]$p.principal -eq [string]$Identity) { $match = $p; break }
}
if (-not $match) {
  Die ("Identity not present in trust_bundle.json principals: {0}" -f $Identity)
}

$keys = @(@($match.keys))
if ($keys.Count -lt 1) { Die ("Principal '{0}' has no keys in trust_bundle.json" -f $Identity) }

# Use first key entry as canonical authority key for this identity
$expectedPub = [string]@($keys)[0].pubkey
if (-not $expectedPub -or $expectedPub.Trim().Length -eq 0) { Die "trust_bundle.json key missing pubkey" }

$gotPub = (ReadUtf8 $SigningPub).Replace("`r","").Trim()
if ($gotPub -ne $expectedPub.Trim()) {
  Die ("SigningKey.pub does not match trust bundle pubkey for Identity '{0}'.`nEXPECTED: {1}`nGOT:      {2}`nFIX: Run selftest with -SigningKey pointing at the Watchtower authority private key that corresponds to the EXPECTED pubkey." -f $Identity, $expectedPub.Trim(), $gotPub)
}

# ---- choose target dirs ----
$Outbox = Join-Path $RepoRoot "packets\outbox"
EnsureDir $Outbox

# ---- create minimal packet payload ----
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$packetAbs = Join-Path $Outbox ("_selftest_packet_v1_{0}.txt" -f $stamp)
$packetText = "watchtower packets selftest v1`nutc={0}`n" -f (Get-Date).ToUniversalTime().ToString("o")
WriteUtf8NoBomLf $packetAbs ($packetText)

$packetSha = Sha256Hex $packetAbs
$packetRel = RelSlash $packetAbs $RepoRoot

# ---- create minimal envelope JSON ----
$envAbs = Join-Path $Outbox ("_selftest_envelope_v1_{0}.json" -f $stamp)

$envObj = [ordered]@{
  schema        = "packet.envelope.v1"
  namespace     = "packet/envelope"
  created_utc   = (Get-Date).ToUniversalTime().ToString("o")
  packet_path   = $packetRel
  packet_sha256 = $packetSha
  issuer        = [ordered]@{ principal = [string]$Identity }
}

$envJson = ($envObj | ConvertTo-Json -Depth 20)
WriteUtf8NoBomLf $envAbs ($envJson + "`n")

# ---- sign envelope (REQUIRE -I; no fallback) ----
$sigAbs = $envAbs + ".sig"
if (Test-Path -LiteralPath $sigAbs) { Remove-Item -LiteralPath $sigAbs -Force }

Write-Host ("Signing file {0}" -f $envAbs) -ForegroundColor Cyan
& $sshkeygen.Source -Y sign -f $SigningKey -n $Namespace -I $Identity $envAbs | Out-Null

if (-not (Test-Path -LiteralPath $sigAbs -PathType Leaf)) { Die "Signature not produced: $sigAbs" }

# ---- receipt count BEFORE ----
$before = 0
if (Test-Path -LiteralPath $ReceiptPath -PathType Leaf) {
  $before = @((Get-Content -LiteralPath $ReceiptPath -ErrorAction Stop)).Count
}

# ---- verify using Watchtower verifier (IN-PROCESS) ----
& $VerifyScript -RepoRoot $RepoRoot -EnvelopePath $envAbs -SigPath $sigAbs

# ---- assert receipt appended + matches this envelope ----
$after = 0
if (Test-Path -LiteralPath $ReceiptPath -PathType Leaf) {
  $after = @((Get-Content -LiteralPath $ReceiptPath -ErrorAction Stop)).Count
} else {
  Die "Receipt file not found after verify: $ReceiptPath"
}
if ($after -lt ($before + 1)) {
  Die ("Receipt not appended. before={0} after={1} path={2}" -f $before, $after, $ReceiptPath)
}

$lastLine = (Get-Content -LiteralPath $ReceiptPath -ErrorAction Stop | Select-Object -Last 1)
if (-not $lastLine -or $lastLine.Trim().Length -eq 0) { Die "Last receipt line empty." }

$last = $lastLine | ConvertFrom-Json
if (-not $last) { Die "Could not parse last receipt JSON line." }

if ([string]$last.action -ne "nfl/ingest-receipt") { Die ("Receipt action mismatch: {0}" -f [string]$last.action) }

$wantEnvSha = Sha256Hex $envAbs
if ([string]$last.envelope_sha256 -ne $wantEnvSha) {
  Die ("Receipt does not match envelope sha256. want={0} got={1}" -f $wantEnvSha, [string]$last.envelope_sha256)
}

Write-Host "OK: selftest PASS (packet+envelope signed with TRUSTED key, verified, receipt appended + matched)." -ForegroundColor Green
Write-Host ("packet:   {0}" -f $packetRel) -ForegroundColor Cyan
Write-Host ("envelope: {0}" -f (RelSlash $envAbs $RepoRoot)) -ForegroundColor Cyan
Write-Host ("sig:      {0}" -f (RelSlash $sigAbs $RepoRoot)) -ForegroundColor Cyan
Write-Host ("receipts:  {0}" -f (RelSlash $ReceiptPath $RepoRoot)) -ForegroundColor Cyan

