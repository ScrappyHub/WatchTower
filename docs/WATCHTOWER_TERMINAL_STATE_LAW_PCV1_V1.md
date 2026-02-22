# WatchTower - Terminal State Law (PCv1 Option A) - v1

## Purpose
WatchTower is a verification plane: it verifies Packet Constitution v1 Option A packets non-mutatingly, ingests inbox packets deterministically, and emits deterministic verification outcomes/receipts.
WatchTower does not invent truth; it only verifies, moves, and records.

This law defines terminal destinations and selftest semantics so Tier-0 behavior is stable and drift-proof.

## Definitions
- PacketRoot: A directory containing a Packet Constitution v1 Option A packet (manifest.json, sha256sums.txt, payload/...). packet_id.txt MAY exist (out-of-band) and MUST be included in sha256sums when present.
- PacketId: SHA-256 of canonical manifest bytes per Option A rules (packet_id.txt is out-of-band).
- Non-mutating verify: verification must never modify packet bytes; it may only read and compute.

## Terminal State Law
### Directories
- packets\inbox\     - staging area for inbound packets awaiting ingest
- packets\quarantine\ - terminal destination for packets that FAIL verification
- packets\receipts\  - terminal destination for packets that PASS verification (and are ingested/recorded)
- packets\processed\ - optional legacy/compat destination (NOT required for Tier-0). If present, it may be treated as a success terminal but is not authoritative.

### Terminal invariants
1. A packet that fails verification MUST end in packets\quarantine\ (Tier-0 ingest uses quarantine on fail).
2. A packet that passes verification MUST be moved out of packets\inbox\ to a success terminal.
3. The authoritative success terminal for Tier-0 is packets\receipts\ (dir-name preserved), where deterministic receipts/outcomes are recorded.
4. The ingest pipeline MUST be compatible with -PacketRoot pinning: when -PacketRoot is provided, ingest MUST only ingest that directory (no inbox scan drift).
5. Selftests MUST treat packets\receipts\ as a valid success terminal destination.

## Selftest Law (Tier-0)
The ingest selftest is PASS if:
- The minimal packet vector is copied into packets\inbox\_<selftest...> deterministically,
- Verify returns VERIFY_OK PacketId=<...>,
- Ingest emits PCV1_OK: <dir> PacketId=<...>,
- The packet directory is moved to the success terminal (packets\receipts\),
- The selftest confirms the moved directory exists in receipts by exact directory name.

## Compatibility note
Older selftests that only searched processed/quarantine by PacketId prefix are non-authoritative under this law. Under this law, receipts is terminal.

## Encoding + determinism
- PowerShell 5.1 + StrictMode Latest
- UTF-8 no BOM, LF only
- Hashes: SHA-256 over bytes as specified by PCv1 Option A
- Receipts: append-only, deterministic structure; include UTC timestamp
