param(
  [Parameter(Mandatory=$true)]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WT-Die([string]$m){
  throw ("WATCHTOWER_PACKET_VERIFY_SELFTEST_FAIL: " + $m)
}

if($RepoRoot -is [System.IO.FileSystemInfo]){
  $RepoRoot = $RepoRoot.FullName
} elseif($RepoRoot -is [array]){
  if($RepoRoot.Count -eq 0){ WT-Die "EMPTY_REPO_ROOT_ARG" }
  $RepoRoot = $RepoRoot[0]
}
$RepoRoot = [string]$RepoRoot

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  WT-Die ("INVALID_REPO_ROOT: " + $RepoRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$Verify = Join-Path $RepoRoot "scripts\watchtower_verify_telemetry_packet_v1.ps1"
$BuildNeg = Join-Path $RepoRoot "scripts\watchtower_build_packet_negative_vectors_v1.ps1"
$RepairPos = Join-Path $RepoRoot "scripts\watchtower_packet_repair_and_verify_v1.ps1"

if(-not (Test-Path -LiteralPath $Verify -PathType Leaf)){ WT-Die "MISSING_VERIFY_SCRIPT" }
if(-not (Test-Path -LiteralPath $BuildNeg -PathType Leaf)){ WT-Die "MISSING_NEGATIVE_BUILDER" }
if(-not (Test-Path -LiteralPath $RepairPos -PathType Leaf)){ WT-Die "MISSING_POSITIVE_REPAIR_PIPELINE" }

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$Base = Join-Path $RepoRoot "test_vectors\watchtower\packet_v1"

$Positive = Join-Path $Base "positive"
$BadPacketId = Join-Path $Base "negative_bad_packet_id"
$BadSha = Join-Path $Base "negative_bad_sha"
$BadSig = Join-Path $Base "negative_bad_sig"

function Invoke-ScriptCapture([string]$File,[string[]]$ScriptArgs){
  $argList = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy","Bypass",
    "-File",$File
  ) + @($ScriptArgs)

  $oldPref = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    $output = & $PSExe @argList 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $oldPref
  }

  $txt = ""
  if($null -ne $output){
    $txt = (($output | ForEach-Object { [string]$_ }) -join "`n")
    $txt = ($txt -replace "`r`n","`n") -replace "`r","`n"
  }

  return [pscustomobject]@{
    ExitCode = $exitCode
    Output   = $txt
  }
}

Write-Host "PACKET_SELFTEST_PHASE:POSITIVE_REPAIR" -ForegroundColor Yellow
$r = Invoke-ScriptCapture $RepairPos @("-RepoRoot",$RepoRoot)
if($r.ExitCode -ne 0){ WT-Die ("POSITIVE_REPAIR_FAILED: " + $r.Output) }
if($r.Output -notmatch 'WATCHTOWER_PACKET_REPAIR_AND_VERIFY_OK'){ WT-Die "POSITIVE_REPAIR_TOKEN_MISSING" }

Write-Host "PACKET_SELFTEST_PHASE:NEGATIVE_BUILD" -ForegroundColor Yellow
$r = Invoke-ScriptCapture $BuildNeg @("-RepoRoot",$RepoRoot)
if($r.ExitCode -ne 0){ WT-Die "NEGATIVE_BUILD_FAILED" }
if($r.Output -notmatch 'WATCHTOWER_NEGATIVE_PACKET_VECTORS_OK'){ WT-Die "NEGATIVE_BUILD_TOKEN_MISSING" }

function Invoke-Verify([string]$PacketDir){
  return Invoke-ScriptCapture $Verify @("-RepoRoot",$RepoRoot,"-PacketDir",$PacketDir)
}

# positive
$r = Invoke-Verify $Positive
if($r.ExitCode -ne 0){ WT-Die "POSITIVE_EXIT_NONZERO" }
if($r.Output -notmatch 'WATCHTOWER_PACKET_VERIFY_OK'){ WT-Die "POSITIVE_TOKEN_MISSING" }
Write-Host "CASE_OK: positive" -ForegroundColor Green

# negative: packet id mismatch
$r = Invoke-Verify $BadPacketId
if($r.ExitCode -eq 0){ WT-Die "NEG_BAD_PACKET_ID_EXIT_ZERO" }
if($r.Output -notmatch 'PACKET_ID_MISMATCH'){ WT-Die "NEG_BAD_PACKET_ID_TOKEN_MISSING" }
Write-Host "CASE_OK: negative_bad_packet_id" -ForegroundColor Green

# negative: sha mismatch
$r = Invoke-Verify $BadSha
if($r.ExitCode -eq 0){ WT-Die "NEG_BAD_SHA_EXIT_ZERO" }
if($r.Output -notmatch 'SHA256_MISMATCH'){ WT-Die "NEG_BAD_SHA_TOKEN_MISSING" }
Write-Host "CASE_OK: negative_bad_sha" -ForegroundColor Green

# negative: signature fail
$r = Invoke-Verify $BadSig
if($r.ExitCode -eq 0){ WT-Die "NEG_BAD_SIG_EXIT_ZERO" }
if($r.Output -notmatch 'SIG_VERIFY_FAILED_EXIT_'){ WT-Die "NEG_BAD_SIG_TOKEN_MISSING" }
Write-Host "CASE_OK: negative_bad_sig" -ForegroundColor Green

Write-Host "WATCHTOWER_PACKET_VERIFY_SELFTEST_OK" -ForegroundColor Green
