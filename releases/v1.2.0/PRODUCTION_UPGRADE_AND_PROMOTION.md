# Production database update and Appsmith promotion

November 9, 2026. Reviewable preparation, **not an approved execution manifest**. Test2 was deleted. Continue development on the existing host using the separate `signaturegate_test` database and development branch; do not change `signaturegate` or published master during acceptance.

## Minimum remaining release work

1. Resolve #36's saved request, then complete one synthetic NocoDB upload, retrieve the stored document as the intended reviewer, approve with an authorized independent Document Reviewer and verify agreement/evidence/audit/receipt records. Intake uses Later followed by Participant Functions; direct atomic Intake paper upload is not implemented.
2. Review/pull the NocoDB default and temporarily disabled new Drive UI correction into development. Install the reviewed inventory Code correction in the intended test workflow and check one assigned scope plus an empty scope. Keep bank selection, refresh lookup, confirm-triggered ERP synchronization, retry and dynamic status intact.
3. Inventory the actual production baseline, choose missing forward changes, restore/rehearse with workers/destinations isolated, and pin compatible deployed dependencies. Historical or fresh-schema tests cannot replace this step.
4. Review the production-bound Appsmith source/environment delta, generate its export, pass required checks, then obtain production promotion approval. Final version/tag/publish follows approval and successful cutover.

Already accepted browser workflows do not need wholesale repetition. A new ERP synchronization end-to-end test and Google Drive storage acceptance are not release gates. Drive backend and historical links remain; only new Drive uploads in this UI are temporarily disabled by explicit owner direction.

## 1. Reconcile the operator SQL transcript

The contact reassignment migration completed on `signaturegate_test`. The test loop continued after one terminology-default assertion error. Do not record that loop as an all-pass run. The seed deliberately preserves organization-specific labels. First inspect configuration privately:

```bash
sudo docker exec -i signaturegate-postgres psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test <<'SQL'
BEGIN READ ONLY;
SELECT concept_key,singular_label,plural_label,is_active
FROM public.issue20_organization_terminology()
WHERE concept_key IN ('member','practitioner','facilitator') ORDER BY concept_key;
COMMIT;
SQL
```

After reviewing/pulling the corrected test, run **only** this rollback-only check. Missing concepts remain a failure; investigate required seeds/migrations instead of resetting organization overrides.

```bash
sudo docker exec -i signaturegate-postgres psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test < db/tests/verify_organization_terminology.sql
```

Stop on nonzero status. No need to repeat the entire `db/tests/*.sql` loop.

## 2. Recover the existing paper request before retrying

In the same signed-in account, use **Check saved paper upload**. Changing the selected Participant does not change the saved account-owned request. Retain its request/member/practitioner IDs from the saved checkpoint privately; never post file bytes, contacts, credentials or execution payloads in an issue.

Verify that the actual Appsmith receipt query and both n8n Postgres nodes use `signaturegate_test`, and that the upload endpoint is the intended authenticated paper workflow. A host name or a Git datasource descriptor alone does not prove this. Run the database identity probe below through the actual datasource. Inspect the matching workflow execution's first failing node privately: authentication/validation, reservation, binary preparation, storage, completion or response. A missing reservation alone does not prove storage was never contacted in another execution/environment.

If the receipt is committed, recover its agreement; do not upload again. If pending or absent, inspect the workflow and storage before choosing **Resolve pending upload**. Supply the reason and confirm an audited cancellation receipt/tombstone. This prevents late reservation/completion. A stored orphan, if any, requires separate inspected cleanup; cancellation does not delete it. If cancellation fails because the former resource/account no longer exists after a database replacement, retain the checkpoint and inspect that specific authorization failure; do not clear browser state or bypass the API to manufacture a success.

Only after cancellation is confirmed, select the synthetic Participant/file and start a separate NocoDB attempt. Record request ID, agreement ID, controlled storage reference, reviewer reason and audit identities privately. Verify storage retrieval and approved agreement state; do not equate a successful HTTP response with complete acceptance.

## 3. Inventory and back up production (review first)

Use a checkout pinned to the approved backend commit. Capture `capture_database_inventory.sql`, `capture_effective_definition_review.sql` and `capture_integration_configuration.sql` separately for production and test into protected private evidence. Review their output before sharing. For example, from the repository root:

```bash
umask 077
mkdir -p private-v120-evidence
sudo docker exec -i signaturegate-postgres psql -X -qAt -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < releases/v1.2.0/capture_database_inventory.sql > private-v120-evidence/production-inventory.json
sudo docker exec -i signaturegate-postgres psql -X -qAt -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test < releases/v1.2.0/capture_database_inventory.sql > private-v120-evidence/test-inventory.json
```

Do not commit that directory. Inventory compares canonical objects, effective definitions, installed roles/grants/ownership, staff accounts and data invariants. A matching function name or differing hash is not a migration decision. Preserve existing cash confirmed-date guards and unrelated terminology overrides.

Back up the production database and separately retain the role/ownership/extension configuration needed for restore. This is an operator step after the production backup plan is approved:

```bash
sudo docker exec -i signaturegate-postgres pg_dump -U signaturegate -d signaturegate -Fc > private-v120-evidence/signaturegate-before-v120.dump
sudo docker exec -i signaturegate-postgres pg_restore --list < private-v120-evidence/signaturegate-before-v120.dump > private-v120-evidence/archive-list.txt
```

