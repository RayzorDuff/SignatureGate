# SignatureGate database

## Canonical schema

`db/schema.sql` is the authoritative, self-contained database definition for SignatureGate.

It is a complete schema bootstrap, including tables, constraints, indexes, functions, triggers, views, and the current seed data represented by the repository. A new SignatureGate database should be initialized from this file alone.

From the server where the SignatureGate PostgreSQL container runs:

```bash
sudo docker exec -i signaturegate-postgres \
  psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate \
  < db/schema.sql
```

Before applying it to a database that contains data, take an appropriate backup. `schema.sql` is intended as a bootstrap definition, not as an in-place upgrade script for an existing production database.

## Current production upgrade

The canonical schema includes the current cash-deposit management definition. The production database has not yet been changed by this branch; do not load `db/schema.sql` over the existing production database as an upgrade mechanism.

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

The accounting/ERP integration remains a separate system boundary. Cash-deposit confirmation records the operational deposit and its audit trail; ERPNext synchronization is handled by the accounting integration.

## Agreement template seed

A new installation may need an active agreement template if the canonical seed data does not contain the template required by the deployment:

```bash
sudo docker exec -it signaturegate-postgres psql \
  -U signaturegate -d signaturegate -c "INSERT INTO agreement_templates (name, version, required_for, doc_url, active) \
VALUES ('Member Acknowledgment & Liability Release', '2025-12-01', ARRAY['membership','sacrament_release'], \
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

The canonical schema contains the directory-manager account and authorization model. When a new deployment requires an initial directory manager, review the available application accounts first:

```bash
sudo docker exec signaturegate-postgres psql \
  -U signaturegate -d signaturegate -c \
  "SELECT p.person_id, p.display_name, a.email
     FROM public.person_app_accounts a
     JOIN public.people p USING (person_id)
     ORDER BY a.email;"
```

Then bootstrap the intended account with the operator-only helper:

```bash
sudo docker exec -i signaturegate-postgres psql \
  -v ON_ERROR_STOP=1 -v admin_email='ACTUAL_SIGN_IN_EMAIL' \
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

The database follows a canonical-schema model with a small deployment-migration surface for changes that are still pending in production.

- Change the database definition through normal development and testing.
- Validate the resulting schema against a clean database.
- Regenerate `db/schema.sql` when the canonical database definition changes.
- Keep focused `db/tests/verify_*.sql` regression checks for important behavior.
- Do not add historical installation migrations for schema changes that are already incorporated into the canonical schema.
- Production upgrades that cannot safely be represented by replacing the schema bootstrap should be handled as explicit, separately reviewed deployment operations.

The current pending production migrations are:

- `db/migrations/cash_deposit_management.sql`
- `db/migrations/cash_deposit_batch_lifecycle.sql`
- `db/migrations/cash_deposit_batch_tally.sql`
- `db/migrations/person_role_self_assignment.sql
    - db/migrations/cash_deposit_batch_print.sql`

Apply and verify each pending migration against the test database before applying it to production. In particular, `person_role_self_assignment.sql` changes the Issue #19 role-administration boundary so a directory manager may assign or revoke their own operational roles, including `donations_reviewer`; it does not permit this function to grant or revoke `directory_manager`.


The historical migration chain has been removed from the active database installation surface. `db/migrations/` contains only the forward deployment migration still required by current production; once that migration has been deployed and verified, future schema changes should normally be consolidated directly into `db/schema.sql` rather than accumulated as historical migrations.
