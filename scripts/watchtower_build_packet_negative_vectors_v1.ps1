param([Parameter(Mandatory=$true)]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WT-Die([string]$m){ throw ("WATCHTOWER_BUILD_NEGATIVE_VECTORS_FAIL: " + $m) }

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

function WT-CopyDir([string]$Src,[string]$Dst){
  if(-not (Test-Path -LiteralPath $Src -PathType Container)){
    WT-Die ("MISSING_SOURCE_DIR: " + $Src)
  }
  if(Test-Path -LiteralPath $Dst -PathType Container){
    Remove-Item -LiteralPath $Dst -Recurse -Force
  }
  WT-EnsureDir $Dst
  Get-ChildItem -LiteralPath $Src -Force | ForEach-Object {
    $dstPath = Join-Path $Dst $_.Name
    if($_.PSIsContainer){
      Copy-Item -LiteralPath $_.FullName -Destination $dstPath -Recurse -Force
    } else {
      Copy-Item -LiteralPath $_.FullName -Destination $dstPath -Force
    }
  }
}

if($RepoRoot -is [System.IO.FileSystemInfo]){
  $RepoRoot = $RepoRoot.FullName
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$Base = Join-Path $RepoRoot "test_vectors\watchtower\packet_v1"
$Positive = Join-Path $Base "positive"
$BadPacketId = Join-Path $Base "negative_bad_packet_id"
$BadSha = Join-Path $Base "negative_bad_sha"
$BadSig = Join-Path $Base "negative_bad_sig"

if(-not (Test-Path -LiteralPath $Positive -PathType Container)){
  WT-Die ("MISSING_POSITIVE_PACKET: " + $Positive)
}

Write-Host "NEG_VECTOR_PHASE:COPY_START" -ForegroundColor Yellow
WT-CopyDir $Positive $BadPacketId
WT-CopyDir $Positive $BadSha
WT-CopyDir $Positive $BadSig
Write-Host "NEG_VECTOR_PHASE:COPY_DONE" -ForegroundColor Yellow

# bad packet_id only
Write-Host "NEG_VECTOR_PHASE:BAD_PACKET_ID_START" -ForegroundColor Yellow
$packetIdPath = Join-Path $BadPacketId "packet_id.txt"
$origPacketId = [System.IO.File]::ReadAllText($packetIdPath,[System.Text.Encoding]::UTF8)
$origPacketId = ($origPacketId -replace "`r","") -replace "`n",""
$origPacketId = $origPacketId.Trim()
if([string]::IsNullOrWhiteSpace($origPacketId)){ WT-Die "EMPTY_PACKET_ID" }
$mutPacketId = "0" + $origPacketId.Substring(1)
WT-WriteUtf8NoBomLf -Path $packetIdPath -Text $mutPacketId
Write-Host "NEG_VECTOR_PHASE:BAD_PACKET_ID_DONE" -ForegroundColor Yellow

# bad sha only
Write-Host "NEG_VECTOR_PHASE:BAD_SHA_START" -ForegroundColor Yellow
$payloadPath = Join-Path $BadSha "payload\telemetry.ndjson"
$payloadRaw = [System.IO.File]::ReadAllText($payloadPath,[System.Text.Encoding]::UTF8)
$payloadRaw = ($payloadRaw -replace "`r`n","`n") -replace "`r","`n"
$payloadRaw = $payloadRaw.TrimEnd("`n")
$payloadRaw = $payloadRaw + "`n" + '{"schema":"watchtower.health_report.v1","device_id":"dev-negative","observed_utc":"2026-03-01T00:00:00Z","status":"tampered"}'
WT-WriteUtf8NoBomLf -Path $payloadPath -Text $payloadRaw
Write-Host "NEG_VECTOR_PHASE:BAD_SHA_DONE" -ForegroundColor Yellow

# bad sig only
Write-Host "NEG_VECTOR_PHASE:BAD_SIG_START" -ForegroundColor Yellow
$sigPath = Join-Path $BadSig "manifest.json.sig"
if(-not (Test-Path -LiteralPath $sigPath -PathType Leaf)){
  WT-Die ("MISSING_SIG_FILE: " + $sigPath)
}
WT-WriteUtf8NoBomLf -Path $sigPath -Text @"
-----BEGIN SSH SIGNATURE-----
this-is-not-a-valid-signature
-----END SSH SIGNATURE-----
"@
Write-Host "NEG_VECTOR_PHASE:BAD_SIG_DONE" -ForegroundColor Yellow

Write-Host "WATCHTOWER_NEGATIVE_PACKET_VECTORS_OK" -ForegroundColor Green
