# v1.2.0 release candidate preparation

Updated November 9, 2026. **Candidate preparation only; not approved for production.**

**November 10 superseding checkpoint:** The restored-production migration rehearsal and 12 rollback-only SQL tests **passed**, the compared schema now matches development and 35 historical table counts were preserved; see [scoped evidence](evidence/november_10_restored_production_migration_rehearsal.md). Native NocoDB paper upload/review acceptance is also [recorded](evidence/november_10_paper_native_retry.md). The Appsmith export preparation was unified under shared Action/manual tooling in merged SignatureGate PR #40; see [export procedure](../../appsmith/EXPORT.md). The older source SHAs and work items in this document are historical preparation snapshots, **not release pins or instructions to repeat accepted tests**. Production roles/grants, final manifest, actual deployment, integration pins and rollback remain open. This is still **not** approval for production promotion.

## Scope freeze

Additional end-to-end ERPNext deposit synchronization (#18) and Google Drive storage (#34) acceptance testing is deferred and nonblocking. Existing integration functionality and validation runbooks must remain intact. ERP capabilities remain enabled. The November 9 owner direction temporarily disables new Google Drive uploads in the UI and selects NocoDB by default; preserve Drive implementation and existing document access. No real bank transaction, production signing or production storage action is authorized by this candidate.

Required workflows are canonical Directory/Profiles/Reports, consecutive Participant Intake, reviewer contact correction, Contributor/cash handling, local deposit preparation/confirmation, and local/NocoDB paper agreement creation/review. Preserve accepted results in [TEST2_UI_ACCEPTANCE.md](TEST2_UI_ACCEPTANCE.md). Do not repeat full suites or add a browser framework.

## Source under review

| Component | Candidate source | State |
| --- | --- | --- |
| SignatureGate backend | main at ba7eec08120e82bb97b5034fe6a5d816e2a51705, including PR #33 | Existing accepted backend baseline; accepted evidence retained; PR #9 capability reductions rejected |
| Appsmith development | chatgpt_development at 666c9bcaefa6bf22c5683f7819bdbbc55e114482, including PR #8 | Core browser PASS evidence preserved |
| Rejected deposit change | [Appsmith PR #9](https://github.com/RayzorDuff/SignatureGate-Appsmith/pull/9) | Closed without merging; failed Development checks. Excluded from the candidate. The retained development source preserves all existing ERP capabilities and PR #8; native collection compilation, bindings and focused cash regressions pass. The former disposable deployment is retired, so its editor does not require restoration. |
| Acceptance and release preparation | [SignatureGate PR #35](https://github.com/RayzorDuff/SignatureGate/pull/35) | Merged in main at 9556662677f2567fa71de73c3444d74c5d6fba65; accepted results retained |
| Existing integrations | ERP functionality retained; Drive backend and existing links retained, new-upload UI temporarily disabled | Additional end-to-end acceptance is deferred; preserve existing dependency and configuration contracts |

After approved PRs are merged, freeze exact backend and production-bound Appsmith revisions. Do not merge development wholesale into production or substitute a development VERSION for a released dependency pin.

## Required database review

The existing [upgrade manifest](UPGRADE_MANIFEST_DRAFT.json) remains non-executable with 24 undecided entries and nine unverified environment proofs. Select only missing forward changes against the actual installed baseline. The following are requirement groups, not permission to execute every file:

- Canonical identity, Contributor contacts, company contact reassignment, identity notes and former-Participant contact reassignment.
- Agreement Type administration, reviewer-on-behalf authorization and canonical application authorization.
- Cash lifecycle, tally/print, correction guards, reconciliation exclusions and existing authorization compatibility.
- Central terminology and the separately approved Participant presentation configuration.
- Atomic Intake and durable paper-upload/evidence-storage contracts.
- Provider/mailing compatibility only where required by the retained application contracts; isolated testing must not contact production; preserve existing integration contracts.

Use the manifest's dependency order and source checksums after each selected/skipped decision has supporting private catalog/data evidence. Never bootstrap over an existing database. No deposit schema or architecture redesign is authorized.

Review production account ownership, effective grants and data invariants privately. The narrowed test connection-policy observation is not proof of production isolation and does not justify broad access-control restructuring.

## Known limitations and remaining acceptance

- Local/NocoDB paper upload failed before durable reservation (#36). One synthetic dispatch did not produce a reservation or committed agreement; creation, retrieval, reviewer transition and evidence/audit acceptance remain required.
- Digital signing is not certified by this checkpoint. Do not enable a release-used digital path without its separate isolated acceptance.
- Additional ERP synchronization and Drive storage testing is deferred. ERP functionality remains intact. Drive implementation and existing evidence access remain; new Drive upload selection is temporarily disabled by the November 9 owner instruction.
- Wider provider address canonicalization, navigation accessibility/mobile completion and other issue-wide residual work remain tracked; do not introduce general redesign or unrelated functionality.
- Source and deployed development configuration must be reconciled before packaging. Private destination/credential bindings must never enter the public export or evidence.

Work can continue without the former acceptance deployment. November 8 local checks passed the existing paper controller, workflow and database regressions plus one connected actual-source rehearsal with synthetic in-memory storage. No product source change was required. Preserve the distinction between these results and real Appsmith/n8n/NocoDB transport, protected storage retrieval and reviewer acceptance. The historical #36 failure remains unresolved; its runtime cause cannot be established from passing local checks. No replacement host, general storage redesign or new reusable test framework is required by this checkpoint.

Do not replay the historical uncertain upload. If a prior checkpoint is restored, perform owner-scoped receipt inspection and reasoned cancellation/tombstoning before a separate attempt. The retired deployment is not proof that a restored request was cancelled.

## Rollback and recovery conditions

Before migration approval, verify a restorable backup and rehearse the exact selected upgrade on a protected restored copy with workers and destinations isolated. Verify historical identities, contacts, contributions, agreements and audits, plus recovery at each incompatible boundary.

Pin the prior compatible Appsmith revision and private datasource/workflow configuration alongside the candidate. An application/configuration rollback is valid only when the reviewed schema remains backward compatible. For incompatible or committed data changes, use the separately reviewed recovery plan and verified backup; do not improvise a down migration or restore over active shared services.

Record the recovery decision point and owner approval privately. Reconcile any committed operational writes before resuming workers. Preserve audit/history and avoid re-sending receipts, signing requests, stored files or deposit events.

## Production approval checklist

1. Close core local agreement/paper acceptance and retain the accepted local deposit evidence; review/merge the focused PRs.
2. Resolve all manifest dispositions and release-used dependency/configuration pins; verify restoration, rehearsal, history and recovery.
3. Review the production-bound Appsmith delta, exact exported source and private configuration. Preserve existing ERP/Drive functionality and PR #8. Use the retained development source; no retired-editor restoration is required.
4. Reconcile changelog/release notes, VERSION, export checksum and final immutable source pins.
5. Obtain explicit owner approval for production migration, publication and release/tag actions.

No production migration, datasource promotion, publication, VERSION bump or tag has occurred.

## November 9 preparation update

The owner’s screenshots and SQL transcript are reconciled in [current status](STATUS.md). Verify/Reassign is owner-accepted. Paper remains unresolved; changing Participant does not bypass the account-owned checkpoint. The terminology transcript contains one error, so do not call it an all-pass run. The saved location workflow and NocoDB/Intake UI have targeted source corrections awaiting review/deployment. Follow [the production runbook](PRODUCTION_UPGRADE_AND_PROMOTION.md); preparation does not authorize production changes.

Source correction: [Appsmith PR #10](https://github.com/RayzorDuff/SignatureGate-Appsmith/pull/10), head `322816a92aec2f9309b7d39a9c0099a841156ce5`, targets development only. [Sanitized preparation evidence](evidence/november_9_preparation.json) distinguishes local checks, owner acceptance and unverified production gates.
