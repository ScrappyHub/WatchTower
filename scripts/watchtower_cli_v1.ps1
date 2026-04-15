param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(ValueFromRemainingArguments=$true)][string[]]$Args
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WT-Die([string]$m){
  throw ("WATCHTOWER_CLI_FAIL: " + $m)
}

function WT-EnsureRepo([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    WT-Die ("INVALID_REPO_ROOT: " + $Path)
  }
  return (Resolve-Path -LiteralPath $Path).Path
}

function WT-ReadUtf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    WT-Die ("FILE_MISSING: " + $Path)
  }
  return [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8).Replace("`r`n","`n").Replace("`r","`n")
}

function WT-ReadJson([string]$Path){
  return (WT-ReadUtf8 $Path | ConvertFrom-Json)
}

function WT-InvokeChild([string]$Script,[string[]]$ChildArgs){
  if(-not (Test-Path -LiteralPath $Script -PathType Leaf)){
    WT-Die ("SCRIPT_MISSING: " + $Script)
  }

  $PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

  & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Script @ChildArgs
  if($LASTEXITCODE -ne 0){
    WT-Die ("CHILD_FAILED: " + $Script + ": " + $LASTEXITCODE)
  }
}

function WT-ListDevices([string]$DevicesRoot){
  if(-not (Test-Path -LiteralPath $DevicesRoot -PathType Container)){
    Write-Host "WATCHTOWER_DEVICE_LIST_OK"
    Write-Host "COUNT: 0"
    return
  }

  $dirs = Get-ChildItem -LiteralPath $DevicesRoot -Directory | Sort-Object Name
  Write-Host "WATCHTOWER_DEVICE_LIST_OK"
  Write-Host ("COUNT: " + @($dirs).Count)

  foreach($d in $dirs){
    $deviceJson = Join-Path $d.FullName "device.json"
    if(Test-Path -LiteralPath $deviceJson -PathType Leaf){
      $obj = WT-ReadJson $deviceJson
      $id = [string]$obj.device_id
      $status = [string]$obj.status
      $trust = [string]$obj.trust_level
      $os = [string]$obj.os_family
      Write-Host ("DEVICE: " + $id + " | status=" + $status + " | trust=" + $trust + " | os=" + $os)
    }
    else {
      Write-Host ("DEVICE_DIR_NO_JSON: " + $d.FullName)
    }
  }
}

function WT-ShowDevice([string]$DevicesRoot,[string]$DeviceId){
  $deviceRoot = Join-Path $DevicesRoot $DeviceId
  $deviceJson = Join-Path $deviceRoot "device.json"
  $eventsPath = Join-Path $deviceRoot "events.ndjson"

  if(-not (Test-Path -LiteralPath $deviceJson -PathType Leaf)){
    WT-Die ("DEVICE_NOT_FOUND: " + $DeviceId)
  }

  $obj = WT-ReadJson $deviceJson
  Write-Host "WATCHTOWER_DEVICE_SHOW_OK"
  Write-Host ("DEVICE_ID: " + [string]$obj.device_id)
  Write-Host ("STATUS: " + [string]$obj.status)
  Write-Host ("TRUST: " + [string]$obj.trust_level)
  Write-Host ("OS: " + [string]$obj.os_family)
  Write-Host ("MANUFACTURER: " + [string]$obj.manufacturer)
  Write-Host ("SERIAL: " + [string]$obj.serial)
  Write-Host ("HARDWARE_FINGERPRINT: " + [string]$obj.hardware_fingerprint)
  Write-Host ("DEVICE_JSON: " + $deviceJson)

  if(Test-Path -LiteralPath $eventsPath -PathType Leaf){
    $lines = @(WT-ReadUtf8 $eventsPath -split "`n" | Where-Object { $_ -and $_.Trim().Length -gt 0 })
    Write-Host ("EVENT_COUNT: " + @($lines).Count)
    Write-Host ("EVENTS: " + $eventsPath)
  }
  else {
    Write-Host "EVENT_COUNT: 0"
  }
}

function WT-ListReceipts([string]$ReceiptsRoot){
  if(-not (Test-Path -LiteralPath $ReceiptsRoot -PathType Container)){
    Write-Host "WATCHTOWER_RECEIPTS_LIST_OK"
    Write-Host "COUNT: 0"
    return
  }

  $files = Get-ChildItem -LiteralPath $ReceiptsRoot -File | Sort-Object Name
  Write-Host "WATCHTOWER_RECEIPTS_LIST_OK"
  Write-Host ("COUNT: " + @($files).Count)
  foreach($f in $files){
    Write-Host ("RECEIPT: " + $f.FullName)
  }
}

