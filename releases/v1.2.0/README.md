# SignatureGate v1.2.0 release workspace

Status: **unreleased**. This is the first coordinated SignatureGate-Appsmith release. `VERSION` remains 1.1.0 until final release preparation.

- [Current status](STATUS.md)
- [Documentation consistency audit and remaining gaps](DOCUMENTATION_CONSISTENCY_AUDIT.md)
- [Restored-production upgrade rehearsal: 12 migrations / 12 tests PASS](evidence/november_10_restored_production_migration_rehearsal.md)
- [Canonical Appsmith export workflow](../../appsmith/EXPORT.md)
- [Production database and promotion steps](PRODUCTION_UPGRADE_AND_PROMOTION.md)
- [Issue release disposition](ISSUE_RELEASE_DISPOSITION.md)
- [Current unified Intake rollout and narrow validation](UNIFIED_INTAKE_VALIDATION.md)
- [Disposable PostgreSQL 16 contention check](POSTGRES_INTAKE_VALIDATION.md)
- [Current report definitions and focused validation](REPORTS_VALIDATION.md)
- [Current atomic Intake and terminology validation](ATOMIC_INTAKE_AND_TERMINOLOGY_VALIDATION.md)
- [Accepted presentation and browser recovery increment](PRESENTATION_AND_INTAKE_RECOVERY.md)
- [Release plan](RELEASE_PLAN.md)
- [Actual served Appsmith startup diagnostic](APP_STARTUP_DIAGNOSTIC.md)
- [Cold page startup and authority validation](PAGE_STARTUP_VALIDATION.md)
- [Navigation parser repair and focused runtime validation](NAVIGATION_RUNTIME_REPAIR.md)
- [Phase 1 audit and work queue](PHASE_1_AUDIT.md)
- [Phase 1 live validation requirements](PHASE_1_VALIDATION.md)
- [Linode validation commands, steps 2–5](LINODE_VALIDATION_COMMANDS.md)
- [Phase 2 implementation and test deployment](PHASE_2_PROGRESS.md)
- [Acceptance ledger](ACCEPTANCE_LEDGER.csv)
- [Environment and migration inventory](ENVIRONMENT_AND_MIGRATIONS.md)
- [Changelog coverage audit](CHANGELOG_AUDIT.md)
- [Read-only database collector](capture_database_inventory.sql)
- [Source inventory summary](evidence/source_summary.json)

**Current checkpoint (November 10, 2026):** The restored-production rehearsal is **PASS**: 12 selected SQL migrations applied on an isolated PostgreSQL 16.13 restore; 12/12 targeted rollback-only SQL tests passed; **zero compared structural differences** against `signaturegate_test`; all 35 original production-table row counts preserved. Native NocoDB paper upload and independent review have separate accepted test evidence. **Still open:** manifest dispositions and environment proofs, ownership/grants and production-role checks, final rollback exercise, integration pins, reviewed Appsmith master promotion and actual production publication. Production `signaturegate` has not been migrated. No v1.2.0 release/tag is final.

- [Sanitized live evidence review](LIVE_EVIDENCE_REVIEW.md): received catalog dispositions, confirmed software versions and open deployment gates.
- [Next identity-notes validation commands](NOTES_VALIDATION_COMMANDS.md): private effective-definition capture, test migration/reapplication and Profile/`Intake` checks.
- [Current migration candidates](CURRENT_MIGRATION_CANDIDATES.md): current checksums and prerequisite/recovery review; not a production execution manifest.

- [Permission repair and role matrix](PERMISSION_REVIEW.md).
- [Backend-first permission validation](PERMISSION_VALIDATION.md).

- [Test confidence and focused manual validation](TEST_CONFIDENCE_AND_MANUAL_VALIDATION.md)

- [Provider review increment and focused validation](PROVIDER_REVIEW_VALIDATION.md)

- [Current phase status](STATUS.md)
- [Company contacts and Cash Deposits access validation](DIRECTORY_REVIEW_VALIDATION.md)

- [Current access and workflow-feedback validation](INTAKE_PROGRESS_AND_ACCESS_VALIDATION.md): accepted operator results, read-only observation and two page openings.

- [Grouped navigation and Participant presentation validation](NAVIGATION_AND_PARTICIPANT_VALIDATION.md).

First Appsmith release notes: [draft in the application source](https://github.com/RayzorDuff/SignatureGate-Appsmith/blob/chatgpt_development/releases/first-release/RELEASE_NOTES.md). Final version/tag and production provenance remain gated.

- [Conditional upgrade-manifest review](UPGRADE_MANIFEST_REVIEW.md): checksum/order draft, undecided selections and required restore/dependency evidence.

- [Directory startup schedule rebuild](DIRECTORY_STARTUP_REBUILD.md): observed empty served schedules, failed Console repair, retired download and one native editor settings sequence.

- [Native object identities and current startup validation](NATIVE_OBJECT_IDENTITY_AND_STARTUP.md): accepted Directory table recovery, saved initializer correction and preservation of recreated objects.

Historical focused follow-up: [native startup and Participant agreement selection](NATIVE_STARTUP_AND_AGREEMENT_SELECTION.md). Deferred Intake and installed API validation have passed; do not repeat accepted work. See current [STATUS.md](STATUS.md) for outstanding release gates.

Navigation/selectors are operator-accepted. The earlier [protected no-email paper upload](PAPER_AGREEMENT_VALIDATION.md) plan is historical; see [accepted native paper evidence](evidence/november_10_paper_native_retry.md) for the completed NocoDB test and remaining source/deployment scope.

Historical paper-provider design: [private Drive storage and repaired file transport](GOOGLE_DRIVE_PAPER_VALIDATION.md). For v1.2.0 new-upload UI, NocoDB remains the default/only enabled provider; Drive implementation and existing links are retained but new Drive UI upload is deferred.

Historical Test2 follow-up (Test2 host retired): [canonical SQL fixture validation and console coordination](CANONICAL_REGRESSION_VALIDATION.md).

[Former Participant contact correction](FORMER_PARTICIPANT_CONTACT_VALIDATION.md): reproduced ownership defect, guarded forward change and one focused native check after coordinated Test2 deployment.
