# Canon

This document defines immutable behavior.

---

## Identity

Exactly one authority:

single-tenant/watchtower_authority/authority/watchtower

All signatures originate from this identity.

---

## Trust

trust_bundle.json is the only source of truth.

allowed_signers is derived only.

No implicit trust.

---

## Receipts

All actions append to:

proofs/receipts/neverlost.ndjson

Constraints:

• append-only
• UTF-8
• LF only
• deterministic ordering
• sha256-hashable

No edits.

---

## Determinism

Equal inputs must yield equal outputs.

Differences indicate fault.

---

## Namespaces

Only namespaces present in trust_bundle are valid.

All others are rejected.

---

## Overlay

overlay_policy ∩ canonical_policy

Overlay may restrict only.

Overlay may not permit.

---

## Scope

Watchtower verifies and attests only.

No execution.

No mutation.

No orchestration.

---

## Packet Model

Packets are directories.

Detached signatures only.

Verification must work offline.

---

## Philosophy

Small.
Boring.
Auditable.
