param(
  [Parameter(Mandatory=$true)]$RepoRoot,
  [Parameter(Mandatory=$true)]$PacketDir,
  $ReceiptPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function WT-Die([string]$m){ throw ("WATCHTOWER_PACKET_VERIFY_FAIL: " + $m) }

function WT-EnsureString([object]$v){
  if($null -eq $v){ return "" }
  return [string]$v
}

function WT-EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function WT-AppendNdjson([string]$Path,[string]$Line){
  $dir = Split-Path -Parent $Path
  if($dir){ WT-EnsureDir $dir }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $txt = (WT-EnsureString $Line).Replace("`r`n","`n").Replace("`r","`n")
  if(-not $txt.EndsWith("`n")){ $txt += "`n" }
  [System.IO.File]::AppendAllText($Path,$txt,$enc)
}

function WT-ReadUtf8NoBomLf([string]$Path){
  return [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8).Replace("`r`n","`n").Replace("`r","`n")
}

function WT-Sha256HexBytes([byte[]]$b){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($b)) -replace "-","").ToLowerInvariant()
  }
  finally {
    $sha.Dispose()
  }
}

function WT-Sha256HexFile([string]$Path){
  return WT-Sha256HexBytes ([System.IO.File]::ReadAllBytes($Path))
}

function WT-Sha256HexTextLf([string]$Text){
  $norm = (WT-EnsureString $Text).Replace("`r`n","`n").Replace("`r","`n")
  return WT-Sha256HexBytes ([System.Text.Encoding]::UTF8.GetBytes($norm))
}

function WT-FindFirstExisting([object[]]$Candidates){
  foreach($c in @($Candidates)){
    $p = WT-EnsureString $c
    if(-not [string]::IsNullOrWhiteSpace($p)){
      if(Test-Path -LiteralPath $p -PathType Leaf){ return $p }
    }
  }
  return $null
}

function WT-FindTelemetryPayload([string]$Root){
  return WT-FindFirstExisting @(
    (Join-Path $Root "payload\telemetry.ndjson"),
    (Join-Path $Root "payload\watchtower_telemetry.ndjson"),
    (Join-Path $Root "payload\telemetry.jsonl"),
    (Join-Path $Root "telemetry.ndjson")
  )
}

function WT-VerifyPacketConstitution([string]$Root){
  $manifestPath = Join-Path $Root "manifest.json"
  $packetIdPath = Join-Path $Root "packet_id.txt"
  $shaPath      = Join-Path $Root "sha256sums.txt"

  if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){ WT-Die ("MISSING_MANIFEST: " + $manifestPath) }
  if(-not (Test-Path -LiteralPath $packetIdPath -PathType Leaf)){ WT-Die ("MISSING_PACKET_ID: " + $packetIdPath) }
  if(-not (Test-Path -LiteralPath $shaPath -PathType Leaf)){ WT-Die ("MISSING_SHA256SUMS: " + $shaPath) }

  $manifestRaw = WT-ReadUtf8NoBomLf $manifestPath
  if([string]::IsNullOrWhiteSpace($manifestRaw)){ WT-Die "EMPTY_MANIFEST" }

  $manifestObj = $manifestRaw | ConvertFrom-Json
  if($manifestObj.PSObject.Properties.Name -contains "packet_id"){
    WT-Die "MANIFEST_CONTAINS_PACKET_ID"
  }

  $expectedPacketId = (WT-ReadUtf8NoBomLf $packetIdPath).Trim()
  if([string]::IsNullOrWhiteSpace($expectedPacketId)){ WT-Die "EMPTY_PACKET_ID" }

  $actualPacketId = WT-Sha256HexTextLf $manifestRaw
  if($actualPacketId -ne $expectedPacketId){
    WT-Die "PACKET_ID_MISMATCH"
  }

  $shaRaw = WT-ReadUtf8NoBomLf $shaPath
  if([string]::IsNullOrWhiteSpace($shaRaw)){ WT-Die "EMPTY_SHA256SUMS" }

  foreach($ln in ($shaRaw -split "`n")){
    $t = (WT-EnsureString $ln).Trim()
    if($t.Length -eq 0){ continue }

    if($t.Length -lt 67){ WT-Die "BAD_SHA256SUM_LINE" }

    $hashPart = $t.Substring(0,64).ToLowerInvariant()
    $rest = $t.Substring(64)
    if(-not ($rest.StartsWith("  ") -or $rest.StartsWith(" *"))){ WT-Die "BAD_SHA256SUM_SEPARATOR" }

    $relPath = $rest.Substring(2).Trim()
    if([string]::IsNullOrWhiteSpace($relPath)){ WT-Die "BAD_SHA256SUM_PATH" }
    if($relPath -eq "sha256sums.txt"){ WT-Die "SHA256SUMS_SELF_HASH_FORBIDDEN" }
    if($relPath.Contains("..")){ WT-Die "SHA256SUMS_TRAVERSAL" }
    if([System.IO.Path]::IsPathRooted($relPath)){ WT-Die "SHA256SUMS_ABSOLUTE_PATH" }

    $full = Join-Path $Root $relPath
    if(-not (Test-Path -LiteralPath $full -PathType Leaf)){ WT-Die ("SHA256SUMS_TARGET_MISSING: " + $relPath) }

    $actualHash = WT-Sha256HexFile $full
    if($actualHash -ne $hashPart){
      WT-Die ("SHA256_MISMATCH: " + $relPath)
    }
  }

  return [pscustomobject]@{
    manifest_path = $manifestPath
    packet_id     = $actualPacketId
    sha256sums    = $shaPath
  }
}

