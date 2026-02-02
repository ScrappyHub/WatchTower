param(
  [Parameter(Mandatory=$true)][string]$PacketId,
  [Parameter(Mandatory=$true)][string]$CommitHash,
  [Parameter(Mandatory=$true)][string]$SigPathRel,      # e.g. outbox/<PacketId>/signatures/ingest.sig
  [Parameter(Mandatory=$true)][string]$OutboxRel,       # e.g. outbox/<PacketId>
  [Parameter(Mandatory=$false)][string]$NflInboxRel="", # e.g. NFL/inbox/<PacketId> (optional)
  [Parameter(Mandatory=$false)][string]$PledgeLogHash=""# optional: from pledges.ndjson line
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Canon-Json([object]$Obj){
  # Canon v1 minimal: ConvertTo-Json -Compress is NOT fully canonical across all cases,
  # but it's deterministic enough for v1 if you constrain inputs (no floats, stable ordering).
  # If you later implement full canonicalizer in src\nfl\Canon.*, swap this routine.
  return ($Obj | ConvertTo-Json -Depth 50 -Compress)
}

function Sha256Hex([string]$s){
  $bytes = [Text.Encoding]::UTF8.GetBytes($s)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
}

$Repo = Split-Path -Parent $PSScriptRoot
Set-Location $Repo

$wpath = Join-Path $Repo "witness\witness.ndjson"
if(-not(Test-Path -LiteralPath $wpath)){ throw "Missing witness ledger: witness\witness.ndjson" }

$prev = "GENESIS"
$tail = Get-Content -LiteralPath $wpath -Tail 1 -ErrorAction SilentlyContinue
if($tail){
  try {
    $o = $tail | ConvertFrom-Json
    if($o.witness_hash){ $prev = [string]$o.witness_hash }
  } catch { }
}

$entry = [ordered]@{
  schema          = "repo.witness.v1"
  created_at_utc  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  producer        = "watchtower"
  producer_instance = "watchtower-local-1"
  tenant          = "single-tenant"
  principal       = "single-tenant/watchtower_authority/authority/watchtower"
  packet_id       = $PacketId
  commit_hash     = $CommitHash
  sig_path        = $SigPathRel
  outbox_rel      = $OutboxRel
  nfl_inbox_rel   = $NflInboxRel
  pledge_log_hash = $PledgeLogHash
  prev_witness_hash = $prev
}

$canon_no_hash = Canon-Json $entry
$wh = Sha256Hex $canon_no_hash

$entry.witness_hash = $wh
$line = Canon-Json $entry

Add-Content -LiteralPath $wpath -Encoding UTF8 -Value $line

Write-Host ("OK: appended witness line: {0}" -f $wh)