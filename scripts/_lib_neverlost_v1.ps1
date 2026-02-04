Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Utf8NoBom() { New-Object System.Text.UTF8Encoding($false) }
function Write-Utf8NoBom([string]$Path, [string]$Text) {
  $enc  = Utf8NoBom
  $norm = $Text.Replace("`r`n","`n").Replace("`r","`n")
  [System.IO.File]::WriteAllText($Path, $norm, $enc)
}
function Read-Utf8([string]$Path) { [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) }
function Append-Utf8NoBom([string]$Path, [string]$Text) {
  $enc  = Utf8NoBom
  $norm = $Text.Replace("`r`n","`n").Replace("`r","`n")
  $sw = New-Object System.IO.StreamWriter($Path, $true, $enc)
  try { $sw.Write($norm) } finally { $sw.Dispose() }
}

function Sha256HexBytes([byte[]]$Bytes) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $h = $sha.ComputeHash($Bytes)
    return ([BitConverter]::ToString($h) -replace "-", "").ToLowerInvariant()
  } finally { $sha.Dispose() }
}
function Sha256HexPath([string]$Path) {
  $b = [System.IO.File]::ReadAllBytes($Path)
  Sha256HexBytes $b
}

function ResolveRealPath([string]$Path) { return (Resolve-Path -LiteralPath $Path).Path }
function RelPathUnix([string]$Root, [string]$Path) {
  $r = (ResolveRealPath $Root).TrimEnd('\')
  $p = (ResolveRealPath $Path)
  if ($p.Length -lt $r.Length -or $p.Substring(0, $r.Length).ToLowerInvariant() -ne $r.ToLowerInvariant()) {
    throw ("Path not under root: root={0} path={1}" -f $r, $p)
  }
  $rel = $p.Substring($r.Length).TrimStart('\')
  return ($rel -replace '\\','/')
}

function AssertPrincipalFormat([string]$Principal) {
  if (-not $Principal) { throw "Principal missing" }
  if ($Principal -notmatch '^single-tenant/[a-z0-9_\-]+/authority/[a-z0-9_\-]+$') {
    throw ("Principal invalid: {0}" -f $Principal)
  }
}
function AssertKeyIdFormat([string]$KeyId) {
  if (-not $KeyId) { throw "KeyId missing" }
  if ($KeyId -notmatch '^[a-z0-9\-]+$') { throw ("KeyId invalid: {0}" -f $KeyId) }
}

function To-CanonJson([object]$Obj) {
  function Canon([object]$x) {
    if ($null -eq $x) { return $null }
    if ($x -is [System.Collections.IDictionary]) {
      $keys = @($x.Keys) | Sort-Object
      $o = [ordered]@{}
      foreach ($k in $keys) { $o[$k] = Canon $x[$k] }
      return $o
    }
    if ($x -is [System.Collections.IEnumerable] -and -not ($x -is [string])) {
      $arr = @()
      foreach ($i in $x) { $arr += (Canon $i) }
      return ,$arr
    }
    return $x
  }
  $canon = Canon $Obj
  return ($canon | ConvertTo-Json -Depth 50 -Compress)
}

function LoadTrustBundle([string]$TrustBundlePath) {
  if (-not (Test-Path -LiteralPath $TrustBundlePath)) { throw "Missing trust bundle: $TrustBundlePath" }
  $raw = Read-Utf8 $TrustBundlePath
  $obj = $raw | ConvertFrom-Json
  if ($obj.schema -ne "neverlost.trust_bundle.v1") { throw "trust_bundle schema mismatch" }
  if (-not $obj.bundle_id) { throw "trust_bundle missing bundle_id" }
  if (-not $obj.principals) { throw "trust_bundle missing principals[]" }
  foreach ($p in $obj.principals) {
    AssertPrincipalFormat $p.principal
    if (-not $p.keys) { throw ("trust_bundle principal missing keys[]: {0}" -f $p.principal) }
    foreach ($k in $p.keys) {
      AssertKeyIdFormat $k.key_id
      if (-not $k.pubkey -or $k.pubkey -notmatch '^ssh-ed25519\s+') { throw ("pubkey invalid for {0}/{1}" -f $p.principal, $k.key_id) }
      if (-not $k.pubkey_sha256) { throw ("pubkey_sha256 missing for {0}/{1}" -f $p.principal, $k.key_id) }
      if (-not $k.namespaces) { throw ("namespaces missing for {0}/{1}" -f $p.principal, $k.key_id) }
    }
  }
  return $obj
}

function MakeAllowedSignersLine([string]$Principal, [string]$Namespace, [string]$PubKeyLine) {
  AssertPrincipalFormat $Principal
  if (-not $Namespace) { throw "Namespace missing" }
  if (-not $PubKeyLine -or $PubKeyLine -notmatch '^ssh-ed25519\s+') { throw "PubKeyLine must start with ssh-ed25519" }
  return ("{0} {1} {2}" -f $Principal, $Namespace, $PubKeyLine.Trim())
}
function WriteAllowedSignersFile([string]$AllowedSignersPath, [object]$TrustBundle) {
  $lines = New-Object System.Collections.Generic.List[string]
  $principals = @($TrustBundle.principals) | Sort-Object { $_.principal }
  foreach ($p in $principals) {
    $keys = @($p.keys) | Sort-Object { $_.key_id }
    foreach ($k in $keys) {
      $ns = @($k.namespaces) | Sort-Object
      foreach ($n in $ns) {
        $lines.Add((MakeAllowedSignersLine -Principal $p.principal -Namespace $n -PubKeyLine $k.pubkey))
      }
    }
  }
  $text = ($lines -join "`n") + "`n"
  Write-Utf8NoBom $AllowedSignersPath $text
}

function Write-NeverLostReceipt([string]$ReceiptsPath, [hashtable]$Receipt) {
  if (-not $ReceiptsPath) { throw "ReceiptsPath missing" }
  $canonJson = To-CanonJson $Receipt
  $h = Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($canonJson + "`n"))
  Append-Utf8NoBom $ReceiptsPath ($canonJson + "`n")
  return $h
}

function SshYSignFile {
  param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$KeyPriv,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Namespace,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$InFile,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SigOut
  )

  if (-not (Test-Path -LiteralPath $KeyPriv)) { throw "Missing key: $KeyPriv" }
  if (-not (Test-Path -LiteralPath $InFile))  { throw "Missing file: $InFile" }

  $outDir = Split-Path -Parent $SigOut
  if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    [System.IO.Directory]::CreateDirectory($outDir) | Out-Null
  }

  $t0 = (Get-Date).ToUniversalTime()

  # File-arg signing: should create "$InFile.sig" on disk.
  # Run through cmd.exe to avoid PS5.1 native stderr becoming a terminating error.
  $cmd = 'ssh-keygen -Y sign -f "{0}" -n "{1}" -O hashalg=sha256 "{2}"' -f $KeyPriv, $Namespace, $InFile
  $out = & cmd.exe /c ($cmd + ' 2>&1')
  $ec = $LASTEXITCODE
  if ($ec -ne 0) { throw ("ssh-keygen sign failed (exit={0}): {1}" -f $ec, ($out -join "`n")) }

  # Primary expected output
  $produced = ($InFile + ".sig")
  if (-not (Test-Path -LiteralPath $produced)) {
    # Fallback: newest .sig in same dir written since t0
    $inDir = Split-Path -Parent $InFile
    $sig = Get-ChildItem -LiteralPath $inDir -Filter "*.sig" -File -ErrorAction Stop |
      Where-Object { $_.LastWriteTimeUtc -ge $t0.AddSeconds(-2) } |
      Sort-Object LastWriteTimeUtc -Descending |
      Select-Object -First 1
    if ($sig) { $produced = $sig.FullName }
  }

  if (-not (Test-Path -LiteralPath $produced)) { throw "ssh-keygen did not produce signature file near input file" }

  Move-Item -LiteralPath $produced -Destination $SigOut -Force
  if (-not (Test-Path -LiteralPath $SigOut)) { throw "Signature output not created at SigOut: $SigOut" }

  return $out
}

function SshYVerifyFile {
  param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$AllowedSignersPath,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Namespace,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Identity,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$InFile,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SigPath
  )

  if (-not (Test-Path -LiteralPath $AllowedSignersPath)) { throw "Missing allowed_signers: $AllowedSignersPath" }
  if (-not (Test-Path -LiteralPath $InFile))             { throw "Missing file: $InFile" }
  if (-not (Test-Path -LiteralPath $SigPath))            { throw "Missing sig:  $SigPath" }

  # Older verify expects stdin + requires -I identity.
  $cmd = 'ssh-keygen -Y verify -f "{0}" -I "{1}" -n "{2}" -s "{3}" < "{4}"' -f $AllowedSignersPath, $Identity, $Namespace, $SigPath, $InFile
  $out = & cmd.exe /c ($cmd + ' 2>&1')
  $ec = $LASTEXITCODE
  if ($ec -ne 0) { throw ("ssh-keygen verify failed (exit={0}) for identity '{1}': {2}" -f $ec, $Identity, ($out -join "`n")) }

  return $out
}

