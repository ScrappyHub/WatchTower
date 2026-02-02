# Contract: Watchtower ↔ Legacy Doctor

Legacy Doctor consumes device identity + allowed operations list (constraints).

Legacy Doctor may emit wrapper receipts:
- repair run summary
- health scan summary
- evidence hashes pointing to Legacy Doctor artifacts

Watchtower records wrapper receipts as attestation_type=wrapper.