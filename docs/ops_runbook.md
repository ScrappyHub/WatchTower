# Watchtower Operations Runbook

This file documents deterministic operational steps.

---

## First Time Setup

Generate allowed signers

powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\make_allowed_signers_v1.ps1 -RepoRoot .


---

## Show Identity

powershell.exe -File scripts\show_identity_v1.ps1 -RepoRoot .


---

## Ingest Packet

Place packet directory into:

packets/inbox/

Run:

powershell.exe -File scripts\watchtower_ingest_packet_v1.ps1 -RepoRoot . -PacketDir packets\inbox<packet>


Results:

• verified → receipts written  
• invalid → moved to quarantine  

---

## Re-verify Quarantine

powershell.exe -File scripts\watchtower_verify_quarantine_v1.ps1 -RepoRoot .


---

## Emit Device Pledge

powershell.exe -File scripts\watchtower_emit_device_pledge_v1.ps1 -RepoRoot .


Produces signed pledge in outbox.

---

## Duplicate Receipts to NFL

powershell.exe -File scripts\watchtower_duplicate_to_nfl_v1.ps1 -RepoRoot .


---

## Repair Trust

After trust_bundle change:

powershell.exe -File scripts\make_allowed_signers_v1.ps1 -RepoRoot .


---

## NEVER DO

• never edit receipts  
• never edit allowed_signers manually  
• never bypass trust_bundle  
• never run scripts interactively  
• never depend on environment variables  

All runs must be file-based and deterministic.

---

## Debug Rule

If hashes differ across runs:

Treat as bug immediately.
