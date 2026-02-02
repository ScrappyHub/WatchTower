# Device Posture / Zones v1

Posture is a computed label recorded in ledger events.

- unknown: device seen, no trusted identity
- observed: device has identity packet but not approved
- enrolled: admin approved, device_id assigned
- verified: meets policy min attestation grade + recent heartbeat
- high_assurance: TPM-backed + secure boot evidence + policy-required cadence satisfied
- quarantined: failed checks or revoked
- retired: decommissioned; no longer valid

Upgrade/downgrade triggers are policy-driven.
Watchtower records results; it does not invent policy.