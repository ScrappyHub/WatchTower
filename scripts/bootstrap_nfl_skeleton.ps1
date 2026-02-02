$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Repo = Split-Path -Parent $PSScriptRoot
Set-Location $Repo

$dirs = @(
  "schemas",
  "contracts",
  "src\nfl",
  "tests\vectors\sample_packet\payload",
  "tests\vectors\sample_packet\signatures",
  "scripts",
  "witness"
)

foreach($d in $dirs){
  $p = Join-Path $Repo $d
  if(-not(Test-Path -LiteralPath $p)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

$w = Join-Path $Repo "witness\witness.ndjson"
if(-not(Test-Path -LiteralPath $w)){
  Set-Content -LiteralPath $w -Value "" -Encoding UTF8 -NoNewline
}

Write-Host "OK: NFL skeleton folders ensured + witness\witness.ndjson present"