Checking an archive list is not a verified restore. Restore into a separate protected rehearsal database, preserve owners/grants where required and isolate workers, queue consumers, signing/mail/storage/ERP destinations. Use the reviewed restore procedure for that host. Never restore over production for a rehearsal.

## 4. Select and rehearse the exact forward sequence

`UPGRADE_MANIFEST_DRAFT.json` contains **24 undecided entries and nine unverified environment proofs**. It is conditional ordering, not a list to execute. Against the refreshed production baseline, give every entry a selected/skipped disposition and evidence; reconstruct any missing canonical forward change. Do not load `db/schema.sql` on an existing database or glob all migration files.

Validate the reviewed manifest structure:

```bash
python3 scripts/validate_upgrade_manifest.py releases/v1.2.0/UPGRADE_MANIFEST_DRAFT.json
```

On the protected restored copy, execute only the selected files in dependency order, each with `psql -X -v ON_ERROR_STOP=1`, and retain exit statuses privately. Respect each file's transaction boundaries. Run only the selected changes' scoped verification, check historical identity/contribution/agreement/evidence/audit preservation and actual app-role grants, and rehearse application/configuration rollback plus database recovery. A validation pass does not flip any environment proof automatically.

Finalize the reviewed manifest with source checksums, actual backup/restore evidence, compatible n8n/RootedOps revisions and the maintenance/recovery boundary. If an older application cannot read the upgraded schema, rolling back Git alone is insufficient. Agree the verified recovery method before changing production.

## 5. Datasource and mode changes: timing

| Stage | Required database/configuration |
| --- | --- |
| Development and issue #36 acceptance | Keep `chatgpt_development` bound to the existing test datasource and `signaturegate_test`; verify its restricted principal and test integrations. Do not repoint a shared test datasource at production. |
| Production candidate, before master merge | In an isolated candidate checkout/app, bind PostgreSQL action descriptors to the existing production descriptor and review ERP/signing/storage modes. This source preparation must not edit saved shared connection secrets or publish master. |
| Production maintenance, after approval | Pause incompatible writers/workers, take the final backup, apply the rehearsed selected database changes, verify definitions/grants/history, then publish the accepted production app/workflow revision. |
| After cutover | Check actual datasource identity and published revision; perform the narrow approved production checks. Resume workers after compatibility is verified. Keep development on test. |

Use a temporary read-only query **through each actual Appsmith/n8n datasource**:

```sql
SELECT current_database() AS database_name, current_user AS database_role,
       current_setting('server_version') AS server_version;
```

Saved connection settings live outside Git. If the existing production datasource already targets `signaturegate` with the reviewed production app role, no connection change is needed after merge. If settings do need correction, stage them in an isolated candidate datasource and switch the production app during the approved cutover; never edit a shared datasource blindly before merge. Delete temporary diagnostic actions after recording private evidence.

## 6. Prepare the master PR and export

The reviewed baseline is backend main `9556662677f2567fa71de73c3444d74c5d6fba65`, Appsmith development `666c9bcaefa6bf22c5683f7819bdbbc55e114482` plus [correction PR #10](https://github.com/RayzorDuff/SignatureGate-Appsmith/pull/10) at `7af34c0fb7981f90b19f853f9792dbe68b6496de`, and Appsmith master `48905ca281271889cf6cb778cd0249a221b87c82`. Refresh heads before final packaging. Preserve all five PR #8 repairs and unrelated master changes, including its Cash Deposits widget arrangement and internal-routing work. PR #9 remains excluded.

Prepare a separate production candidate from reviewed feature changes, with a per-file master-only disposition. **Do not merge development wholesale into master.** Add the existing production datasource descriptor from master without inventing a new native identity. In that isolated checkout, inspect a dry run, then rebind metadata using the existing tool:

```bash
node scripts/appsmith-rebind-datasource.mjs --source /path/to/isolated-production-candidate --from signaturegate-postgres-test --to signaturegate-postgres --dry-run
node scripts/appsmith-rebind-datasource.mjs --source /path/to/isolated-production-candidate --from signaturegate-postgres-test --to signaturegate-postgres
node scripts/appsmith-rebind-datasource.mjs --source /path/to/isolated-production-candidate --verify --expected-datasource signaturegate-postgres
```

The source must contain both named descriptors while rebinding. Review unused test descriptor retention separately; no credentials go in Git. Review both the ERP API fallback body **and the two explicit `mode: "test"` controller calls** (confirm and retry). The production candidate must use the established production contract; changing only the body fallback leaves both calls in test mode. Keep Manual signing selection and production-only destinations deliberate. Do not run the production synchronization action during source preparation.

Compile native JS collections/bindings and verify existing ERP widgets/actions/bindings. Required CI must pass; do not bypass a failure. Generate the export from the exact reviewed production candidate, then compare:

```bash
node scripts/appsmith-export.mjs --source /path/to/isolated-production-candidate --output /path/to/candidate-export.json
python3 scripts/validate_appsmith_source_export.py --source /path/to/isolated-production-candidate --export /path/to/candidate-export.json
```

Review source IDs, native identities, descriptors, jsPDF and all pages/actions/collections. Commit the final accepted JSON to `appsmith/Rooted Psyche Membership Ops.json` only after the production-bound source is pinned. Keep VERSION at 1.1.0 and no final tag while the release gates remain open. Reconcile changelog, coordinated dependency/release notes, checksums and publication order at final acceptance; a development dependency version is not a released/deployed pin.

No production SQL, datasource switch, publication, master merge or tag has been performed by this preparation.
