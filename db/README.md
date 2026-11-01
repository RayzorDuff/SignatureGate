# SignatureGate database

## Canonical schema

`db/schema.sql` is the authoritative, self-contained database definition for SignatureGate.

It is a complete schema bootstrap, including tables, constraints, indexes, functions, triggers and views. Bootstrap a fresh database from this file, then apply the explicit deployment seeds below. The schema does not contain operational records or default terminology rows.

From the server where the SignatureGate PostgreSQL container runs:

```bash
sudo docker exec -i signaturegate-postgres \
  psql -X -v ON_ERROR_STOP=1 -U signaturegate \
  -d "${release_fresh_db:?Set this to a new empty database first}" \
  < db/schema.sql
```

Create and verify an empty target before setting `release_fresh_db`; neither existing `signaturegate` nor `signaturegate_test` is a fresh-bootstrap target. Use the reviewed forward migration process for existing data. A backup does not make schema replay an in-place upgrade.

## Current production upgrade

The canonical schema includes current cash-deposit and identity definitions. Production acceptance has been reported for some features, but the initial v1.2.0 live catalogs have been reviewed and targeted effective definitions have been dispositioned in the release review. Do not load `db/schema.sql` over the existing production database as an upgrade mechanism. Use [the release validation checklist](../releases/v1.2.0/PHASE_1_VALIDATION.md) to establish required forward upgrades.

Production deployment should use the reviewed database change procedure for the current release rather than treating the canonical bootstrap as an in-place upgrade.

## Verification

The verification scripts in `db/tests/verify_*.sql` are rollback-only integration checks. They create synthetic data inside a transaction and roll the transaction back when complete.

Run them against a disposable or dedicated test database, not against production:

```bash
sudo docker exec -i signaturegate-postgres \
  psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  < db/tests/verify_cash_deposit_management.sql
```

The cash-deposit verification covers:

- Cash on Hand selection and totals.
- Exclusion of ignored and already-deposited donations.
- Identified and anonymous cash donations.
- Deposit batch creation and item selection.
- Expected-total calculation and amount snapshots.
- Duplicate donation assignment protection.
- Preparer and verifier authorization.
- Confirmation amount matching.
- Confirmation and cancellation behavior.
- Immutability of confirmed batches and items.
- Audit entries.

Other verification scripts document and test focused parts of the canonical schema. They are retained as regression tests even though the historical migrations that originally introduced those objects are no longer part of the installation procedure.

## Database objects

The canonical schema includes the operational database used by:

- SignatureGate/Appsmith.
- SignatureGate n8n workflows.
- NocoDB, where applicable.
- The cash contribution review and deposit workflow.
- Document signing and agreement operations.
- Membership, contributor, person, organization, contact, practitioner, release, and audit functionality.

The accounting/ERP integration remains a separate system boundary. Cash-deposit confirmation records the operational deposit and its audit trail. Issue #18 queues a durable ERP synchronization row for confirmed batches while RootedOps remains authoritative for ERPNext accounting and bank reconciliation.

## Agreement template seed

A new installation may need an active agreement template if the canonical seed data does not contain the template required by the deployment:

```bash
sudo docker exec -it signaturegate-postgres psql \
  -U signaturegate -d "${release_fresh_db:?Select the reviewed new database}" -c "INSERT INTO agreement_templates (name, version, required_for, doc_url, active) \
VALUES ('Synthetic Participant Agreement', '1.0', ARRAY['membership','sacrament_release'], \
'DOCUMENSO_TEMPLATE_OR_PDF_URL', true) ON CONFLICT DO NOTHING;"
```

Use the deployment's actual Documenso template URL rather than the placeholder above.

## NocoDB

Create or connect the SignatureGate NocoDB base to the PostgreSQL database as appropriate for the deployment.

When NocoDB is running in the same Docker network:

```
Host: signaturegate-postgres
Port: 5432
DB: ${SIG_DB_NAME}
User: ${SIG_DB_USER}
Password: ${SIG_DB_PASSWORD}
```

