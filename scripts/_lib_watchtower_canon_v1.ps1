Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function Write-Utf8NoBom([string]$Path, [string]$Content) {
  $dir = Split-Path -Parent $Path
  if ($dir) { Ensure-Dir $dir }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $norm = $Content.Replace("`r`n","`n").Replace("`r","`n")
  [System.IO.File]::WriteAllText($Path, $norm, $enc)
}

function Read-Bytes([string]$Path) { return [System.IO.File]::ReadAllBytes($Path) }

function Sha256HexBytes([byte[]]$b) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($b))).Replace("-","").ToLowerInvariant() }
  finally { $sha.Dispose() }
}

function Sha256HexPath([string]$Path) {
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function To-CanonJson($obj, [int]$Depth=60) {
  # Caller must supply [ordered] hashtables for deterministic key order.
  return ($obj | ConvertTo-Json -Depth $Depth -Compress)
}

function Assert-Tool([string]$exe) {
  $cmd = Get-Command $exe -ErrorAction SilentlyContinue
  if (-not $cmd) { throw "Missing required tool in PATH: $exe" }
}

function RelPathUnix([string]$Base, [string]$Full) {
  $rel = $Full.Substring($Base.Length).TrimStart('\')
  return ($rel -replace '\\','/')
}

function Write-Sha256Sums([string]$PacketDir) {
  # Deterministic order by relative path (unix separators)
  # MUST exclude sha256sums.txt itself (canonical rule)
  $all = Get-ChildItem -LiteralPath $PacketDir -File -Recurse |
    Where-Object { $_.Name -ne "sha256sums.txt" } |
    Sort-Object FullName

  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($f in $all) {
    $rel = RelPathUnix $PacketDir $f.FullName
    $h = Sha256HexPath $f.FullName
    $lines.Add(("{0}  {1}" -f $h, $rel))
  }

  $out = Join-Path $PacketDir "sha256sums.txt"
  Write-Utf8NoBom $out (($lines -join "`n") + "`n")
}

function Build-ManifestV1_1([string]$PacketDir, [string]$Producer, [string]$ProducerInstance, [string]$PacketId) {
  # packet_manifest.v1
  # Non-circular: manifest lists EVERY file except itself.
  $created = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

  $files = New-Object System.Collections.Generic.List[object]

  $all = Get-ChildItem -LiteralPath $PacketDir -File -Recurse |
    Where-Object { $_.Name -ne "manifest.json" } |
    Sort-Object FullName

  foreach ($f in $all) {
    $rel = RelPathUnix $PacketDir $f.FullName
    $h = Sha256HexPath $f.FullName
    $bytes = [int64]$f.Length
    $files.Add([ordered]@{ path=$rel; bytes=$bytes; sha256=$h })
  }

  $m = [ordered]@{
    schema = "packet_manifest.v1"
    packet_id = $PacketId
    producer = $Producer
    producer_instance = $ProducerInstance
    created_at_utc = $created
    files = @($files)
  }

  $json = (To-CanonJson $m 60) + "`n"
  Write-Utf8NoBom (Join-Path $PacketDir "manifest.json") $json
}

function PacketIdFromManifest([string]$PacketDir) {
  # PacketId = sha256( canonical_bytes(manifest.json) )
  $m = Join-Path $PacketDir "manifest.json"
  if (-not (Test-Path -LiteralPath $m)) { throw "Missing manifest.json: $m" }
  $bytes = Read-Bytes $m
  return Sha256HexBytes $bytes
}

function SshYSignFile([string]$KeyPath, [string]$Namespace, [string]$SignerIdentity, [string]$FileToSign, [string]$SigOut) {
  Assert-Tool "ssh-keygen"
  if (-not (Test-Path -LiteralPath $KeyPath)) { throw "Missing signing key: $KeyPath" }
  if (-not (Test-Path -LiteralPath $FileToSign)) { throw "Missing file to sign: $FileToSign" }

  $defaultSig = "$FileToSign.sig"
  if (Test-Path -LiteralPath $defaultSig) { Remove-Item -LiteralPath $defaultSig -Force }

  & ssh-keygen -Y sign -f $KeyPath -n $Namespace -I $SignerIdentity $FileToSign | Out-Null

  if (-not (Test-Path -LiteralPath $defaultSig)) {
    throw "Expected signature output not found: $defaultSig"
  }

  $sigDir = Split-Path -Parent $SigOut
  if ($sigDir) { Ensure-Dir $sigDir }
  if (Test-Path -LiteralPath $SigOut) { Remove-Item -LiteralPath $SigOut -Force }
  Move-Item -LiteralPath $defaultSig -Destination $SigOut -Force
}