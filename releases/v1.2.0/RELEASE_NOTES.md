# SignatureGate v1.2.0

Release date: **2026-11-10**

## Summary

This coordinated release introduces the first versioned SignatureGate-Appsmith application source alongside the SignatureGate database, paper evidence, participant/contributor and cash-deposit upgrades. The production database upgrade and Appsmith master deployment were performed on November 10, with scoped operator verification. See the accepted [restored-production rehearsal](evidence/november_10_restored_production_migration_rehearsal.md) and [preproduction preparation](PREPRODUCTION_HANDOFF.md).

## Highlights

- Directory, Individual/Company Profiles and role-aware navigation; independent Participant and Contributor capacities, contact correction and person-level notes.
- Configurable Participant and Spiritual Practitioner display terminology without rewriting historical internal identifiers or executed documents.
- Atomic Intake with two contacts, role/assignment checks, durable request receipts and recovery, digital, later and paper agreement choices.
- Protected paper evidence: NocoDB storage, validation, request idempotency and cancellation/recovery, independent reviewer decisions and durable audit records; Drive new-upload UI remains disabled while historical Drive links and implementation are preserved.
- Contributor-independent cash/provider donation review and attribution, reports, operational cash deposit batching, confirmation, audit and optional ERP synchronization/retry.
- Preserved production Cash Deposits layout, native Appsmith IDs and production ERP mode semantics; inventory scope fails closed on explicitly malformed/empty scope.

## Released code and provenance

- SignatureGate backend and generated Appsmith export are included in the **v1.2.0** release commit and tag, to be recorded by the tagging operator.
- Canonical Appsmith source: `RayzorDuff/SignatureGate-Appsmith` `master` at **`809f1b8e23f228f671873e6d8752e208d52a3d9a`** (production candidate PR #16 merged, followed by documentation PR #17).
- Appsmith production datasource descriptor: `48905ca281271889cf6cb778cd0249a221b87c82`.
- Generated `appsmith/Rooted Psyche Membership Ops.json` and `appsmith/EXPORT_PROVENANCE.json` use the two exact source pins. The recorded generated export SHA-256 is `66fd39a8fa9fb07147a23d3e0d495266cf8a44d8789eb3a7e0e43c547b90b35d` (verify against the actual tagged file).
- Production-bound n8n paper workflow is `n8n/workflows/SignatureGate - Paper Agreement Upload.json`, updated on `main` at commit **`684c8776c98a28bd26c93fdff7ef54d3f7b55a8a`** with the two PostgreSQL credential selections changed to `signaturegate`. This source refresh also changed n8n node IDs/layout positions: the operator should retain the existing deployed workflow ID, previously accepted request/receipt state, and live credential bindings instead of blindly reimporting the file.
- The RootedOps source pin used during preparation is documented in `evidence/preproduction_integration_pins.json`; **its exact deployed production revision was not established by that source-only record**. This release does not claim a new ERP acceptance transaction.

## Production upgrade and accepted verification

1. The 12 forward SQL migrations selected in `UPGRADE_MANIFEST_DRAFT.json` (11 legacy replays skipped and separately audited terminology adoption omitted) were applied in the rehearsed order to production `signaturegate`. The operator's November 10 terminal transcript reported **12/12 PASS**.
2. The pre-migration custom-format production archive was saved with a validated SHA-256 checksum at `~/signaturegate-release-backups/v1.2.0/production-20261110T162541Z/`. Keep the backup and private evidence off GitHub.
3. Isolated rehearsal on restored production data previously reported **12/12 SQL verification tests PASS**, zero compared schema differences versus `signaturegate_test`, and the original 35 production-table row counts preserved.
4. Post-upgrade production read-only checks reported six core identity/Intake/paper objects present, zero invalid indexes and **zero violating agreement-status rows**. One `member_agreements_status_chk` constraint remains `NOT VALID`, though new/updated rows are checked.
5. Appsmith's production `signaturegate-postgres` datasource was observed using host `signaturegate-postgres:5432` and database `signaturegate`; a read-only query returned database/user `signaturegate`, PostgreSQL 16.13. The operator showed the merged `master` Directory loading 75 records in Appsmith; the temporary database diagnostic edit was discarded.
6. The operator confirmed the published application's Directory/Intake/Cash Deposits navigation and changed both existing live n8n paper upload nodes to the production PostgreSQL credential, then committed their exported workflow to SignatureGate `main`. These are configuration-level checks; **a new production paper upload/ERP transaction was not run** and is not required to restate prior accepted functionality.

## Known limitations, security and recovery follow-up

- Production app database role `signaturegate` is currently SUPERUSER and BYPASSRLS, as observed in the read-only post-upgrade query. Use an approved least-privilege role migration in a separate change; do not silently alter credentials during the cutover.
- The isolated functional rehearsal used `pg_restore --no-owner --no-acl`; a separate owner/ACL-preserving restore and protected row-content digest comparison have **not been reported complete**. The November 10 production backup checksum was verified, but that alone does not prove a full disaster-recovery restoration. Retain private backup and operational recovery work for follow-up.
- The current migration manifest records 12 selected entries, 11 skipped legacy entries, one excluded configuration operation and nine environment proofs originally left false. It is the reviewed source inventory, **not a signed record that every private proof was closed**. Do not automatically rerun the entire manifest against an already upgraded database.
- Spiritual Practitioner Functions → Assign Storage Location currently exposes a text input without the existing location suggestions. Follow-up: [Appsmith #18](https://github.com/RayzorDuff/SignatureGate-Appsmith/issues/18); no release claim that MushroomProcess locations automatically populate.
- Additional ERP end-to-end replay, optional new Google Drive upload verification, Playwright and broad accessibility tests remain deferred. Keep historical Drive references, ERP bank lookup/sync/retry/status, and prior signed evidence intact.

## Operational notes

- Retain production backups, release provenance, node/credential mappings and any exported live workflow configuration privately.
- Avoid importing the production-bound monolithic JSON into a new Appsmith workspace when Git Sync can update the existing application while preserving its identity. The existing Git-synchronized `master` was used for production promotion.
- Avoid replaying uncertain paper uploads, signing requests, or ERP accounting events as smoke tests.
- Consult [production promotion/recovery guidance](PREPRODUCTION_HANDOFF.md) for recovery boundaries. After writes resume, backup rollback requires reconciliation of new records and external effects.
- If a noncritical regression is discovered, prepare a focused **v1.2.1** repair rather than changing the released v1.2.0 tag.

## Coordinated release references

- SignatureGate source/tag: **v1.2.0**
- SignatureGate-Appsmith source: `809f1b8e23f228f671873e6d8752e208d52a3d9a` (tag separately after verifying branch head matches)
- RootedOps: current deployment unchanged by SignatureGate packaging; its actual deployed SHA remains an operational inventory item.
