param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoRoot,

  # Positive = sign with repo authority key and expect verify PASS
  # Negative = sign with wrong key and expect verify FAIL (receipt ok:false)
  [Parameter()][ValidateSet("Positive","Negative")][string]$Mode = "Positive",

  # Default = repo authority key (must match trust_bundle.json for Identity)
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
function TrimCrLf([string]$s){
  return ($s -as [string]).Replace("`r","").Trim()
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

# ---- load trust bundle + expected pubkey for Identity ----
$tb = (ReadUtf8 $TrustBundlePath) | ConvertFrom-Json
if (-not $tb) { Die "Could not parse trust_bundle.json" }

$principals = @(@($tb.principals))
if ($principals.Count -lt 1) { Die "trust_bundle.json principals empty" }

$match = $null
foreach ($p in $principals) {
  if ([string]$p.principal -eq [string]$Identity) { $match = $p; break }
}
if (-not $match) { Die ("Identity not present in trust_bundle.json principals: {0}" -f $Identity) }

$keys = @(@($match.keys))
if ($keys.Count -lt 1) { Die ("Principal '{0}' has no keys in trust_bundle.json" -f $Identity) }

$expectedPub = [string]@($keys)[0].pubkey
if (-not $expectedPub -or $expectedPub.Trim().Length -eq 0) { Die "trust_bundle.json key missing pubkey" }
$expectedPub = $expectedPub.Trim()

# ---- choose working dirs ----
$Outbox  = Join-Path $RepoRoot "packets\outbox"
EnsureDir $Outbox

$Scratch = Join-Path $RepoRoot "scripts\_scratch"
EnsureDir $Scratch

# ---- decide signing key per mode ----
$effectiveSigningKey = $SigningKey

if ($Mode -eq "Negative") {
  # Generate an ephemeral WRONG key in scripts/_scratch (ignored).
  # IMPORTANT: use minimal ssh-keygen args (some builds reject extras).
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
  $badKey = Join-Path $Scratch ("_selftest_badkey_ed25519_{0}" -f $stamp)
  # PS5.1 native-arg edge case: empty argv elements (-N '') can be dropped for native exes -> 'Too many arguments'.
  # Use Start-Process with ONE argument string so ssh-keygen receives -N "" deterministically.
  $arg = ('-q -t ed25519 -f "{0}" -N "" -C "{1}"' -f $badKey, "watchtower-selftest-badkey")
  $p = Start-Process -FilePath $sshkeygen.Source -ArgumentList $arg -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) { Die ('ssh-keygen keygen failed (exit={0})' -f $p.ExitCode) }
  # Sanity: key MUST be unencrypted. If encrypted, -y will prompt/fail; treat as failure.
  $pubOut = & $sshkeygen.Source -y -f $badKey 2>$null
  if (-not $pubOut) { Die ('Bad key appears encrypted or unreadable (expected unencrypted). badKey={0}' -f $badKey) }
  if (-not (Test-Path -LiteralPath $badKey -PathType Leaf)) { Die "Failed to create bad key: $badKey" }
  if (-not (Test-Path -LiteralPath ($badKey + ".pub") -PathType Leaf)) { Die "Failed to create bad key pub: $($badKey + ".pub")" }

  $effectiveSigningKey = $badKey
}

if (-not (Test-Path -LiteralPath $effectiveSigningKey -PathType Leaf)) { Die "SigningKey missing: $effectiveSigningKey" }
$SigningPub = $effectiveSigningKey + ".pub"
if (-not (Test-Path -LiteralPath $SigningPub -PathType Leaf)) { Die "SigningKey pub missing: $SigningPub" }

$gotPub = (TrimCrLf (ReadUtf8 $SigningPub))

if ($Mode -eq "Positive") {
  if ($gotPub -ne $expectedPub) {
    Die ("SigningKey.pub does not match trust bundle pubkey for Identity '{0}'.`nEXPECTED: {1}`nGOT:      {2}`nFIX: Provide -SigningKey pointing at the Watchtower authority private key for EXPECTED pubkey." -f $Identity, $expectedPub, $gotPub)
  }
} else {
  if ($gotPub -eq $expectedPub) {
    Die ("Negative mode refused: provided/created SigningKey.pub MATCHES the trust bundle key for Identity '{0}'. Need a WRONG key." -f $Identity)
  }
}

# ---- create minimal packet payload ----
$stamp2 = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$packetAbs = Join-Path $Outbox ("_selftest_packet_v1_{0}_{1}.txt" -f $Mode.ToLowerInvariant(), $stamp2)
$packetText = "watchtower packets selftest v1`nmode={0}`nutc={1}`n" -f $Mode, (Get-Date).ToUniversalTime().ToString("o")
WriteUtf8NoBomLf $packetAbs ($packetText)

$packetSha = Sha256Hex $packetAbs
$packetRel = RelSlash $packetAbs $RepoRoot

# ---- create minimal envelope JSON ----
$envAbs = Join-Path $Outbox ("_selftest_envelope_v1_{0}_{1}.json" -f $Mode.ToLowerInvariant(), $stamp2)

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

Write-Host ("[{0}] Signing file {1}" -f $Mode, $envAbs) -ForegroundColor Cyan
& $sshkeygen.Source -Y sign -f $effectiveSigningKey -n $Namespace -I $Identity $envAbs | Out-Null
if (-not (Test-Path -LiteralPath $sigAbs -PathType Leaf)) { Die "Signature not produced: $sigAbs" }

# ---- receipt count BEFORE ----
$before = 0
if (Test-Path -LiteralPath $ReceiptPath -PathType Leaf) {
  $before = @((Get-Content -LiteralPath $ReceiptPath -ErrorAction Stop)).Count
}

# ---- verify using Watchtower verifier (IN-PROCESS) ----
$verifyThrew = $false
$verifyErr   = ""

try {
  & $VerifyScript -RepoRoot $RepoRoot -EnvelopePath $envAbs -SigPath $sigAbs
} catch {
  $verifyThrew = $true
  $verifyErr = $_.Exception.Message
}

if ($Mode -eq "Positive") {
  if ($verifyThrew) { Die ("Positive mode expected PASS but verify threw: {0}" -f $verifyErr) }
} else {
  if (-not $verifyThrew) { Die "Negative mode expected verify FAIL, but it PASSED." }
  Write-Host ("[Negative] OK: verify failed as expected: {0}" -f $verifyErr) -ForegroundColor Yellow
}

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

if ($Mode -eq "Positive") {
  if (-not [bool]$last.ok) { Die "Positive mode expected receipt ok:true but got ok:false." }
  Write-Host "OK: selftest PASS (Positive): trusted key signed, verify PASS, receipt ok:true and matched." -ForegroundColor Green
} else {
  if ([bool]$last.ok) { Die "Negative mode expected receipt ok:false but got ok:true." }
  Write-Host "OK: selftest PASS (Negative): wrong key signed, verify FAIL, receipt ok:false and matched." -ForegroundColor Green
}

Write-Host ("mode:     {0}" -f $Mode) -ForegroundColor Cyan
Write-Host ("packet:   {0}" -f $packetRel) -ForegroundColor Cyan
Write-Host ("envelope: {0}" -f (RelSlash $envAbs $RepoRoot)) -ForegroundColor Cyan
Write-Host ("sig:      {0}" -f (RelSlash $sigAbs $RepoRoot)) -ForegroundColor Cyan
Write-Host ("receipts: {0}" -f (RelSlash $ReceiptPath $RepoRoot)) -ForegroundColor Cyan
