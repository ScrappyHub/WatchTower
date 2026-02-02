# Watchtower Canonical Spec v1

## Definition
Watchtower is a deterministic device custody and attestation instrument that observes, measures, and cryptographically
records every device that crosses into the system boundary. Watchtower does not manage or control devices; it
establishes verifiable truth about them.

## Hard Boundary

### Watchtower owns
- Device identity & enrollment
- Device registry (fleet inventory: metadata, not payload imaging)
- Observation snapshots (metadata sets)
- Attestation collection & verification results (platform / TRIAD / wrappers)
- Custody ledger + transcripts (append-only, hash-chained)
- Policy distribution as constraints (policy authored/decided elsewhere)

### Watchtower does NOT own
- Scheduling jobs (Atlas Artifact)
- Capture/restore/verify/attest/seal/transcript of artifacts (TRIAD)
- Repair logic (Legacy Doctor)
- Archive library behavior (Archive Recall)
- Governance decisions (Covenant Gate)

## Identity Model

### Identifiers
- device_id: Watchtower-issued stable UUID (recommended UUIDv7)
- identity_hash: sha256(canonical_json(DeviceIdentityV1))

device_id is permanent. identity_hash may change; changes are recorded as events.

### Identity Tiers
- Tier0 (dev): file key allowed; identity_class=user-asserted
- Tier1: OS keystore key required; identity_class=os-rooted
- Tier2: TPM key + quote evidence; identity_class=hardware-rooted

## Enrollment Ceremony
1) Device generates device key (tier-specific) and creates JoinRequest.
2) Device obtains pairing token (time-bounded).
3) Admin approves JoinRequest, Watchtower issues EnrollmentReceipt.
4) Watchtower assigns device_id and publishes initial policy constraints bundle reference.
5) Device becomes ENROLLED; posture computed by constraints + evidence.

Offline enrollment is supported via signed outbox/inbox packets.

## Observations
Watchtower records ObservationSets: normalized, policy-scoped metadata snapshots.
Watchtower never records secrets. Redaction is not a feature; instead, collection is policy-gated.

## Attestations
Watchtower accepts:
- Platform attestation (device â†’ Watchtower): signed ObservationSet; optional TPM quote bundle.
- TRIAD attestation (TRIAD â†’ Watchtower): run receipt with ArtifactId + roots + transcript_root + hashes.
- Wrapper receipts (Atlas/Legacy Doctor/Security instruments): signed run summaries with artifact hash references.

Watchtower verifies signatures + required fields; it does not re-prove TRIAD semantics.

## Ledger & Transcript
- Append-only NDJSON events.
- Each event includes prev_hash and hash.
- Daily checkpoint seals (configurable) create a SealEvent referencing transcript_head hash and checkpoint signature.

## Receipts & Artifacts
Watchtower emits Receipt Artifact v1 (manifest + sha256sums + optional transcript slice + detached signature).

## Policy Interaction (Covenant Gate)
- Gate is policy source of truth.
- Watchtower consumes signed PolicyBundle.
- Watchtower enforces constraints only: minimum attestation grades, quarantine thresholds, allowed operations.
- Overlays can only add walls; never weaken baseline.

## Posture / Zones
Posture is a computed label recorded in events:
unknown â†’ observed â†’ enrolled â†’ verified â†’ high_assurance
Failures â†’ quarantined
Decommission â†’ retired

Upgrade/downgrade triggers are policy-driven.
Watchtower records results; it does not invent policy.
