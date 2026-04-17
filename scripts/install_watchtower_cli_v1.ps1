param(
  [string]$InstallRoot = "$env:LOCALAPPDATA\WatchTowerCLI",
  [string]$RepoRoot = "",
  [switch]$UseLocalRelease
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WT-Die([string]$m){
  throw ("WATCHTOWER_CLI_INSTALL_FAIL: " + $m)
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

function WT-RemoveIfExists([string]$p){
  if(Test-Path -LiteralPath $p){
    Remove-Item -LiteralPath $p -Recurse -Force
  }
}

$zipUrl = "https://github.com/ScrappyHub/WatchTower/releases/download/watchtower-cli-v1.0.0/watchtower_cli_v1.zip"

if([string]::IsNullOrWhiteSpace($RepoRoot)){
  $RepoRoot = Split-Path -Parent $PSScriptRoot
}
if(Test-Path -LiteralPath $RepoRoot -PathType Container){
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

WT-EnsureDir $InstallRoot

$tempZip = Join-Path $env:TEMP "watchtower_cli_v1.zip"
$tempExtract = Join-Path $env:TEMP "watchtower_cli_v1_extract"

WT-RemoveIfExists $tempZip
WT-RemoveIfExists $tempExtract

if($UseLocalRelease){
  $localZip = Join-Path $RepoRoot "release\watchtower_cli_v1.zip"
  if(-not (Test-Path -LiteralPath $localZip -PathType Leaf)){
    WT-Die ("LOCAL_RELEASE_ZIP_MISSING: " + $localZip)
  }
  Copy-Item -LiteralPath $localZip -Destination $tempZip -Force
}
else {
  Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip
}

Expand-Archive -LiteralPath $tempZip -DestinationPath $tempExtract -Force

$dirs = @(Get-ChildItem -LiteralPath $tempExtract -Directory -ErrorAction SilentlyContinue)

if(@($dirs).Count -eq 1){
  $bundleRoot = $dirs[0].FullName
}
else {
  $bundleRoot = $tempExtract
}

$cliEntry = Join-Path $bundleRoot "scripts\watchtower_cli_v1.ps1"
if(-not (Test-Path -LiteralPath $cliEntry -PathType Leaf)){
  WT-Die ("CLI_ENTRY_NOT_FOUND_IN_BUNDLE: " + $bundleRoot)
}

$finalRoot = Join-Path $InstallRoot "watchtower_cli_v1"
WT-RemoveIfExists $finalRoot
Copy-Item -LiteralPath $bundleRoot -Destination $finalRoot -Recurse -Force

$launcher = Join-Path $InstallRoot "watchtower.cmd"
$launcherTxt = '@echo off' + "`n" +
'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + (Join-Path $finalRoot 'scripts\watchtower_cli_v1.ps1') + '" -RepoRoot "' + $finalRoot + '" %*'
WT-WriteUtf8NoBomLf -Path $launcher -Text $launcherTxt

Write-Host "WATCHTOWER_CLI_INSTALL_OK" -ForegroundColor Green
Write-Host ("INSTALL_ROOT: " + $InstallRoot) -ForegroundColor Green
Write-Host ("BUNDLE_ROOT: " + $finalRoot) -ForegroundColor Green
Write-Host ("LAUNCHER: " + $launcher) -ForegroundColor Green
Write-Host "TRY: watchtower.cmd quick-check" -ForegroundColor Green
