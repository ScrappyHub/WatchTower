param(
  [Parameter(Mandatory=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$RepoRoot,

  # Producer identity (Watchtower)
  [string]$Tenant = "single-tenant",
  [string]$Producer = "watchtower",
  [string]$ProducerInstance = "watchtower-local-1",

  # Signing (Watchtower device/authority key â€” for now use authority)
  [string]$AuthorityKey = "C:\dev\watchtower\proofs\keys\watchtower_authority_ed25519",
  [string]$Principal = "single-tenant/watchtower_authority/authority/watchtower",
  [string]$KeyId = "watchtower-authority-ed25519",

  
  [string]$SignerIdentity = "watchtower-authority",
# Canonical transport roots
  [string]$Outbox = "C:\ProgramData\Watchtower\outbox",
  [string]$PledgesDir = "C:\ProgramData\Watchtower\pledges",

  # Where NFL inbox is (offline drop target)
  [string]$NflInbox = "C:\ProgramData\NFL\inbox"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $RepoRoot "scripts\_lib_watchtower_canon_v1.ps1")

function Commit([string]$EventType, [string[]]$PrevLinks, [hashtable]$ContentRef, [string]$Strength) {
  $nowUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

  $payload = [ordered]@{
    schema = "commitment.v1"
    producer = $Producer
    producer_instance = $ProducerInstance
    event_type = $EventType
    event_time = $nowUtc
    prev_links = @($PrevLinks)
    content_ref = $ContentRef
    strength = $Strength
  }

  $json = To-CanonJson $payload 40
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json + "`n")
  $commitHash = Sha256HexBytes $bytes

  return [ordered]@{
    commit_hash = $commitHash
    payload_json = $json
    payload_bytes = $bytes
    event_time = $nowUtc
  }
}

function PledgeLocal([hashtable]$Commit, [string]$ProducerSigPath) {
  Ensure-Dir $PledgesDir

  $logPath = Join-Path $PledgesDir "pledges.ndjson"
  $prevLogHash = "GENESIS"
  if (Test-Path -LiteralPath $logPath) {
    $tail = Get-Content -LiteralPath $logPath -Tail 1
    if ($tail) {
      $obj = $tail | ConvertFrom-Json
      if ($obj.log_hash) { $prevLogHash = [string]$obj.log_hash }
    }
  }

  $seq = 0
  if (Test-Path -LiteralPath $logPath) {
    $count = (Get-Content -LiteralPath $logPath).Count
    $seq = [int]$count
  }

  $entry = [ordered]@{
    schema = "watchtower.local_pledge.v1"
    tenant = $Tenant
    producer = $Producer
    producer_instance = $ProducerInstance
    seq = $seq
    commit_hash = $Commit.commit_hash
    prev_log_hash = $prevLogHash
    principal = $Principal
    key_id = $KeyId
    sig_path = $ProducerSigPath
    created_at_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  }

  $entryJson = To-CanonJson $entry 40
  $entryBytes = [System.Text.Encoding]::UTF8.GetBytes($entryJson + "`n")
  $logHash = Sha256HexBytes $entryBytes
  $entry.log_hash = $logHash

  $finalJson = (To-CanonJson $entry 40) + "`n"
  Add-Content -LiteralPath $logPath -Value $finalJson -Encoding UTF8

  return $logHash
}

function DuplicateToNFL([hashtable]$Commit, [string]$ProducerSigB64, [string]$ProducerSigAlg, [string]$ProducerSigKeyId) {
  Ensure-Dir $Outbox

  $ingest = [ordered]@{
    schema = "nfl.ingest.v1"
    commit_hash = $Commit.commit_hash
    producer = $Producer
    producer_sig = [ordered]@{
      principal = $Principal
      key_id = $ProducerSigKeyId
      alg = $ProducerSigAlg
      sig = $ProducerSigB64
    }
    prev_links = @()
    event_type = $null
    producer_time = $Commit.event_time
    payload_bytes = $null
  }

  $tmp = Join-Path $Outbox ("_tmp_" + [Guid]::NewGuid().ToString("N"))
  $payloadDir = Join-Path $tmp "payload"
  $sigDir = Join-Path $tmp "signatures"
  Ensure-Dir $payloadDir
  Ensure-Dir $sigDir

  $commitPath = Join-Path $payloadDir "commit.payload.json"
  Write-Utf8NoBom $commitPath ($Commit.payload_json + "`n")

  $commitHashPath = Join-Path $payloadDir "commit_hash.txt"
  Write-Utf8NoBom $commitHashPath ($Commit.commit_hash + "`n")

  $ingestPath = Join-Path $payloadDir "nfl.ingest.json"
  $ingest.event_type = ($Commit.payload_json | ConvertFrom-Json).event_type
  $ingest.prev_links = @((($Commit.payload_json | ConvertFrom-Json).prev_links))
  Write-Utf8NoBom $ingestPath ((To-CanonJson $ingest 40) + "`n")

  $sigEnv = [ordered]@{
    schema = "sig_envelope.v1"
    principal = $Principal
    key_id = $ProducerSigKeyId
    alg = $ProducerSigAlg
    sig_path = "signatures/ingest.sig"
    signed_file = "payload/commit_hash.txt"
    namespace = "nfl"
  }
  Write-Utf8NoBom (Join-Path $payloadDir "sig_envelope.json") ((To-CanonJson $sigEnv 40) + "`n")

  $sigOut = Join-Path $sigDir "ingest.sig"
  SshYSignFile -KeyPath $AuthorityKey -Namespace "nfl" -SignerIdentity $SignerIdentity -FileToSign $commitHashPath -SigOut $sigOut

  $manifest = [ordered]@{
    schema = "packet.manifest.v1"
    schema_version = "1"
    kind = "nfl.ingest"
    producer = $Producer
    commit_hash = $Commit.commit_hash
    created_at_utc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    payload = [ordered]@{
      commit_payload = "payload/commit.payload.json"
      commit_hash = "payload/commit_hash.txt"
      nfl_ingest = "payload/nfl.ingest.json"
      sig_envelope = "payload/sig_envelope.json"
    }
    signatures = [ordered]@{
      ingest_sig = "signatures/ingest.sig"
    }
  }
  Write-Utf8NoBom (Join-Path $tmp "manifest.json") ((To-CanonJson $manifest 40) + "`n")

  Write-Sha256Sums $tmp

  $packetSha = PacketSha $tmp
  $final = Join-Path $Outbox $packetSha
  if (Test-Path -LiteralPath $final) { Remove-Item -LiteralPath $final -Recurse -Force }
  Move-Item -LiteralPath $tmp -Destination $final -Force

  Ensure-Dir $NflInbox
  $dest = Join-Path $NflInbox $packetSha
  if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
  Copy-Item -LiteralPath $final -Destination $dest -Recurse -Force

  return $packetSha
}

# -----------------------------
# Execute once (minimal example)
# -----------------------------
Ensure-Dir $Outbox
Ensure-Dir $PledgesDir

$commit = Commit -EventType "watchtower.device.observed.v1" -PrevLinks @() -ContentRef ([ordered]@{ kind="sealed"; ref="none" }) -Strength "evidence"
$packetId = DuplicateToNFL -Commit $commit -ProducerSigB64 "" -ProducerSigAlg "openssh-ed25519" -ProducerSigKeyId $KeyId
$producerSigPath = ("outbox/{0}/signatures/ingest.sig" -f $packetId)
$logHash = PledgeLocal -Commit $commit -ProducerSigPath $producerSigPath

Write-Host ("OK: CommitHash: {0}" -f $commit.commit_hash) -ForegroundColor Green
Write-Host ("OK: NFL packet (outbox + delivered to NFL inbox): {0}" -f $packetId) -ForegroundColor Green
Write-Host ("OK: Local pledge log hash: {0}" -f $logHash) -ForegroundColor Green