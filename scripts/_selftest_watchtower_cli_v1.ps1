param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WT-Die([string]$m){
  throw ("WATCHTOWER_CLI_SELFTEST_FAIL: " + $m)
}

function WT-InvokeCapture([string]$Script,[string[]]$ChildArgs){
  $PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
  $outFile = Join-Path $env:TEMP ("watchtower_cli_selftest_" + [guid]::NewGuid().ToString("N") + ".txt")
  try {
    $p = Start-Process `
      -FilePath $PSExe `
      -ArgumentList (@("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$Script) + $ChildArgs) `
      -RedirectStandardOutput $outFile `
      -Wait `
      -PassThru `
      -NoNewWindow

    $txt = ""
    if(Test-Path -LiteralPath $outFile -PathType Leaf){
      $txt = [System.IO.File]::ReadAllText($outFile,[System.Text.Encoding]::UTF8)
      $txt = ($txt -replace "`r`n","`n") -replace "`r","`n"
    }

    return [pscustomobject]@{
      ExitCode = $p.ExitCode
      Output   = $txt
    }
  }
  finally {
    if(Test-Path -LiteralPath $outFile -PathType Leaf){
      Remove-Item -LiteralPath $outFile -Force
    }
  }
}

if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){
  WT-Die ("INVALID_REPO_ROOT: " + $RepoRoot)
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$Cli = Join-Path $RepoRoot "scripts\watchtower_cli_v1.ps1"
if(-not (Test-Path -LiteralPath $Cli -PathType Leaf)){
  WT-Die ("CLI_MISSING: " + $Cli)
}

$r = WT-InvokeCapture $Cli @("-RepoRoot",$RepoRoot,"device","list")
if($r.ExitCode -ne 0){ WT-Die ("DEVICE_LIST_EXIT_" + $r.ExitCode + ": " + $r.Output) }
if($r.Output -notmatch 'WATCHTOWER_DEVICE_LIST_OK'){ WT-Die "DEVICE_LIST_TOKEN_MISSING" }
Write-Host "CASE_OK: device_list" -ForegroundColor Green

$r = WT-InvokeCapture $Cli @("-RepoRoot",$RepoRoot,"receipts","list")
if($r.ExitCode -ne 0){ WT-Die ("RECEIPTS_LIST_EXIT_" + $r.ExitCode + ": " + $r.Output) }
if($r.Output -notmatch 'WATCHTOWER_RECEIPTS_LIST_OK'){ WT-Die "RECEIPTS_LIST_TOKEN_MISSING" }
Write-Host "CASE_OK: receipts_list" -ForegroundColor Green

$r = WT-InvokeCapture $Cli @("-RepoRoot",$RepoRoot,"freeze","show")
if($r.ExitCode -ne 0){ WT-Die ("FREEZE_SHOW_EXIT_" + $r.ExitCode + ": " + $r.Output) }
if($r.Output -notmatch 'WATCHTOWER_FREEZE_SHOW_OK'){ WT-Die "FREEZE_SHOW_TOKEN_MISSING" }
Write-Host "CASE_OK: freeze_show" -ForegroundColor Green

Write-Host "WATCHTOWER_CLI_SELFTEST_OK" -ForegroundColor Green
