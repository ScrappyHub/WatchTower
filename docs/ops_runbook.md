# Operations

All commands are deterministic.

---

## Regenerate trust material

powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\make_allowed_signers_v1.ps1 -RepoRoot .


---

## Show identity

powershell.exe -File scripts\show_identity_v1.ps1 -RepoRoot .


---

## Ingest packet

powershell.exe -File scripts\watchtower_ingest_packet_v1.ps1 -RepoRoot . -PacketDir packets\inbox<packet>


---

## Emit device pledge

powershell.exe -File scripts\watchtower_emit_device_pledge_v1.ps1 -RepoRoot .


---

## Duplicate receipts to NFL

powershell.exe -File scripts\watchtower_duplicate_to_nfl_v1.ps1 -RepoRoot .


---

## Rules

• never edit receipts  
• never edit allowed_signers  
• never bypass trust_bundle  
• never run interactively  
• never depend on machine state  

Only file-based execution is valid.
