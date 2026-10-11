# v1.2.0 environment and migration inventory

Prepared October 11, 2026. This is a source inventory, not an approved production execution manifest. Every migration's test/production application state remains **unknown** until actual database inventories and deployment records are compared. Reported #17/#18 production success establishes that some relevant functionality is deployed; it does not identify all deployed definitions.

## Environment map

| Component | Source evidence | Required live evidence |
| --- | --- | --- |
| Appsmith development | `chatgpt_development` at `2746b2712f2bd91b508c1d58f7025ce444abef78`; 202 DB actions reference `signaturegate-postgres-test` | Actual connection returns `signaturegate_test`; installed Appsmith product version; runtime action registration and lint; published/editor revision |
| Appsmith production | `master` at `0b7739f2a4a20ef89808d2c76658682b3a1c39c4` | Published revision and production datasource identity; actual connection returns `signaturegate` |
| Additional Appsmith branch | `production_development` at `7c0a7e7cc48e5b522744bb0b934b636b9eb4857f` | Determine whether still used; preserve relevant changes during candidate comparison |
| Database test/production | Canonical schema and 15 retained forward migration files in SignatureGate | Effective functions, columns, views, constraints, triggers, grants, seed/config data, application records; restored-copy upgrade |
| n8n | 16 Appsmith API actions use `N8N`; checked-in Givebutter, Listmonk and Documenso workflows | Deployed workflow IDs/revisions, activation, credential target, processing mode, queue behavior |
| RootedOps/ERPNext | #18 comments report production posting/reconciliation; Appsmith Confirm/Retry each explicitly send `mode: "test"` in development | Deployed RootedOps revision, activated ERP sync/bank-account n8n routes, shared idempotency registry, bank-account choices and reconciliation status |
| NocoDB/uploads | Two actions bind `NocoDB danks.store`; one binds `NocoDB danks.store public` | Upload storage target/permissions, file URLs, evidence retrieval and retention |
| Documenso | Template listing, send and cancel API paths are inventoried in `evidence/actions.csv` | Template/envelope/recipient mappings, version compatibility, legal/board dependency inventory; executed documents unchanged |
| Listmonk | Contributor-aware worker/unsubscribe exports and two mailing migrations | Member/contributor list mapping and deployed queue worker; opt-in/out propagation |
| MushroomProcess | Available-product/mark-shipped/mark-unshipped PGSQL routes | Correct inventory service/database, scoped storage and operational compatibility |

Datasource Git files contain descriptors, not live connection definitions. No credential values are recorded in this inventory. `applicationVersion`, `clientSchemaVersion` and `serverSchemaVersion` are artifact schema fields; they do not establish the installed Appsmith version.

## Collect read-only database evidence

The collector reads catalogs in `BEGIN READ ONLY`, exports definition hashes and metadata, and rolls back. It does not emit people, donation amounts, contacts, notes, bank identifiers or credentials. It has not been executed against PostgreSQL in this workspace; use the existing server PostgreSQL tooling. Row counts are catalog estimates, not historical-data verification.

From the existing Linode checkout:

```bash
cd ~/signaturegate
git pull --ff-only

mkdir -p "$HOME/signaturegate-release-evidence/v1.2.0"

sudo docker exec -i signaturegate-postgres \
  psql -X -qAt -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  < releases/v1.2.0/capture_database_inventory.sql \
  > "$HOME/signaturegate-release-evidence/v1.2.0/database-test.json"

sudo docker exec -i signaturegate-postgres \
  psql -X -qAt -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate \
  < releases/v1.2.0/capture_database_inventory.sql \
  > "$HOME/signaturegate-release-evidence/v1.2.0/database-production.json"
```

Confirm both files parse as JSON and identify their expected database. Keep collected live evidence outside the public repository. Compare catalog entries against an isolated canonical bootstrap on the same PostgreSQL major version, then obtain targeted `pg_get_functiondef` / view definitions for differences. Definition hashes reveal differences, not whether one version is correct; compare signatures and effective behavior as well.

Also record the installed Appsmith version, deployed/published Git revision, n8n/RootedOps revisions and activated workflow versions. Verify `SELECT current_database()` through the actual Appsmith datasource separately; a server-side psql connection does not prove Appsmith is using it. Seed/configuration values require a reviewed targeted inventory after the structural comparison. Do not copy test configuration into production.

## Source dependency inventory

