# Watchtower RBAC v1

Roles:
- Owner
- OrgAdmin
- DeviceAdmin
- Operator
- Auditor
- DeviceAgent (machine principal)

Must-have boundaries:
1) Enrollment / revocation is OrgAdmin+ only (Owner implicit).
2) Operator can request actions (create RunRequests) but cannot approve enroll/revoke.
3) Auditor is read-only; access to raw identifiers is policy-gated (prefer hashed facts).
4) DeviceAgent can write only:
   - its own ObservationSets
   - its own platform attestations
   It cannot read fleet or policies beyond what it is issued.
5) Policy bundles can be installed only by OrgAdmin (or by verified Gate channel).