function WT-VerifyPacketSignature([string]$Root,[string]$AllowedPath,[string]$Namespace){
  if(-not (Test-Path -LiteralPath $AllowedPath -PathType Leaf)){
    WT-Die ("MISSING_ALLOWED_SIGNERS: " + $AllowedPath)
  }

  $sigPath = WT-FindFirstExisting @(
    (Join-Path $Root "manifest.json.sig"),
    (Join-Path $Root "manifest.sig"),
    (Join-Path $Root "packet.sig")
  )

  if([string]::IsNullOrWhiteSpace($sigPath)){
    WT-Die "MISSING_PACKET_SIGNATURE"
  }

  $cmd = (Get-Command cmd.exe -ErrorAction Stop).Source
  $ssh = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source
  $manifestPath = Join-Path $Root "manifest.json"

  $principal = "watchtower"
  $verifyCmd = 'type "' + $manifestPath + '" | "' + $ssh + '" -Y verify -f "' + $AllowedPath + '" -I "' + $principal + '" -n "' + $Namespace + '" -s "' + $sigPath + '"'
  $verifyProc = Start-Process -FilePath $cmd -ArgumentList @("/d","/c",$verifyCmd) -Wait -PassThru -NoNewWindow
  if($verifyProc.ExitCode -ne 0){
    WT-Die ("SIG_VERIFY_FAILED_EXIT_" + $verifyProc.ExitCode)
  }

  return [pscustomobject]@{
    sig_path   = $sigPath
    principal  = $principal
    namespace  = $Namespace
  }
}

if($RepoRoot -is [System.IO.FileSystemInfo]){
  $RepoRoot = $RepoRoot.FullName
} elseif($RepoRoot -is [array]){
  if($RepoRoot.Count -eq 0){ WT-Die "EMPTY_REPO_ROOT_ARG" }
  $RepoRoot = $RepoRoot[0]
}
$RepoRoot = [string]$RepoRoot

if($PacketDir -is [System.IO.FileSystemInfo]){
  $PacketDir = $PacketDir.FullName
} elseif($PacketDir -is [array]){
  if($PacketDir.Count -eq 0){ WT-Die "EMPTY_PACKET_ARG" }
  $PacketDir = $PacketDir[0]
}
$PacketDir = [string]$PacketDir

