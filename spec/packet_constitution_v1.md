# Packet Constitution v1 — Finalization Law (Watchtower)

Canonical bytes:
- UTF-8 no BOM
- LF newlines
- canonical JSON

PacketId:
SHA-256(canonical_bytes(manifest-without-id))

Option A (default):
manifest.json MUST NOT contain packet_id
packet_id.txt stores PacketId

Finalization order:
payload → manifest → signatures → packet_id.txt → sha256sums.txt → receipts

Verification:
MUST NOT mutate packets.
Read-only verification only.