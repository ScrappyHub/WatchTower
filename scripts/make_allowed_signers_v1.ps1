param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ReadUtf8([string]$p) { [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }
function WriteUtf8NoBom([string]$p, [string]$s) {
  $enc  = New-Object System.Text.UTF8Encoding($false)
  $norm = $s.Replace("`r`n","`n").Replace("`r","`n")
  [System.IO.File]::WriteAllText($p, $norm, $enc)
}
function ParseCheck([string]$p) { [ScriptBlock]::Create((ReadUtf8 $p)) | Out-Null }

function Backup([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
  $bak = "$p.bak_$stamp"
  WriteUtf8NoBom $bak (ReadUtf8 $p)
  Write-Host ("OK: backup: {0}" -f $bak) -ForegroundColor DarkGray
  return $bak
}

if (-not (Test-Path -LiteralPath $RepoRoot)) { throw "Missing RepoRoot: $RepoRoot" }

$TrustDir = Join-Path $RepoRoot "proofs\trust"
$TrustBundlePath    = Join-Path $TrustDir "trust_bundle.json"
$AllowedSignersPath = Join-Path $TrustDir "allowed_signers"

if (-not (Test-Path -LiteralPath $TrustBundlePath)) { throw "Missing trust_bundle: $TrustBundlePath" }

$tb = (ReadUtf8 $TrustBundlePath) | ConvertFrom-Json
if (-not $tb.principals) { throw "trust_bundle missing principals" }

Backup $AllowedSignersPath | Out-Null

$lines = New-Object System.Collections.Generic.List[string]

$principals = @($tb.principals) | Sort-Object principal
foreach ($p in $principals) {
  if (-not $p.principal) { throw "trust_bundle principal entry missing .principal" }
  $identity = [string]$p.principal

  $keys = @($p.keys)
  if (-not $keys) { continue }

  $keys = $keys | Sort-Object key_id
  foreach ($k in $keys) {
    if (-not $k.key_id) { throw ("trust_bundle key missing key_id for principal: {0}" -f $identity) }

    $pub = $null
    if ($k.pubkey)         { $pub = [string]$k.pubkey }
    elseif ($k.public_key) { $pub = [string]$k.public_key }
    elseif ($k.key)        { $pub = [string]$k.key }
    if (-not $pub) { throw ("trust_bundle key missing pubkey/public_key/key for key_id '{0}' principal '{1}'" -f $k.key_id, $identity) }

    $parts = @($pub -split "\s+")
    if ($parts.Count -lt 2) { throw ("Invalid pubkey format for key_id '{0}' principal '{1}': {2}" -f $k.key_id, $identity, $pub) }
    $keyType = $parts[0]
    $keyB64  = $parts[1]

    $ns = @()
    if ($k.namespaces) { $ns = @($k.namespaces) }
    $ns = @($ns | Where-Object { $_ -and ([string]$_).Trim().Length -gt 0 } | ForEach-Object { [string]$_ } | Sort-Object -Unique)

    $opt = $null
    if ($ns.Count -gt 0) { $opt = 'namespaces="{0}"' -f ($ns -join ",") }

    $comment = ('key_id={0}' -f [string]$k.key_id)

    if ($opt) { $line = ('{0} {1} {2} {3} {4}' -f $identity, $opt, $keyType, $keyB64, $comment) }
    else      { $line = ('{0} {1} {2} {3}' -f $identity, $keyType, $keyB64, $comment) }

    $lines.Add($line)
  }
}

if ($lines.Count -eq 0) { throw "No allowed_signers lines generated from trust_bundle (no principals/keys?)" }

WriteUtf8NoBom $AllowedSignersPath (($lines -join "`n") + "`n")
ParseCheck $AllowedSignersPath

# sha for determinism visibility
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $AllowedSignersPath).Hash.ToLowerInvariant()

Write-Host ("OK: allowed_signers: {0}" -f (Join-Path "proofs\trust" "allowed_signers")) -ForegroundColor Green
Write-Host ("OK: allowed_signers_sha256: {0}" -f $sha) -ForegroundColor DarkGray
$code = (0)
if ($MyInvocation.InvocationName -eq '.') { return $code } else { exit $code }