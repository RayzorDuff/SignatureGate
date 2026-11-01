# Phase 1 validation: required evidence and pass conditions

**Source inventory complete; live deployment gate open. Phase 2 may proceed on the test-bound development branch.** These blockers are release work items, not exceptions to acceptance. Production promotion and upgrade approval remain blocked until the evidence below is reviewed.

The submitted PostgreSQL 16.13 catalog/service evidence has been reviewed privately, and the operator reports a successful test Agreement Type migration and form submission. See [LIVE_EVIDENCE_REVIEW.md](LIVE_EVIDENCE_REVIEW.md) for sanitized findings and remaining blockers; [NOTES_VALIDATION_COMMANDS.md](NOTES_VALIDATION_COMMANDS.md) gives the next exact sequence. Captures do not close the deployment gate.

Copy-and-paste server commands for steps 2–5 are in [LINODE_VALIDATION_COMMANDS.md](LINODE_VALIDATION_COMMANDS.md).

## 1. Capture both deployed database catalogs

Run from the server that hosts the existing PostgreSQL container:

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

The collector uses a read-only transaction and exports catalog definitions as hashes, without donor records, notes, bank details or credentials. Preserve command exit status, capture timestamp and the SignatureGate SHA used. Both JSON files must parse and identify the intended database. A file left by a failed command is not valid evidence.

## 2. Compare deployed catalogs with the canonical target

Initialize a **new disposable database**, using the same PostgreSQL major version and required extensions as production, from the exact candidate `db/schema.sql`. Run the same collector there to produce `database-canonical.json`. Do not bootstrap an existing test or production database over its records.

Compare relations/columns, function signatures and definition hashes, views, constraints, triggers, indexes, grants, RLS and extension versions across canonical, test and production. Investigate every missing or changed effective definition. Hash differences identify objects needing review; retrieve their actual definitions privately when needed to determine the forward change. Estimated row counts and timestamps are informational, not schema acceptance checks.

For each difference, record: object, environment, intended state, already-applied evidence, required migration/backfill, prerequisites, transaction strategy, verification and recovery. Check seed/configuration and historical backfill invariants with targeted read-only queries as well; the structural collector does not validate application data. Reconstruct a forward migration for required canonical changes missing from the retained migration directory. Do not replay overlapping migrations alphabetically.

**Pass condition:** all differences have an explicit disposition and the dependency-ordered upgrade manifest is written. Restored-production upgrade rehearsal remains mandatory in Phases 4–5; it does not block independent Phase 2 development.

## 3. Verify actual Appsmith environment and revisions

Record the installed Appsmith product version, editor Git branch/SHA, production published revision and how each was observed. The exported application/schema version is not the installed product version. Preserve unsynchronized editor work before pulling Git changes.

Through each application's actual PostgreSQL datasource, run the read-only query:

```sql
SELECT current_database(), current_setting('server_version');
```

The development application must return `signaturegate_test`; production must return `signaturegate`. Record the action/datasource identity and result. A datasource's display name does not prove its connection. Inspect installed navigation capabilities for Appsmith #4 before selecting the implementation.

## 4. Verify deployed integration dependencies

Record RootedOps revision/version, n8n version, active workflow IDs/revisions and route targets for deposit synchronization, bank-account lookup, signing/uploads, Givebutter and mailing. Record credential identity/target without secret values, test/production ERP mode, Listmonk list mappings and Documenso template/recipient mappings. Review compatibility with the candidate. Prior successful deposit comments remain acceptance evidence but cannot identify current deployed revisions.

**Pass condition:** no unknown target or incompatible dependency remains; any required integration change has an owner, implementation and deployment order in the release manifest.

## 5. Close the gate with a recorded review

Update `ENVIRONMENT_AND_MIGRATIONS.md`, the acceptance ledger and release plan with evidence locations, timestamps and exact SHAs. Phase 1 passes when every scoped criterion has a disposition, actual deployment differences are known, required forward changes are identified and the integration/environment map is verified. Functional and restored-copy acceptance continue in later phases.

The workspace has no live server/database/Appsmith session. The collector and isolated tests can be validated here; actual deployment evidence must come from the server and Appsmith runtime. See [Phase 2 progress](PHASE_2_PROGRESS.md) for work already implemented and its test deployment instructions.