## Appsmith

Create a PostgreSQL datasource in Appsmith using the same database connection.

When Appsmith is running in the same Docker network:

```
Host: signaturegate-postgres
Port: 5432
DB: ${SIG_DB_NAME}
User: ${SIG_DB_USER}
Password: ${SIG_DB_PASSWORD}
```

## Directory manager bootstrap

The canonical schema contains the directory-manager account and authorization model. When a new deployment requires an initial directory manager, select the intended account privately. Do not export a directory of names or contact information as release evidence.

Then bootstrap the intended account with the operator-only helper. All three values are required. This legacy bootstrap creates or uses an active membership and practitioner compatibility flags; it refuses a second manager bootstrap. It grants only Directory Manager, not Donations Reviewer. Existing deployments should use the manager-controlled Individual Profile role/account controls. Do not run bootstrap to repair a cash-page denial. Keep actual names/contact values and command output private. Supply shell-quoted values without embedding SQL quotes inside them:

```bash
sudo docker exec -i signaturegate-postgres psql \
  -X -v ON_ERROR_STOP=1 -v admin_email='ACTUAL_SIGN_IN_EMAIL' \
  -v admin_first_name='INITIAL_MANAGER_FIRST_NAME' \
  -v admin_last_name='INITIAL_MANAGER_LAST_NAME' \
  -U signaturegate -d signaturegate \
  < db/bootstrap_directory_manager.sql
```

## Audit log

The `audit_log` table provides permanent, append-only recording of significant system events.

Important fields include:

- `actor` — email or system identifier such as `n8n` or `documenso`.
- `action` — machine-readable event name.
- `entity_type` — logical entity affected.
- `entity_id` — identifier of the affected entity.
- `details` — JSON contextual metadata.
- `created_at` — server timestamp.

The audit log is not intended for debugging or analytics and should not be truncated or modified.

## Database development model

The database follows a canonical-schema model with a small deployment-migration surface for changes whose deployed state must be verified against the production catalog.

- Change the database definition through normal development and testing.
- Validate the resulting schema against a clean database.
- Regenerate `db/schema.sql` when the canonical database definition changes.
- Keep focused `db/tests/verify_*.sql` regression checks for important behavior.
- Do not add historical installation migrations for schema changes that are already incorporated into the canonical schema.
- Production upgrades that cannot safely be represented by replacing the schema bootstrap should be handled as explicit, separately reviewed deployment operations.

The current candidate forward migrations are listed below. Presence in this directory does not establish whether a migration is already applied or required. Phase 1 must compare effective definitions and produce the dependency-ordered manifest; do not run this list alphabetically.

- `db/migrations/agreement_type_administration.sql`
- `db/migrations/cash_deposit_batch_lifecycle.sql`
- `db/migrations/cash_deposit_batch_print.sql`
- `db/migrations/cash_deposit_batch_tally.sql`
- `db/migrations/cash_deposit_confirmation_correction.sql`
- `db/migrations/cash_deposit_erp_sync.sql`
- `db/migrations/cash_deposit_management.sql`
- `db/migrations/cash_donation_reconciliation_exceptions.sql`
- `db/migrations/cash_donation_reconciliation_revive.sql`
- `db/migrations/donation_financial_access.sql`
- `db/migrations/listmonk_contributor_email_support.sql`
- `db/migrations/listmonk_dual_capacity_contributor_email.sql`
- `db/migrations/member_agreement_reviewer_on_behalf.sql`
- `db/migrations/organization_contact_reassignment.sql`
- `db/migrations/party_identity_notes.sql`
- `db/migrations/person_role_self_assignment.sql`

Apply and verify each required migration against the test database before applying it to production. In particular, `person_role_self_assignment.sql` changes the Issue #19 role-administration boundary so a directory manager may assign or revoke their own operational roles, including `donations_reviewer`; it does not permit this function to grant or revoke `directory_manager`.


