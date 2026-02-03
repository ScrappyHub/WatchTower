# Watchtower

Watchtower is a deterministic, cryptographically-verifiable maintenance and packet-ingest instrument.

It is NOT an OS.
It is NOT an updater.
It is NOT an agent.

It is a **boring, auditable verifier**.

Its only responsibilities:

• Verify signed packets  
• Enforce trust + namespace policy  
• Emit append-only receipts  
• Duplicate receipts to NFL  
• Produce device pledges  

Everything else is out of scope.

---

## Governing Standards

Watchtower strictly follows:

• NeverLost v1 (identity + receipts)  
• Packet Constitution v1 (directory packets + detached signatures)  
• AnchorMark (mandatory receipt duplication)  
• Deterministic PowerShell execution only  

---

## Canonical Properties

Watchtower must always be:

• Deterministic  
• Offline-capable  
• Reproducible  
• Append-only  
• Hash-addressed  
• Signature-verifiable  

If behavior is nondeterministic, it is a bug.

---

## Repository Layout

proofs/
keys/
trust/
receipts/

packets/
inbox/
outbox/
quarantine/
receipts/

scripts/

policy/
docs/


---

## Identity

Principal:

single-tenant/watchtower_authority/authority/watchtower

KeyId:

watchtower-authority-ed25519

---

## Required Workflow

### Regenerate allowed signers

powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\make_allowed_signers_v1.ps1 -RepoRoot .


### Verify packet

powershell.exe -File scripts\watchtower_ingest_packet_v1.ps1 -RepoRoot . -PacketDir packets\inbox<packet>


### Emit pledge

powershell.exe -File scripts\watchtower_emit_device_pledge_v1.ps1 -RepoRoot .


---

## Security Rules

• trust_bundle.json is source of truth  
• allowed_signers is derived only  
• receipts are append-only  
• overlays may only add restrictions  
• no network required for verification  
• no hidden defaults  
• all outputs must be hashable  

---

## Design Philosophy

Small.  
Boring.  
Verifiable.

If it grows complicated, split it out.

Watchtower is an instrument, not a platform.
