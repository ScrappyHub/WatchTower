# Contract: Watchtower → Atlas Artifact (Read-Only Feed)

Atlas consumes Watchtower device registry facts and posture labels.

## Provided views
- device roster: device_id, platform, posture, last_seen, policy_ref
- entitlements: posture thresholds required for job eligibility
- signed snapshots: periodic device_state_snapshot receipts

Atlas never writes to Watchtower except via wrapper receipts (optional).