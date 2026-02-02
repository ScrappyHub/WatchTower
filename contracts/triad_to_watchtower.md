# Contract: TRIAD → Watchtower (RunReceipt v1)

Watchtower ingests TRIAD receipts without re-proving semantics.

## Minimum ingest fields
- run_id
- device_id
- device_identity_hash
- artifact_id
- roots:
  - block_root
  - semantic_root
  - transcript_root
  - policy_hash
  - identity_hash
- result: pass|fail
- invariants_summary (optional)
- triad_version
- verifier_set (optional)
- signatures (TRIAD)

## Watchtower behavior
- verify signature authenticity + required fields present
- record receipt hash
- write ledger events:
  - device.triad.run.receipt
  - device.attestation.received (type=triad)
  - device.attestation.verified (pass/fail)
- emit Watchtower Receipt Artifact v1 for ingestion outcome