function WT-ShowFreeze([string]$FreezeRoot,[string]$ReceiptPath){
  Write-Host "WATCHTOWER_FREEZE_SHOW_OK"
  Write-Host ("FREEZE_ROOT: " + $FreezeRoot)

  $manifest = Join-Path $FreezeRoot "freeze_manifest.json"
  $sha = Join-Path $FreezeRoot "sha256sums.txt"
  $fgOut = Join-Path $FreezeRoot "full_green.stdout.txt"
  $fgErr = Join-Path $FreezeRoot "full_green.stderr.txt"
  $bindOut = Join-Path $FreezeRoot "device_binding.stdout.txt"
  $bindErr = Join-Path $FreezeRoot "device_binding.stderr.txt"

  foreach($p in @($manifest,$sha,$fgOut,$fgErr,$bindOut,$bindErr,$ReceiptPath)){
    if(Test-Path -LiteralPath $p){
      Write-Host ("ARTIFACT: " + $p)
    }
  }
}

$RepoRoot = WT-EnsureRepo $RepoRoot

$ScriptsRoot = Join-Path $RepoRoot "scripts"
$DevicesRoot = Join-Path $RepoRoot "devices"
$ReceiptsRoot = Join-Path $RepoRoot "proofs\receipts"
$FreezeRoot = Join-Path $RepoRoot "proofs\freeze\watchtower_tier0_v1"
$FreezeReceipt = Join-Path $RepoRoot "proofs\receipts\watchtower_tier0_freeze.ndjson"

if($null -eq $Args -or @($Args).Count -eq 0){
  Write-Host "WATCHTOWER_CLI_HELP"
  Write-Host "watchtower device list"
  Write-Host "watchtower device show <device_id>"
  Write-Host "watchtower receipts list"
  Write-Host "watchtower freeze show"
  Write-Host "watchtower packet verify"
  Write-Host "watchtower selftest full-green"
  Write-Host "watchtower selftest freeze"
  return
}

$cmd0 = $Args[0].ToLowerInvariant()

switch($cmd0){
  "device" {
    if(@($Args).Count -lt 2){ WT-Die "DEVICE_SUBCOMMAND_REQUIRED" }
    $cmd1 = $Args[1].ToLowerInvariant()

    switch($cmd1){
      "list" {
        WT-ListDevices $DevicesRoot
        return
      }
      "show" {
        if(@($Args).Count -lt 3){ WT-Die "DEVICE_ID_REQUIRED" }
        WT-ShowDevice $DevicesRoot $Args[2]
        return
      }
      default {
        WT-Die ("UNKNOWN_DEVICE_SUBCOMMAND: " + $cmd1)
      }
    }
  }

  "receipts" {
    if(@($Args).Count -lt 2){ WT-Die "RECEIPTS_SUBCOMMAND_REQUIRED" }
    $cmd1 = $Args[1].ToLowerInvariant()

    switch($cmd1){
      "list" {
        WT-ListReceipts $ReceiptsRoot
        return
      }
      default {
        WT-Die ("UNKNOWN_RECEIPTS_SUBCOMMAND: " + $cmd1)
      }
    }
  }

  "freeze" {
    if(@($Args).Count -lt 2){ WT-Die "FREEZE_SUBCOMMAND_REQUIRED" }
    $cmd1 = $Args[1].ToLowerInvariant()

    switch($cmd1){
      "show" {
        WT-ShowFreeze $FreezeRoot $FreezeReceipt
        return
      }
      default {
        WT-Die ("UNKNOWN_FREEZE_SUBCOMMAND: " + $cmd1)
      }
    }
  }

  "packet" {
    if(@($Args).Count -lt 2){ WT-Die "PACKET_SUBCOMMAND_REQUIRED" }
    $cmd1 = $Args[1].ToLowerInvariant()

    switch($cmd1){
      "verify" {
        $script = Join-Path $ScriptsRoot "watchtower_packet_repair_and_verify_v1.ps1"
        WT-InvokeChild $script @("-RepoRoot",$RepoRoot)
        return
      }
      default {
        WT-Die ("UNKNOWN_PACKET_SUBCOMMAND: " + $cmd1)
      }
    }
  }

  "selftest" {
    if(@($Args).Count -lt 2){ WT-Die "SELFTEST_SUBCOMMAND_REQUIRED" }
    $cmd1 = $Args[1].ToLowerInvariant()

    switch($cmd1){
      "full-green" {
        $script = Join-Path $ScriptsRoot "_RUN_watchtower_live_state_full_green_v1.ps1"
        WT-InvokeChild $script @("-RepoRoot",$RepoRoot)
        return
      }
      "freeze" {
        $script = Join-Path $ScriptsRoot "_RUN_watchtower_tier0_freeze_v1.ps1"
        WT-InvokeChild $script @("-RepoRoot",$RepoRoot)
        return
      }
      default {
        WT-Die ("UNKNOWN_SELFTEST_SUBCOMMAND: " + $cmd1)
      }
    }
  }

  default {
    WT-Die ("UNKNOWN_COMMAND: " + $cmd0)
  }
}
