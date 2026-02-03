# Watchtower Canon

This document defines immutable behavioral law.

These rules must never change without a version bump.

---

## Identity Law

Watchtower has exactly one authority identity:

principal:
single-tenant/watchtower_authority/authority/watchtower

All signatures originate from this identity.

---

## Trust Law

trust_bundle.json is the only source of truth.

allowed_signers MUST be derived.

Nothing else is trusted.

---

## Receipt Law

Every action MUST append a receipt to:

proofs/receipts/neverlost.ndjson

Receipts are:

• UTF-8
• no BOM
• LF only
• append-only
• hashed

No edits.
No rewrites.
No truncation.

---

## Determinism Law

Given identical inputs:

• packet
• trust bundle
• allowed signers
• policy

Watchtower MUST produce identical outputs and hashes.

---

## Namespace Law

Watchtower only accepts namespaces present in trust_bundle.

Unknown namespaces are rejected.

---

## Overlay Law

Overlay policy may only restrict.

effective_policy = canonical ∩ overlay

Overlay may never permit what canonical denies.

---

## Transport Law (Packet Constitution)

Packets are directories.

Detached signatures only.

No inline signatures.

No network trust.

Everything must verify locally.

---

## Scope Law

Watchtower does NOT:

• update software
• modify systems
• execute payloads
• act as agent

It only verifies and attests.

---

## Failure Law

If verification cannot be reproduced deterministically:

The packet is invalid.

---

## Philosophy

Watchtower is a measuring instrument.

Not a smart system.

Not adaptive.

Not heuristic.

Pure verification only.
