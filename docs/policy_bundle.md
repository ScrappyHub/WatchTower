# Policy Bundle (Covenant Gate → Watchtower) v1

Watchtower consumes signed policy bundles and enforces constraints only.

## Fields
- policy_id
- policy_hash
- baseline_hash
- overlay_hashes[]
- constraints:
  - min_identity_tier: 0|1|2
  - min_attestation_grade: platform_signed|tpm_quote
  - quarantine_on_failed_attestation: true|false
  - allowed_operations: [triad.capture, triad.restore, triad.verify, ...]
  - ttl_seconds
- signature (Gate authority)

Overlays may only add walls; never weaken baseline.