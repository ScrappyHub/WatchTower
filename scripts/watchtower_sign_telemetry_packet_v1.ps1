param(
  [Parameter(Mandatory=$true)]$RepoRoot,
  [Parameter(Mandatory=$true)]$PacketDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WT-Die([string]$m){
  throw ("WATCHTOWER_SIGN_PACKET_FAIL: " + $m)
}

function WT-EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function WT-WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $dir = Split-Path -Parent $Path
  if($dir){ WT-EnsureDir $dir }
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function WT-AppendNdjson([string]$Path,[string]$Line){
  $dir = Split-Path -Parent $Path
  if($dir){ WT-EnsureDir $dir }
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = ($Line -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::AppendAllText($Path,$t,$enc)
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

function WT-CanonicalJson([hashtable]$Map){
  $keys = New-Object System.Collections.Generic.List[string]
  foreach($k in $Map.Keys){ [void]$keys.Add([string]$k) }
  $keys.Sort()

  $parts = New-Object System.Collections.Generic.List[string]
  foreach($k in $keys){
    $nameJson = ConvertTo-Json ([string]$k) -Compress
    $valJson  = ConvertTo-Json $Map[$k] -Compress -Depth 20
    [void]$parts.Add(($nameJson + ":" + $valJson))
  }
  return "{" + ($parts -join ",") + "}"
}

if($RepoRoot -is [System.IO.FileSystemInfo]){
  $RepoRoot = $RepoRoot.FullName
}
$RepoRoot = [string]$RepoRoot
if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  WT-Die ("INVALID_REPO_ROOT: " + $RepoRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if($PacketDir -is [System.IO.FileSystemInfo]){
  $PacketDir = $PacketDir.FullName
}
$PacketDir = [string]$PacketDir
if(-not (Test-Path -LiteralPath $PacketDir -PathType Container)){
  WT-Die ("INVALID_PACKET_DIR: " + $PacketDir)
}
$PacketDir = (Resolve-Path -LiteralPath $PacketDir).Path

$KeyPath    = Join-Path $RepoRoot "proofs\keys\wt_key"
$Allowed    = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$Manifest   = Join-Path $PacketDir "manifest.json"
$SigPath    = Join-Path $PacketDir "manifest.json.sig"
$ReceiptPath = Join-Path $RepoRoot "proofs\receipts\watchtower_sign_telemetry_packet.ndjson"

if(-not (Test-Path -LiteralPath $KeyPath -PathType Leaf)){
  WT-Die ("MISSING_SIGNING_KEY: " + $KeyPath)
}
if(-not (Test-Path -LiteralPath $Allowed -PathType Leaf)){
  WT-Die ("MISSING_ALLOWED_SIGNERS: " + $Allowed)
}
if(-not (Test-Path -LiteralPath $Manifest -PathType Leaf)){
  WT-Die ("MISSING_MANIFEST: " + $Manifest)
}

if(Test-Path -LiteralPath $SigPath -PathType Leaf){
  Remove-Item -LiteralPath $SigPath -Force
}

$ssh = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source
$cmd = (Get-Command cmd.exe -ErrorAction Stop).Source

Write-Host "SIGN_PHASE:SIGN_START" -ForegroundColor Yellow
& $ssh -Y sign -f $KeyPath -n watchtower/telemetry $Manifest
if($LASTEXITCODE -ne 0){
  WT-Die ("SIGN_FAILED_EXIT_" + $LASTEXITCODE)
}
if(-not (Test-Path -LiteralPath $SigPath -PathType Leaf)){
  WT-Die ("SIGNATURE_NOT_CREATED: " + $SigPath)
}
Write-Host "SIGN_PHASE:SIGN_DONE" -ForegroundColor Yellow

Write-Host "SIGN_PHASE:VERIFY_START" -ForegroundColor Yellow
$verifyCmd = 'type "' + $Manifest + '" | "' + $ssh + '" -Y verify -f "' + $Allowed + '" -I "watchtower" -n "watchtower/telemetry" -s "' + $SigPath + '"'
$proc = Start-Process -FilePath $cmd -ArgumentList @("/d","/c",$verifyCmd) -Wait -PassThru -NoNewWindow
if($proc.ExitCode -ne 0){
  WT-Die ("POST_SIGN_VERIFY_FAILED_EXIT_" + $proc.ExitCode)
}
Write-Host "SIGN_PHASE:VERIFY_DONE" -ForegroundColor Yellow

$receiptMap = [ordered]@{
  allowed_signers_sha256 = WT-Sha256HexBytes ([System.IO.File]::ReadAllBytes($Allowed))
  key_path = $KeyPath
  manifest_sha256 = WT-Sha256HexBytes ([System.IO.File]::ReadAllBytes($Manifest))
  packet_dir = $PacketDir
  receipt_schema = "watchtower.sign_telemetry_packet.receipt.v1"
  signature_path = $SigPath
  status = "ok"
}
$receiptJson = WT-CanonicalJson $receiptMap
WT-AppendNdjson -Path $ReceiptPath -Line $receiptJson

Write-Host "WATCHTOWER_SIGN_TELEMETRY_PACKET_OK" -ForegroundColor Green
Write-Host ("PACKET: " + $PacketDir) -ForegroundColor Green
Write-Host ("SIGNATURE: " + $SigPath) -ForegroundColor Green
Write-Host ("RECEIPT: " + $ReceiptPath) -ForegroundColor Green
