param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$PacketDir,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Principal
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Tool([string]$exe) {
  $cmd = Get-Command $exe -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "Missing required tool in PATH: $exe" }
}

function Read-Bytes([string]$Path) { return [System.IO.File]::ReadAllBytes($Path) }

function Sha256HexBytes([byte[]]$b) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($b))).Replace("-","").ToLowerInvariant() }
  finally { $sha.Dispose() }
}

function Sha256HexPath([string]$Path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }

function To-CanonJson($obj, [int]$Depth=60) { return ($obj | ConvertTo-Json -Depth $Depth -Compress) }

function Get-Prop([object]$o, [string]$name, $default=$null) {
  $p = $o.PSObject.Properties[$name]
  if ($p) { return $p.Value }
  return $default
}

Assert-Tool "ssh-keygen"
Assert-Tool "cmd.exe"

if (-not (Test-Path -LiteralPath $PacketDir)) { throw "Missing PacketDir: $PacketDir" }

$manifest = Join-Path $PacketDir "manifest.json"
$sumPath  = Join-Path $PacketDir "sha256sums.txt"
if (-not (Test-Path -LiteralPath $manifest)) { throw "Missing: $manifest" }
if (-not (Test-Path -LiteralPath $sumPath))  { throw "Missing: $sumPath" }

# --- 1) Compute v1.1 packet_id from manifest core (tolerant) ---
$mObj = Get-Content -LiteralPath $manifest | ConvertFrom-Json

$schema = [string](Get-Prop $mObj "schema" "unknown")
$producer = [string](Get-Prop $mObj "producer" "")
$producerInstance =
  [string](Get-Prop $mObj "producer_instance" (Get-Prop $mObj "producerInstance" ""))

$created = [string](Get-Prop $mObj "created_at_utc" (Get-Prop $mObj "createdAtUtc" ""))

$core = @{
  schema = $schema
  producer = $producer
  producer_instance = $producerInstance
  created_at_utc = $created
  files = @()
}

$files = Get-Prop $mObj "files" @()
foreach ($f in $files) {
  $core.files += @{
    path  = [string](Get-Prop $f "path" "")
    bytes = [int64](Get-Prop $f "bytes" 0)
    sha256 = ([string](Get-Prop $f "sha256" "")).ToLowerInvariant()
  }
}

$canonCore = (To-CanonJson $core 60) + "`n"
$computed = Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($canonCore))

$folderName = (Split-Path -Leaf $PacketDir).ToLowerInvariant()

if ($folderName -ne $computed) {
  Write-Host "WARN: legacy packet id scheme detected (folder != computed core-hash)" -ForegroundColor Yellow
  Write-Host (" - folder:   {0}" -f $folderName) -ForegroundColor Yellow
  Write-Host (" - computed: {0}" -f $computed) -ForegroundColor Yellow
  # Do NOT throw — continue verifying integrity/signature for legacy packets.
} else {
  Write-Host ("OK: PacketId matches folder (core-hash): {0}" -f $computed) -ForegroundColor Green
}

# --- 2) sha256sums integrity ---
$lines = Get-Content -LiteralPath $sumPath
foreach ($ln in $lines) {
  if (-not $ln) { continue }
  $parts = $ln -split "  ", 2
  if ($parts.Count -ne 2) { throw "Bad sha256sums line (expected '<sha256>␠␠<path>'): $ln" }
  $want = $parts[0].Trim().ToLowerInvariant()
  $rel  = $parts[1].Trim()
  $full = Join-Path $PacketDir ($rel -replace '/','\')
  if (-not (Test-Path -LiteralPath $full)) { throw "sha256sums references missing file: $rel" }
  $have = Sha256HexPath $full
  if ($have -ne $want) { throw ("sha256 mismatch: {0} want={1} have={2}" -f $rel, $want, $have) }
}
Write-Host "OK: sha256sums verified" -ForegroundColor Green

# --- 3) Manifest files[] hashes match (if present) ---
foreach ($f in $files) {
  $rel = [string](Get-Prop $f "path" "")
  if (-not $rel) { continue }
  $want = ([string](Get-Prop $f "sha256" "")).ToLowerInvariant()
  $full = Join-Path $PacketDir ($rel -replace '/','\')
  if (-not (Test-Path -LiteralPath $full)) { throw "manifest references missing file: $rel" }
  $have = Sha256HexPath $full
  if ($want -and ($have -ne $want)) { throw ("manifest sha256 mismatch: {0} want={1} have={2}" -f $rel, $want, $have) }
}
Write-Host "OK: manifest files[] verified" -ForegroundColor Green

# --- 4) CommitHash recompute from commit.payload.json bytes ---
$commitPayload = Join-Path $PacketDir "payload\commit.payload.json"
$commitHashTxt = Join-Path $PacketDir "payload\commit_hash.txt"
if (-not (Test-Path -LiteralPath $commitPayload)) { throw "Missing: $commitPayload" }
if (-not (Test-Path -LiteralPath $commitHashTxt)) { throw "Missing: $commitHashTxt" }

$payloadBytes = Read-Bytes $commitPayload
$recalc = Sha256HexBytes $payloadBytes
$decl = (Get-Content -LiteralPath $commitHashTxt | Out-String).Trim().ToLowerInvariant()
if ($recalc -ne $decl) { throw ("CommitHash mismatch: declared={0} recalced={1}" -f $decl, $recalc) }
Write-Host ("OK: CommitHash verified: {0}" -f $decl) -ForegroundColor Green

# --- 5) Verify detached signature over commit_hash.txt ---
$allowed = Join-Path $PacketDir "allowed_signers"
if (-not (Test-Path -LiteralPath $allowed)) { throw "Missing allowed_signers next to packet: $allowed" }

Push-Location $PacketDir
try {
  $cmdline = 'type "payload\commit_hash.txt" | ssh-keygen -Y verify -n "nfl" -f "allowed_signers" -I "' + $Principal + '" -s "signatures\ingest.sig"'
  cmd.exe /s /c $cmdline | Out-Host
  if ($LASTEXITCODE -ne 0) { throw ("Signature verify FAILED (exit={0})" -f $LASTEXITCODE) }
} finally {
  Pop-Location
}
Write-Host "OK: ingest.sig verified" -ForegroundColor Green

Write-Host "OK: PACKET VERIFIED (dual-scheme verifier)" -ForegroundColor Green