if($ReceiptPath -is [System.IO.FileSystemInfo]){
  $ReceiptPath = $ReceiptPath.FullName
} elseif($ReceiptPath -is [array]){
  if($ReceiptPath.Count -gt 0){ $ReceiptPath = $ReceiptPath[0] } else { $ReceiptPath = "" }
}
$ReceiptPath = [string]$ReceiptPath

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  WT-Die ("INVALID_REPO_ROOT: " + $RepoRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if(-not (Test-Path -LiteralPath $PacketDir -PathType Container)){
  WT-Die ("MISSING_PACKET_DIR: " + $PacketDir)
}
$PacketDir = (Resolve-Path -LiteralPath $PacketDir).Path

if([string]::IsNullOrWhiteSpace($ReceiptPath)){
  $ReceiptPath = Join-Path $RepoRoot "proofs\receipts\watchtower_telemetry_packet_verify.ndjson"
}

$TrustBundlePath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$AllowedPath     = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$Namespace       = "watchtower/telemetry"

$trustBundleSha = ""
$allowedSha     = ""
if(Test-Path -LiteralPath $TrustBundlePath -PathType Leaf){ $trustBundleSha = WT-Sha256HexFile $TrustBundlePath }
if(Test-Path -LiteralPath $AllowedPath -PathType Leaf){ $allowedSha = WT-Sha256HexFile $AllowedPath }

Write-Host "PACKET_VERIFY_PHASE:PC_START" -ForegroundColor Yellow
$packetInfo = WT-VerifyPacketConstitution $PacketDir
Write-Host "PACKET_VERIFY_PHASE:PC_DONE" -ForegroundColor Yellow

Write-Host "PACKET_VERIFY_PHASE:SIG_START" -ForegroundColor Yellow
$sigInfo = WT-VerifyPacketSignature -Root $PacketDir -AllowedPath $AllowedPath -Namespace $Namespace
Write-Host "PACKET_VERIFY_PHASE:SIG_DONE" -ForegroundColor Yellow

$payloadPath = WT-FindTelemetryPayload $PacketDir
if([string]::IsNullOrWhiteSpace($payloadPath)){ WT-Die "MISSING_TELEMETRY_PAYLOAD" }

$directVerify = Join-Path $RepoRoot "scripts\watchtower_verify_telemetry_v1.ps1"
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

Write-Host "PACKET_VERIFY_PHASE:PAYLOAD_VERIFY_START" -ForegroundColor Yellow
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $directVerify -RepoRoot $RepoRoot -TelemetryPath $payloadPath -ReceiptPath $ReceiptPath
if($LASTEXITCODE -ne 0){
  WT-Die ("PAYLOAD_VERIFY_FAILED_EXIT_" + $LASTEXITCODE)
}
Write-Host "PACKET_VERIFY_PHASE:PAYLOAD_VERIFY_DONE" -ForegroundColor Yellow

$receipt = [pscustomobject]@{
  schema              = "watchtower.telemetry.packet_verify.receipt.v1"
  packet_dir          = $PacketDir
  packet_id           = (WT-EnsureString $packetInfo.packet_id)
  payload_path        = $payloadPath
  signature_path      = (WT-EnsureString $sigInfo.sig_path)
  verify_namespace    = (WT-EnsureString $sigInfo.namespace)
  verify_principal    = (WT-EnsureString $sigInfo.principal)
  trust_bundle_sha256 = $trustBundleSha
  allowed_sha256      = $allowedSha
  verify_status       = "verified"
} | ConvertTo-Json -Compress -Depth 10

WT-AppendNdjson -Path $ReceiptPath -Line $receipt

Write-Host "WATCHTOWER_PACKET_VERIFY_OK" -ForegroundColor Green
Write-Host ("PACKET: " + $PacketDir) -ForegroundColor Green
Write-Host ("PAYLOAD: " + $payloadPath) -ForegroundColor Green
Write-Host ("RECEIPT: " + $ReceiptPath) -ForegroundColor Green