Checksums, defined objects, and transaction markers for every retained file are in [`evidence/migrations.csv`](evidence/migrations.csv). Entries are candidate dependencies, not an instruction to replay all files. Canonical identity/contact/role objects must already exist or receive a reconstructed forward upgrade before dependent files run.

| Candidate file in `db/migrations/` | Prerequisite / ordering constraint | Verification in `db/tests/` |
| --- | --- | --- |
| `cash_deposit_management.sql` | Current donations/contributors and legacy member actor model; base deposit objects | `verify_cash_deposit_management.sql` |
| `cash_deposit_batch_lifecycle.sql` | Deposit base; replaces base item/confirm/cancel functions and cash-on-hand selection | `verify_cash_deposit_batch_lifecycle.sql` |
| `cash_deposit_batch_tally.sql` | Base + prepared/removal lifecycle columns; contributor profile projection | `verify_cash_deposit_batch_tally.sql` |
| `cash_deposit_batch_print.sql` | Base + lifecycle columns; contributor profile projection | `verify_cash_deposit_batch_print.sql` |
| `cash_deposit_erp_sync.sql` | Deposit confirmation/lifecycle and existing durable batch identity | `verify_cash_deposit_erp_sync.sql` |
| `cash_deposit_confirmation_correction.sql` | Base trigger and ERP sync state; must follow earlier versions of the batch-mutation trigger | `verify_cash_deposit_confirmation_correction.sql` |
| `cash_donation_reconciliation_exceptions.sql` | Base/lifecycle; final cash-on-hand definition excludes reconciliation exceptions | `verify_cash_donation_reconciliation_exceptions.sql` |
| `cash_donation_reconciliation_revive.sql` | Reconciliation exclusions and existing reviewer authorization | `verify_cash_donation_reconciliation_exceptions.sql` plus explicit revival/reason runtime cases |
| `donation_financial_access.sql` | Legacy member/facilitator reviewer flags; canonical-role compatibility remains a release gap | Canonical/legacy role matrix and scoped financial acceptance |
| `person_role_self_assignment.sql` | Canonical person roles, account/role helpers, directory-manager boundary | `verify_person_roles.sql` |
| `organization_contact_reassignment.sql` | Canonical organization contributor/contact identity and ownership synchronization | `verify_organization_contact_reassignment.sql` |
| `member_agreement_reviewer_on_behalf.sql` | Canonical practitioner signer, member agreement and reviewer helpers | `verify_member_agreement_reviewer_on_behalf.sql` |
| `party_identity_notes.sql` | Canonical people/organizations, member-person links, directory visibility and role helpers | `verify_party_identity_notes.sql` checks existence only; add behavior/backfill/rerun coverage |
| `listmonk_contributor_email_support.sql` | Existing Listmonk queue and contributor email schema | `verify_listmonk_contributor_email_support.sql` |
| `listmonk_dual_capacity_contributor_email.sql` | Contributor Listmonk support and its wrapper/helper APIs | `verify_listmonk_contributor_email_support.sql` plus independent dual-capacity choices |

Alphabetical execution is unsafe: `cash_deposit_management.sql` would run after `cash_deposit_batch_lifecycle.sql` and `cash_deposit_confirmation_correction.sql`, replacing refined definitions. `cash_on_hand_donations` is defined by three files; its final exception-aware definition must survive. The effective definition, not a filename/application timestamp alone, determines whether a step is needed.

Four retained files have no explicit `BEGIN`/`COMMIT`: notes, reviewer-on-behalf agreements, donation financial access, and reconciliation revival. Plan transaction handling explicitly. In particular, the notes migration has multiple schema/backfill/API statements and needs all-or-nothing upgrade behavior and safe changed-source reapplication tests. Do not apply a blanket transaction wrapper to the whole mixed migration chain.

## Upgrade manifest still required

The final manifest must record for each necessary step: live preconditions, prerequisite objects, checksum, transactional execution, expected effective definitions, backfill counts/invariants, test evidence, production-safe verification and recovery. A v1.1.0 database may be missing canonical identities, contact ownership and contributor backfills whose historical migrations are no longer in `db/migrations/`.

Before deployment, reconstruct missing forward upgrades from the actual production baseline. Test on a restored production copy and preserve historical donation/provider IDs, contacts, membership/contributor links, agreement references, audit records, confirmed batch composition and ERP source identities. `db/schema.sql` is a fresh bootstrap, not an in-place production upgrade. No migration application or production-ready ordering is certified by this Phase 1 source audit.
