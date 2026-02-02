# Watchtower Receipt Artifact v1

A Watchtower receipt is a deterministic evidence packet consumable by other instruments.

## Layout
receipt/
  manifest.json
  sha256sums.txt
  signatures/
    receipt.ed25519.sig
  payload/
    receipt.json
    transcript_slice.ndjson   (optional)

## IDs
receipt_id = sha256(canonical_json(payload/receipt.json))

## Signing
- receipt.ed25519.sig is detached signature over receipt_id (or over receipt.json bytes; choose one and lock).
Canonical rule: sign receipt_id (hex) + "\n" as UTF-8 bytes.

## receipt.json fields
- schema_version
- tenant_id
- receipt_id
- kind (enrollment|attestation_ingest|policy_apply|triad_run_ingest|checkpoint_seal|export)
- device_id (optional depending on kind)
- refs: list of {type, sha256, media_type}
- policy_ref (if relevant)
- created_at_utc
- signer_key_id