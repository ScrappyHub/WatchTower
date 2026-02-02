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

function Read-Bytes([string]$Path) {
  return [System.IO.File]::ReadAllBytes($Path)
}

function Sha256HexBytes([byte[]]$b) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($b))).Replace("-","").ToLowerInvariant() }
  finally { $sha.Dispose() }
}

function Sha256HexPath([string]$Path) {
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function To-CanonJson([hashtable]$obj, [int]$Depth=40) {
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
  $all = Get-ChildItem -LiteralPath $PacketDir -File -Recurse | Sort-Object FullName
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($f in $all) {
    $rel = RelPathUnix $PacketDir $f.FullName
    $h = Sha256HexPath $f.FullName
    $lines.Add(("{0}  {1}" -f $h, $rel))
  }
  $out = Join-Path $PacketDir "sha256sums.txt"
  Write-Utf8NoBom $out (($lines -join "`n") + "`n")
}

function PacketSha([string]$PacketDir) {
  # Packet id = sha256 over sha256sums.txt bytes
  $p = Join-Path $PacketDir "sha256sums.txt"
  if (-not (Test-Path -LiteralPath $p)) { throw "Missing sha256sums.txt: $p" }
  return Sha256HexBytes (Read-Bytes $p)
}

function SshYSignFile([string]$KeyPath, [string]$Namespace, [string]$SignerIdentity, [string]$FileToSign, [string]$SigOut) {
  Assert-Tool "ssh-keygen"
  if (-not (Test-Path -LiteralPath $KeyPath)) { throw "Missing signing key: $KeyPath" }
  if (-not (Test-Path -LiteralPath $FileToSign)) { throw "Missing file to sign: $FileToSign" }

  # ssh-keygen -Y sign writes "<file>.sig" next to the file by default on many builds.
  $defaultSig = "$FileToSign.sig"
  if (Test-Path -LiteralPath $defaultSig) { Remove-Item -LiteralPath $defaultSig -Force }

  # Most compatible flags: -Y sign -f key -n namespace -I identity file
  & ssh-keygen -Y sign -f $KeyPath -n $Namespace -I $SignerIdentity $FileToSign | Out-Null

  if (-not (Test-Path -LiteralPath $defaultSig)) {
    throw "Expected signature output not found: $defaultSig"
  }

  $sigDir = Split-Path -Parent $SigOut
  if ($sigDir) { Ensure-Dir $sigDir }
  if (Test-Path -LiteralPath $SigOut) { Remove-Item -LiteralPath $SigOut -Force }
  Move-Item -LiteralPath $defaultSig -Destination $SigOut -Force
}