The historical migration chain has been removed from the active database installation surface. `db/migrations/` retains candidate forward deployment changes; required/applied state must be established from evidence. Future changes must update the canonical schema and supply a forward migration whenever existing deployments need one. Preserve release migration provenance through deployment verification.

## Agreement Type administration (v1.2.0)

`agreement_type_administration.sql` adds canonical document-reviewer authorization and atomic creation/audit. It requires canonical person accounts/roles, `agreement_types` and `audit_log`; membership is not required. Deploy this migration to test before pulling the new Agreement Templates page. Run `db/tests/verify_agreement_type_administration.sql` only on test/disposable databases. [Phase 2 progress](../releases/v1.2.0/PHASE_2_PROGRESS.md) includes exact commands, isolated test results and required live acceptance.


## Identity notes migration and reapplication (v1.2.0)

`party_identity_notes.sql` atomically installs canonical note APIs and initializes one historical import decision per membership. Original member notes remain intact. `member_identity_note_backfill` stores provenance/outcomes without copied note text; `backfill_member_identity_notes()` is an invoker-rights operator helper, revoked from PUBLIC. Reruns do not reimport changed/blank legacy sources or undo canonical clears. Previously audited canonical edits take precedence; privately review sources marked `preserved_edit` rather than automatically appending them. Keep historical member notes read-only after cutover and use the canonical Profile/Intake APIs for new notes.

Run `verify_party_identity_notes.sql` only on test/disposable databases. It rolls back synthetic fixtures and checks behavior, permissions, migration reapplication and failure atomicity. Follow [the notes validation sequence](../releases/v1.2.0/NOTES_VALIDATION_COMMANDS.md); production requires a restored-copy rehearsal first. Live PostgreSQL 16.13 SQL migration/reapplication and behavioral checks have passed on test; UI acceptance remains pending.


## Organization terminology seed

After fresh schema bootstrap, run `db/seeds/organization_terminology.sql`. It reconstructs the earlier 14 stable concepts and deployment defaults: `practitioner` displays as **Spiritual Practitioner**, while the distinct regulated `facilitator` concept stays inactive. This seed contains public presentation configuration only; no production identities, contacts or operational data. It inserts missing rows and preserves existing labels, active states and update attribution when rerun.

```bash
sudo docker exec -i signaturegate-postgres \
  psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  < db/seeds/organization_terminology.sql
sudo docker exec -i signaturegate-postgres \
  psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  < db/tests/verify_organization_terminology.sql
```

Use these test commands for validation; new production installations select their intended database only after setup review. The behavioral check expects the current deployment defaults; an intentionally customized installation may require separately reviewed expectations rather than resetting its labels.

**Phase 3 requirement:** update this seed and its checks with the accepted Member → Participant presentation changes, and verify every active UI/document surface agrees. This preparation seed retains the current `Member` label and separate inactive Participant concept. Stable tables/role keys and historical signed documents must not be renamed by a label seed. An existing deployment's accepted label change must use the audited terminology API; rerunning this seed deliberately does not overwrite it.

### Reason-aware cash reconciliation revival

After canonical application authorization is installed, apply `db/migrations/cash_donation_reconciliation_revive.sql` to test first. Revival requires Donations Reviewer authority and a nonblank new reason; both original exclusion and new rationale are audited atomically without editing the donation. Two-argument legacy calls fail closed. Run `db/tests/verify_cash_donation_reconciliation_revive.sql` on test/disposable databases only. The v1.2.0 test runner is `bash releases/v1.2.0/validate_cash_reconciliation_test.sh`; production still requires the ordered restored-copy upgrade rehearsal.

### Canonical provider donation review

`db/migrations/provider_donation_administration.sql` follows canonical application authorization and the existing identity/contact/mailing models. It preserves UUID-based legacy entry points while supporting reviewers without Participant capacity, protects duplicate/ambiguous/provider identities and audits attribution correction atomically. Explicit Participant/Contributor creation retains Directory Manager and both reviewer requirements. Apply/verify test with `bash releases/v1.2.0/validate_provider_review_test.sh`; do not replay the canonical schema over an existing database or treat this as an approved production manifest.

