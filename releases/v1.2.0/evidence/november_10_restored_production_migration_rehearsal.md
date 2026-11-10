# Restored-production v1.2.0 migration rehearsal — November 10, 2026 (UTC)

**Result: PASS for the scoped, isolated structural upgrade and 12 targeted SQL verification scripts. Production promotion remains NOT APPROVED.**

## Provenance and isolation

Operator-supplied terminal transcripts from November 10, 2026. Backend checkout: `main` at `6dcaebe0ac13d5b81023bbaa32b93fbe10b09df1`; repository `VERSION` remained `1.1.0`. The live database `signaturegate` was **read only for inventories/backups** and was not migrated. Development comparison target: `signaturegate_test`. Rehearsal database: `signaturegate_rehearsal` in disposable container `signaturegate-v120-restore`, based on `postgres:16` (PostgreSQL 16.13), with Docker network mode `none`. Development Appsmith and production/master datasource settings were not changed as part of this exercise.

A custom-format production backup was created at UTC `20261110T045802Z`, size approximately 806 KB, with 558 `pg_restore --list` archive entries. The SHA-256 check reported `OK`. Restore completed with `pg_restore --no-owner --no-acl --single-transaction --exit-on-error`. Global role definitions were separately captured with `pg_dumpall --globals-only --no-role-passwords`, but **not restored or proven equivalent**. Private evidence lives under `~/signaturegate/private-v120-evidence/`; backup and checksum live outside the repository under `~/signaturegate-release-backups/v1.2.0/`. Do not commit those private artifacts.

Initial restored public schema: 35 tables and 141 routines. The structural inventories of production and restored production agreed on all object-name sets compared. Before migrations, production had 43 relations, 576 columns, 141 functions, 8 views, 179 constraints, 51 triggers, 144 indexes and 0 row policies; development had 49, 616, 173, 9, 203, 52, 152 and 0, respectively.

## Migration sequence rehearsed (12/12 successful)

Each SQL file below was submitted through `psql -X -v ON_ERROR_STOP=1` to the isolated restored database. Terminal output reported PASS for each file in order.

| Order | Manifest ID | Migration file | Result |
| --- | --- | --- | --- |
| 1 | `identity_notes` | `db/migrations/party_identity_notes.sql` | PASS |
| 2 | `agreement_types` | `db/migrations/agreement_type_administration.sql` | PASS |
| 3 | `reviewer_agreements` | `db/migrations/member_agreement_reviewer_on_behalf.sql` | PASS |
| 4 | `organization_contacts` | `db/migrations/organization_contact_reassignment.sql` | PASS |
| 5 | `application_authorization` | `db/migrations/application_authorization.sql` | PASS |
| 6 | `cash_revival` | `db/migrations/cash_donation_reconciliation_revive.sql` | PASS |
| 7 | `provider_review` | `db/migrations/provider_donation_administration.sql` | PASS |
| 8 | `company_contacts` | `db/migrations/company_contact_people.sql` | PASS |
| 9 | `person_contact_reassignment` | `db/migrations/person_contact_reassignment.sql` | PASS |
| 10 | `atomic_intake` | `db/migrations/atomic_intake.sql` | PASS |
| 11 | `paper_agreement_upload` | `db/migrations/paper_agreement_upload.sql` | PASS |
| 12 | `paper_evidence_storage` | `db/migrations/paper_evidence_storage.sql` | PASS |

A read-only prerequisite check before application authorization confirmed the required cash, mailing, role, account and agreement objects, including the actual `listmonk_sync_queue` relation. An installation smoke check after the final migration confirmed six Intake/paper objects/functions and the paper-upload `storage_provider text` column.

The remaining 12 manifest entries were **not executed in this rehearsal**; their selected/skipped dispositions are still subject to actual effective-definition, prerequisite and production-configuration review. In particular, `participant_labels` is an audited configuration operation requiring an authorized account, not a generic schema migration.

## Structural parity and history

After the 12 migrations, a fresh `capture_database_inventory.sql` report for rehearsal compared to `signaturegate_test` showed **zero differences** across the compared object identities and selected definitions/attributes:

| Category | Rehearsal | Development | Reported differences |
| --- | ---: | ---: | ---: |
| Relations | 49 | 49 | 0 |
| Columns | 616 | 616 | 0 |
| Functions | 173 | 173 | 0 |
| Views | 9 | 9 | 0 |
| Constraints | 203 | 203 | 0 |
| Triggers | 52 | 52 | 0 |
| Indexes | 152 | 152 | 0 |
| Row policies | 0 | 0 | 0 |

All **35 original production table row counts** matched rehearsal after schema upgrade. This is row-count preservation, **not** a comparison of every record's contents, live database writes after backup, role-specific behavior, or external integration effects. Newly created migration tables are outside that historical-table count.

The 16 initially differing preexisting function definitions were all mapped to migration source files. Their return types, languages, `SECURITY DEFINER` settings, configuration hashes and grants matched between the initial production and development inventories, but their bodies differed. This is supporting interface evidence, not proof of permission behavior.

## Targeted verification (12/12 PASS)

The operator ran each checked-in script against isolated rehearsal with `psql -X -v ON_ERROR_STOP=1`. Every script returned PASS; each uses synthetic fixtures in a rollback-only transaction:

1. `db/tests/verify_party_identity_notes.sql`
2. `db/tests/verify_agreement_type_administration.sql`
3. `db/tests/verify_member_agreement_reviewer_on_behalf.sql`
4. `db/tests/verify_organization_contact_reassignment.sql`
5. `db/tests/verify_application_authorization.sql`
6. `db/tests/verify_cash_donation_reconciliation_revive.sql`
7. `db/tests/verify_provider_donation_administration.sql`
8. `db/tests/verify_company_contact_people.sql`
9. `db/tests/verify_person_contact_reassignment.sql`
10. `db/tests/verify_atomic_intake.sql`
11. `db/tests/verify_paper_agreement_upload.sql`
12. `db/tests/verify_paper_evidence_storage.sql`

After the verification suite, a new row-count check again reported **PASS for all 35 original production tables**. Private execution logs were saved in `private-v120-evidence/verification/`. The signed paper upload through the native Appsmith/n8n UI is separately recorded; these SQL tests do not call NocoDB, Drive, mail, ERP or production signing services.

## Remaining promotion gates — not closed by this evidence

- Review every one of the 24 draft manifest entries with an evidenced selected/skipped disposition and a reviewed, reproducible final ordering. The existing `UPGRADE_MANIFEST_DRAFT.json` remains `draft_non_executable`; do not treat this report as an executable manifest.
- Verify effective definitions, historical data-level invariants, ownership, grants and actual production app-role access. Restore used `--no-owner --no-acl`; the 536-byte global-roles output was saved but not restored in this rehearsal.
- Rehearse the **final** selected production migration plan against a fresh protected restore, including migration checksums, application compatibility, isolated writers/consumers/destinations and recovery/rollback. Confirm dependency versions of n8n workflows and deployed RootedOps.
- Prepare and review the production-bound Appsmith source/export and actual datasource identities/modes, preserve master-only changes and production ERP functionality, and verify production publishing at cutover. Do not repoint `chatgpt_development` or its shared test datasource.
- Only after production acceptance: increment `VERSION` to `1.2.0`, reconcile the changelog/release notes, and tag/publish the release.

**Evidence type:** operator-reported command transcripts in the release conversation; no private database backup, row data, or execution logs have been committed. No changes to production database or published production Appsmith are asserted.
