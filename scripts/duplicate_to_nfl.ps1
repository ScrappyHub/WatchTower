param(
  [Parameter(Mandatory=$true)][string]$PacketId
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Producer="Watchtower"
$src = Join-Path "C:\ProgramData\$Producer\outbox" $PacketId
$dst = Join-Path "C:\ProgramData\NFL\inbox" $PacketId

if(-not(Test-Path -LiteralPath $src)){ throw "Missing source packet: $src" }

# Ensure destination does not partially exist
if(Test-Path -LiteralPath $dst){
  throw "Destination already exists (refuse overwrite): $dst"
}

New-Item -ItemType Directory -Force -Path $dst | Out-Null

# Byte-identical copy (preserve structure; content is what matters)
Copy-Item -LiteralPath (Join-Path $src "*") -Destination $dst -Recurse -Force

Write-Host "OK: duplicated packet to NFL inbox"
Write-Host ("SRC: {0}" -f $src)
Write-Host ("DST: {0}" -f $dst)