## Company contact people

`organization_contact_people` models company-to-individual relationships separately from organization email/phone/address ownership. The Company Profile controls link, archive and reactivate accessible existing identities with a reason and atomic audit. Multiple people and multiple companies are supported. Links grant no roles or capacity, copy no contacts or mailing consent, and do not attribute company donations to their representatives. Directory Manager or Donations Reviewer authority is required; archived companies cannot be changed. See [the increment validation guide](../releases/v1.2.0/DIRECTORY_REVIEW_VALIDATION.md) and `verify_company_contact_people.sql`.


## Participant display defaults and existing installation adoption

`db/seeds/organization_terminology.sql` now defaults the `member` compatibility concept to Participant/Participants; it still preserves installed label/activation/attribution overrides on repeat. Individual and Company remain identities; Participant and Contributor are capacities, and Facilitator/Spiritual Practitioner and reviewers characterize access. Internal keys remain stable.

For the authorized existing test installation use `env -u 'BASH_FUNC__sudo%%' bash releases/v1.2.0/validate_navigation_terminology_test.sh`. It asks privately for the intended Directory Manager account, calls `db/administration/adopt_participant_terminology.sql` through the audited API and runs rollback-only presentation invariants. It changes configuration, not schema or authority. Do not apply it to production until its reviewed release step. Missing/unauthorized accounts fail; bootstrap is not a repair mechanism.

### Atomic new-party Intake

`migrations/atomic_intake.sql` adds `application_submit_intake(actor_email,request_id,payload)` and owner-scoped `application_intake_status(actor_email,request_id)`. One database transaction creates identity, selected capacities, contact purposes, practitioner assignment, pending digital agreement, mailing queue entries and completion audit. A required UUID request key plus the canonical actor and salted SHA-256 payload fingerprint make committed retries return the same technical result without additional writes. Changed payloads or owners cannot reuse a key; current account and role permissions are rechecked even on replay.

The private receipt stores technical IDs and flags, not contact/name/form values or external responses. Functions run with the caller's privileges; no SECURITY DEFINER elevation or new role grants are introduced. The Appsmith database principal needs the existing helper permissions and private receipt-table access from its migration ownership or explicitly reviewed grants. Never grant the table to PUBLIC. Include owner/grant and concurrent-session verification in the protected restored-copy rehearsal.

No HTTP occurs inside the transaction. Signing remains after commit, against the pending agreement's existing ID; a lost signing response needs delivery reconciliation, not another identity or agreement. Paper remains blocked. `tests/verify_atomic_intake.sql` supplies synthetic rollback-only enrollment/replay/denial/fault tests. `releases/v1.2.0/validate_atomic_intake_test.sh` applies the migration twice and runs them only against `signaturegate_test`. This is not an authorized production upgrade manifest.

### Paper agreement evidence

The reviewed forward change `migrations/paper_agreement_upload.sql` adds owner-scoped upload receipts, pre-storage canonical staff/assignment/on-behalf checks, atomic paper agreement/evidence/audit completion and reasoned cancellation/review guards. It requires current canonical authorization/signers. `tests/verify_paper_agreement_upload.sql` uses synthetic rollback-only fixtures. For this release use the test-only runner and authenticated workflow sequence in [PAPER_AGREEMENT_VALIDATION.md](../releases/v1.2.0/PAPER_AGREEMENT_VALIDATION.md); do not replay all migrations in production. The private receipt table stores hashes/metadata, not file bytes; review invoker grants/backups.

`migrations/paper_evidence_storage.sql` follows the base paper upload migration. It adds a technical storage-provider column and replaces guarded APIs to accept confirmed private Drive file references or retained NocoDB paths. Existing receipt fingerprints, evidence and agreement IDs are preserved. The updated paper test runner applies both changes in order; `tests/verify_paper_evidence_storage.sql` covers provider conflicts and compatibility. See [the current Drive rollout](../releases/v1.2.0/GOOGLE_DRIVE_PAPER_VALIDATION.md).
