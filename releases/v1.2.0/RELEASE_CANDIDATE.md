# v1.2.0 release candidate preparation

Updated November 2, 2026. **Candidate preparation only; not approved for production.**

## Scope freeze

ERPNext deposit accounting synchronization (#18) and Google Drive paper storage (#34) are owner-approved, deferred, nonblocking work. Preserve their implementations and validation runbooks; leave the optional integrations disabled. No ERP synchronization, real bank transaction, production signing or production storage action is authorized by this candidate.

Required workflows are canonical Directory/Profiles/Reports, consecutive Participant Intake, reviewer contact correction, Contributor/cash handling, local deposit preparation/confirmation, and local/NocoDB paper agreement creation/review. Preserve accepted results in [TEST2_UI_ACCEPTANCE.md](TEST2_UI_ACCEPTANCE.md). Do not repeat full suites or add a browser framework.

## Source under review

| Component | Candidate source | State |
| --- | --- | --- |
| SignatureGate backend | main at ba7eec08120e82bb97b5034fe6a5d816e2a51705, including PR #33 | Existing accepted backend baseline; no new database migration needed for the local deposit UI correction |
| Appsmith development | chatgpt_development at 666c9bcaefa6bf22c5683f7819bdbbc55e114482, including PR #8 | Core browser PASS evidence preserved |
| Local deposit correction | [Appsmith PR #9](https://github.com/RayzorDuff/SignatureGate-Appsmith/pull/9), head 4670bbeca08421bc11ac2638c4fa4ee4e83fbacc | Installed only in development; local preparation/confirmation and printable record passed; review/merge pending |
| Acceptance and release preparation | [SignatureGate PR #35](https://github.com/RayzorDuff/SignatureGate/pull/35) | Sanitized evidence and scope disposition; review/merge pending |
| Optional dependencies | ERP and Drive remain excluded | Do not require their external acceptance or an ERP-only release pin for this scope |

After approved PRs are merged, freeze exact backend and production-bound Appsmith revisions. Do not merge development wholesale into production or substitute a development VERSION for a released dependency pin.

## Required database review

The existing [upgrade manifest](UPGRADE_MANIFEST_DRAFT.json) remains non-executable with 24 undecided entries and nine unverified environment proofs. Select only missing forward changes against the actual installed baseline. The following are requirement groups, not permission to execute every file:

- Canonical identity, Contributor contacts, company contact reassignment, identity notes and former-Participant contact reassignment.
- Agreement Type administration, reviewer-on-behalf authorization and canonical application authorization.
- Cash lifecycle, tally/print, correction guards, reconciliation exclusions and existing authorization compatibility.
- Central terminology and the separately approved Participant presentation configuration.
- Atomic Intake and durable paper-upload/evidence-storage contracts.
- Provider/mailing compatibility only where required by the retained application contracts; deferred integrations must not activate workers or contact external services.

Use the manifest's dependency order and source checksums after each selected/skipped decision has supporting private catalog/data evidence. Never bootstrap over an existing database. No additional schema is proposed for entering the local deposit destination.

Review production account ownership, effective grants and data invariants privately. The narrowed test connection-policy observation is not proof of production isolation and does not justify broad access-control restructuring.

## Known limitations and remaining acceptance

- Local/NocoDB paper upload has an unresolved browser receipt. One synthetic dispatch did not produce a committed agreement; creation, retrieval, reviewer transition and evidence/audit acceptance remain required.
- Digital signing is not certified by this checkpoint. Do not enable a release-used digital path without its separate isolated acceptance.
- ERP accounting synchronization and Drive storage are unavailable in this release scope and must be presented as deferred, not failed core workflows.
- Wider provider address canonicalization, navigation accessibility/mobile completion and other issue-wide residual work remain tracked; do not introduce general redesign or unrelated functionality.
- Source and deployed development configuration must be reconciled before packaging. Private destination/credential bindings must never enter the public export or evidence.

## Rollback and recovery conditions

Before migration approval, verify a restorable backup and rehearse the exact selected upgrade on a protected restored copy with workers and destinations isolated. Verify historical identities, contacts, contributions, agreements and audits, plus recovery at each incompatible boundary.

Pin the prior compatible Appsmith revision and private datasource/workflow configuration alongside the candidate. An application/configuration rollback is valid only when the reviewed schema remains backward compatible. For incompatible or committed data changes, use the separately reviewed recovery plan and verified backup; do not improvise a down migration or restore over active shared services.

Record the recovery decision point and owner approval privately. Reconcile any committed operational writes before resuming workers. Preserve audit/history and avoid re-sending receipts, signing requests, stored files or deposit events.

## Production approval checklist

1. Close core local agreement/paper acceptance and retain the accepted local deposit evidence; review/merge the focused PRs.
2. Resolve all manifest dispositions and release-used dependency/configuration pins; verify restoration, rehearsal, history and recovery.
3. Review the production-bound Appsmith delta, exact exported source and private configuration. Keep optional ERP/Drive paths disabled.
4. Reconcile changelog/release notes, VERSION, export checksum and final immutable source pins.
5. Obtain explicit owner approval for production migration, publication and release/tag actions.

No production migration, datasource promotion, publication, VERSION bump or tag has occurred.
