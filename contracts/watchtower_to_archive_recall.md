# Contract: Watchtower → Archive Recall

Archive Recall consumes device/storage metadata + provenance receipts.

Watchtower provides:
- storage inventory snapshot (metadata only)
- posture label + policy_ref
- signed custody receipts for import/restore provenance

Archive Recall remains the library system; Watchtower remains the witness.