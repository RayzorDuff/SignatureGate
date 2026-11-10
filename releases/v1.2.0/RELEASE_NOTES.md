# SignatureGate v1.2.0 — release candidate notes (draft; NOT YET RELEASED)

**Release date:** Pending production acceptance and final tag.

**Status:** Prepared release notes only. `VERSION` remains `1.1.0`; no production schema migration, Appsmith publication, release tag, or production n8n promotion is established by this document. This file may be finalized only after the operator's approved cutover and actual verification.

## Summary

This coordinated release advances SignatureGate's Participant, Contributor, agreement and donation workflows, with its first versioned SignatureGate-Appsmith application source and generated JSON export. It preserves existing ERPNext accounting integration and the separate MushroomProcess inventory boundary.

## Application and functional changes

- Consolidated Directory and identity/capacity workflows, with Individual and Company Profiles, person-level notes and guarded contact ownership/reassignment including inactive Participant correction.
- Configurable organization-facing Participant and Spiritual Practitioner terminology while retaining stable internal identifiers and historical signed records.
- Unified atomic Intake with two-contact enrollment, capacity selection, assigned practitioner, saved receipt/replay/recovery, optional later agreement, digital signing, and a separately accepted same-screen paper-upload path.
- NocoDB paper agreement storage with bounded file validation, independent reviewer approval, recoverable upload receipts and audited cancellation; new Google Drive upload selection is deferred in the UI while implementation and older Drive links remain.
- Contributor-independent identity and donation review, including company/individual contributors, cash verification, attribution reassignment and reporting separation.
- Cash Deposit preparation/confirmation, eligibility/immutability, tally/print, audit, and existing optional RootedOps/ERPNext synchronization/status/retry contracts.
- Role-aware grouped navigation, Directory-to-Profile routing and scope-aware practitioner/reviewer access. Preserves `master` Cash Deposits layout, native Appsmith IDs and production ERP API/controller modes.
- Hardened inventory location scope: explicitly empty/malformed scope fails closed; omitted-scope compatibility retained.

## Database migration and recovery

The proposed production upgrade contains **12 selected forward migration files** from `releases/v1.2.0/UPGRADE_MANIFEST_DRAFT.json`, **11 skipped legacy replays** and **one separately reviewed audited terminology operation excluded from the generic upgrade**. The draft remains non-executable until the nine protected environment proofs are signed off.

On November 10, 2026, a custom production backup was restored into isolated PostgreSQL 16.13. All 12 proposed migrations and 12 targeted SQL verification scripts passed, the compared upgraded schema matched development with zero structural differences and all 35 original production tables had unchanged row counts. See [rehearsal evidence](evidence/november_10_restored_production_migration_rehearsal.md).

**No claim is made that production has been migrated**. Required cutover steps include owner/ACL-preserving restore, actual app and n8n role/grant review, historical-data/backfill invariants, final backup, isolated workers, recovery exercise, and approval of selected dispositions.

## Application and integration packaging

- **Appsmith production candidate:** PR #16 merged at `87cd74f5ee40dfe134a56ca92f5f4cfeb47065fe`, preserving reviewed source and native IDs.
- **Appsmith documentation-only follow-up:** PR #17 merged at `809f1b8e23f228f671873e6d8752e208d52a3d9a`. This is the **current exact Appsmith master export source pin**, subject to any later merges.
- **Production descriptor baseline:** Appsmith commit `48905ca281271889cf6cb778cd0249a221b87c82`. Review and retain its native `signaturegate-postgres` descriptor SHA-256.
- **Export artifact:** Pending regeneration from those two exact commit pins and check-in of `appsmith/Rooted Psyche Membership Ops.json` and `appsmith/EXPORT_PROVENANCE.json` in SignatureGate. The earlier PR #16 disposable export digest is **not** the final shipped artifact.
- **Integration pins:** See `evidence/preproduction_integration_pins.json`. The actual deployed RootedOps revision, n8n workflow versions/credentials and paper workflow production PG bindings still require private runtime verification.

The agreed export procedure is [appsmith/EXPORT.md](../../appsmith/EXPORT.md). Source metadata rebinding does not change saved Appsmith credentials/connection targets or publish the application.

## Accepted verification

- Network-isolated production-restore schema rehearsal: **12/12 migrations PASS**.
- Targeted rollback-only SQL suite: **12/12 PASS**.
- Compared schema category differences: **0**.
- Original production table row-count preservation: **35/35**.
- Native NocoDB test paper upload/retrieval/independent reviewer/audit: accepted under [paper evidence](evidence/november_10_paper_native_retry.md).
- Same-screen Intake paper enrollment and saved receipt recovery: operator reported PASS in the subsequent development session; new synthetic agreement remained pending independent review.
- Appsmith candidate source/controller, production ERP modes, native identity preservation and disposable deterministic export tests: operator reported PASS; exact release export from merged master remains pending.

## Deployment order and release gates

1. Regenerate the release export using the **final exact Appsmith `master` SHA**, a separately pinned production descriptor SHA and identical local/Action preparation logic. Inspect generated provenance/JSON and record the export workflow run.
2. Complete and privately approve all nine production environment proofs in the migration manifest; verify actual roles/grants/data invariants, deployed RootedOps/n8n/Documenso/NocoDB routing and old-app read compatibility.
3. Approve production maintenance and recovery, freeze or isolate writers, capture final production backup and matching service settings; execute only the approved hash-checked selected migration list.
4. Verify schema, data invariants, roles/grants, old/new app compatibility, paper request and cash-state contracts before resuming writes.
5. Publish the approved Appsmith revision against the **actual** production `signaturegate` datasource; rebind paper workflow's two PG nodes to reviewed production credentials, verify caller routes/worker state and resume reviewed consumers in sequence.
6. Confirm actual deployment/published revision and smoke evidence, finalize dependency pins and release notes, update `VERSION`/README/changelog with the established release tooling, run `make release-check`, then create/publish the final `v1.2.0` Git tag and release.

**Do not tag early:** a Git source merge or a successful isolated rehearsal does not establish a production deployment.

## Deferred / not release-blocking

A second ERP end-to-end transaction replay, optional Google Drive new-upload acceptance, full Playwright browser harness, broad mobile/accessibility navigation testing and issue-wide future identity/terminology expansion are deferred. Existing integration functionality is preserved; deferral is not a decision to disable ERP.

## Final evidence to fill before publishing

- [ ] Final backend packaging commit and `VERSION=1.2.0`.
- [ ] Exact Appsmith master source SHA and descriptor commit SHA.
- [ ] Regenerate Appsmith export workflow run URL, generated JSON SHA-256 and `EXPORT_PROVENANCE.json`.
- [ ] Approved manifest including selected/skipped dispositions, private evidence sign-offs and recovery rehearsal.
- [ ] Actual deployed RootedOps tag/SHA, n8n workflow revisions, saved datasource identities/roles and paper PG credentials.
- [ ] Production PostgreSQL migration and post-upgrade verification outcome.
- [ ] Published Appsmith revision, operational acceptance and release tag.
