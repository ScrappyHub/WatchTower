param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoRoot,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$EnvelopePath,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ReadUtf8([string]$p) { [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }
function Sha256Hex([string]$p) { (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant() }

if (-not (Test-Path -LiteralPath $RepoRoot))      { throw "Missing RepoRoot: $RepoRoot" }
if (-not (Test-Path -LiteralPath $EnvelopePath))  { throw "Missing EnvelopePath: $EnvelopePath" }
if (-not (Test-Path -LiteralPath $SigPath))       { throw "Missing SigPath: $SigPath" }

. (Join-Path $RepoRoot "scripts\_lib_neverlost_v1.ps1")

$TrustDir = Join-Path $RepoRoot "proofs\trust"
$AllowedSigners = Join-Path $TrustDir "allowed_signers"
if (-not (Test-Path -LiteralPath $AllowedSigners)) { throw "Missing allowed_signers (run make_allowed_signers_v1.ps1): $AllowedSigners" }

$envJson = (ReadUtf8 $EnvelopePath) | ConvertFrom-Json
if (-not $envJson.schema -or [string]$envJson.schema -ne "packet.envelope.v1") { throw "Envelope schema mismatch (expected packet.envelope.v1)" }
if (-not $envJson.namespace -or [string]$envJson.namespace -ne "packet/envelope") { throw "Envelope namespace mismatch (expected packet/envelope)" }
if (-not $envJson.packet_path) { throw "Envelope missing packet_path" }
if (-not $envJson.packet_sha256) { throw "Envelope missing packet_sha256" }
if (-not $envJson.issuer -or -not $envJson.issuer.principal) { throw "Envelope missing issuer.principal" }

$packetRel = [string]$envJson.packet_path
$packetAbs = Join-Path $RepoRoot ($packetRel.Replace("/","\"))

$ok = $false
$reason = ""
$identity = [string]$envJson.issuer.principal
$namespace = "packet/envelope"

try {
  if (-not (Test-Path -LiteralPath $packetAbs)) { throw "Packet file not found: $packetRel" }

  $want = ([string]$envJson.packet_sha256).ToLowerInvariant()
  $got  = Sha256Hex $packetAbs
  if ($got -ne $want) { throw ("Packet sha256 mismatch: want={0} got={1}" -f $want, $got) }

  $null = SshYVerifyFile -AllowedSignersPath $AllowedSigners -Namespace $namespace -Identity $identity -InFile $EnvelopePath -SigPath $SigPath

  $ok = $true
  Write-Host ("OK: packet envelope verify PASS as {0}" -f $identity) -ForegroundColor Green
}
catch {
  $ok = $false
  $reason = $_.Exception.Message
  Write-Host ("FAIL: packet envelope verify: {0}" -f $reason) -ForegroundColor Red
}
finally {
  & (Join-Path $RepoRoot "scripts\make_ingest_receipt_v1.ps1") `
    -RepoRoot $RepoRoot `
    -PacketPath $packetAbs `
    -EnvelopePath $EnvelopePath `
    -SigPath $SigPath `
    -Identity $identity `
    -Namespace $namespace `
    -Ok $ok `
    -Reason $reason | Out-Null
}

if (-not $ok) { throw $reason }
