# Watchtower Ledger v1

## Storage
Primary transcript format: NDJSON.
Each line is a canonical JSON object conforming to ledger_event_v1.

## Hash Chain
hash = sha256(canonical_json(event_without_hash) || "\n")
prev_hash points to the prior event hash (or GENESIS for first event).

## Checkpoint Seal
Once per day (configurable), Watchtower emits event type:
- ledger.checkpoint.seal
Payload includes:
- transcript_head_hash
- checkpoint_range (start/end event_id)
- signature by Watchtower authority key