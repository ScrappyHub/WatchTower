# Contract: Watchtower → TRIAD (RunRequest v1)

TRIAD consumes Watchtower-signed RunRequests as inputs.

## Files
run_request.json
run_request.sig
run_request.sha256

## Required fields (run_request.json)
- schema_version: "1"
- tenant_id
- run_id (Watchtower issued)
- device_id
- device_identity_hash
- operation: capture|restore|verify|attest_only
- target: selectors (disk/volume/path)
- policy_ref: {policy_id, policy_hash}
- required_acceptance:
  - block_proof_required (bool)
  - semantic_proof_required (bool)
  - independent_agreement_required (int)
- issued_at_utc
- expires_at_utc

## Rules
- TRIAD must record the sha256 of run_request.json in its transcript.
- TRIAD must not call Watchtower for identity; it trusts the signed packet.