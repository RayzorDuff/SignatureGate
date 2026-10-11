# Current v1.2.0 migration candidates

**Pending effective-definition review and restored-production rehearsal; not a production execution manifest.** The original `evidence/migrations.csv` is the initial source-audit snapshot. This document records changed/new candidates without rewriting that baseline. Only technical objects and source checksums are recorded here.

| Candidate | Current SHA-256 | Evidence / prerequisites | Verification / recovery |
| --- | --- | --- | --- |
| `agreement_type_administration.sql` | `574a862369297919a3d0b062acd9341ce6aaecc95edd01e139808939c6524abd` | Operator-reported test application/behavior pass; production API absent at capture. Requires canonical person roles/accounts, agreement types and audit log | `verify_agreement_type_administration.sql`; one transaction; restored-copy rehearsal before production |
| `party_identity_notes.sql` | `7c1737c58829913d34233ee0688000eff08ec3a0096579bd983b6ceac17fa6f3` | Test APIs present at capture; production missing both note columns/APIs. New provenance/helper required in both. Requires canonical people/organizations/participants, directory/role helpers and audit log | `verify_party_identity_notes.sql`; explicit transaction, second-run check, Profile/`Intake` acceptance. Restore rehearsed backup for committed upgrade recovery; retain original source notes/provenance, do not delete/replay markers to force import |
| `organization_contact_reassignment.sql` | `305d14749513812f791fd6c69f1ce4725cd7f5f056ba0905e1fe78f26f3b54d9` | Production API absent; changed contact views require effective SQL review first | `verify_organization_contact_reassignment.sql` plus ownership cases; explicit transaction and restored-copy upgrade/recovery rehearsal |

No order among these independent candidates is approved yet. Each must follow its canonical identity/contact/role prerequisites; do not replay overlapping cash or role migrations without effective-definition review. Cash revival requires the final reason-aware behavior before its candidate is selected. Four changed function hashes and three changed views remain held for review. Column-position-only differences require no column reordering.

Next: privately capture definitions with `capture_effective_definition_review.sql`; classify intended behavior/grants, reconstruct any missing forward changes, record a dependency-ordered production manifest with exact checksums and recovery, then rehearse it against a protected restored production copy. Raw records, definitions with operational literals and configuration mappings remain outside Git.
