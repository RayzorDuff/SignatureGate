# Production database update and Appsmith promotion

**Current pre-production review (November 10):** [PREPRODUCTION_HANDOFF.md](PREPRODUCTION_HANDOFF.md) supersedes the planning counts and source pins below. All 24 manifest entries now have proposed dispositions (12 selected forward files, 11 skipped legacy replays, one separately audited configuration skipped); nine final private environment proofs remain open. [Appsmith candidate PR #16](https://github.com/RayzorDuff/SignatureGate-Appsmith/pull/16) is prepared at `50a3b887e34e5905c3daeb208fcd1bfca03824ce`. Its disposable dual-pinned export validates; it is not the shipped artifact. Existing accepted paper/cash/authorization and restored-production results remain accepted. Final master merge, schema migration, publication and release are not authorized here.


Updated November 10, 2026 (UTC). Reviewable preparation, **not an approved execution manifest**. Test2 was deleted. Continue development on the existing host using the separate `signaturegate_test` database and development branch; do not change `signaturegate` or published master during acceptance.

## Current accepted checkpoint and remaining release work (November 10 UTC)

**Accepted, do not repeat as open tasks:** Issue #36 NocoDB synthetic upload, exact retrieved PDF, independent reviewer approval and audited receipt are documented in [native evidence](evidence/november_10_paper_native_retry.md). On a checksum-verified, network-isolated PostgreSQL 16.13 **restore of production**, 12 reviewed SQL migrations applied successfully in sequence, 12 targeted rollback-only SQL verification scripts passed, the upgraded schema matched `signaturegate_test` across the eight compared categories and all 35 original production-table row counts were preserved. See [rehearsal evidence](evidence/november_10_restored_production_migration_rehearsal.md). These are *not* evidence of production migration or external worker acceptance.

**Still required before production approval:** finalize all 24 manifest selected/skipped dispositions and nine environmental proofs; verify owner/grant/role permissions and data-level invariants; pin actual n8n/ERP/RootedOps/other integration revisions and isolate writers; perform the final approved-sequence/recovery rehearsal; review Appsmith development vs production master and production mode differences; produce the pinned-source JSON through the shared generator; obtain cutover approval and verify live publication. The requested NocoDB-only new-upload UI and inventory-location-scope correction still need their recorded deployment dispositions. A new ERP end-to-end replay and Drive new-upload acceptance are explicitly deferred; retain existing ERP capabilities, historical Drive evidence and links.

The numbered sections below contain **historical diagnostic and recovery procedures**. They are not a mandatory rerun sequence. Use them only for unresolved new failures. The current release checkpoint is in [STATUS.md](STATUS.md), not the older issue #36 retry instructions.

## 1. Historical diagnostic: reconcile the operator SQL transcript (already resolved)

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

## 2. Historical recovery procedure: existing paper request (accepted retry complete)

In the same signed-in account, use **Check saved paper upload**. Changing the selected Participant does not change the saved account-owned request. Retain its request/member/practitioner IDs from the saved checkpoint privately; never post file bytes, contacts, credentials or execution payloads in an issue.

Verify that the actual Appsmith receipt query and both n8n Postgres nodes use `signaturegate_test`, and that the upload endpoint is the intended authenticated paper workflow. A host name or a Git datasource descriptor alone does not prove this. Run the database identity probe below through the actual datasource. Inspect the matching workflow execution's first failing node privately: authentication/validation, reservation, binary preparation, storage, completion or response. A missing reservation alone does not prove storage was never contacted in another execution/environment.

If the receipt is committed, recover its agreement; do not upload again. If pending or absent, inspect the workflow and storage before choosing **Resolve pending upload**. Supply the reason and confirm an audited cancellation receipt/tombstone. This prevents late reservation/completion. A stored orphan, if any, requires separate inspected cleanup; cancellation does not delete it. If cancellation fails because the former resource/account no longer exists after a database replacement, retain the checkpoint and inspect that specific authorization failure; do not clear browser state or bypass the API to manufacture a success.

Only after cancellation is confirmed, select the synthetic Participant/file and start a separate NocoDB attempt. Record request ID, agreement ID, controlled storage reference, reviewer reason and audit identities privately. Verify storage retrieval and approved agreement state; do not equate a successful HTTP response with complete acceptance.

## 3. Production inventory and backup (baseline completed; refresh at cutover)

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

## 4. Finalize migration dispositions and rehearse the final forward sequence

`UPGRADE_MANIFEST_DRAFT.json` contains **24 proposed dispositions and nine unverified final environment proofs**. It is conditional ordering, not a list to execute. Against the refreshed production baseline, give every entry a selected/skipped disposition and evidence; reconstruct any missing canonical forward change. Do not load `db/schema.sql` on an existing database or glob all migration files.

Validate the reviewed manifest structure:

```bash
python3 scripts/validate_upgrade_manifest.py releases/v1.2.0/UPGRADE_MANIFEST_DRAFT.json
```

The scoped November 10 rehearsal already executed 12 selected candidate files successfully; it does not by itself select/skip all 24 manifest entries or verify role/owner/grant recovery. For the final reviewed plan, on a fresh protected restored copy, execute only the selected files in dependency order, each with `psql -X -v ON_ERROR_STOP=1`, and retain exit statuses privately. Respect each file's transaction boundaries. Run only the selected changes' scoped verification, check historical identity/contribution/agreement/evidence/audit preservation and actual app-role grants, and rehearse application/configuration rollback plus database recovery. A validation pass does not flip any environment proof automatically.

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

## Established Appsmith merge/export procedure (shared local and Action path)

The documented v1.2.0 candidate preparation remains a gated, reviewed step: reconcile `chatgpt_development` against Appsmith `master`, preserve master-only fixes and native identities, verify production ERP/signing/storage modes, and merge only the reviewed production candidate. Do **not** merge raw development wholesale or retarget its saved test datasource.

After the candidate is reviewed and pinned, the checked-in export in **SignatureGate** must come from that *same* Appsmith source commit. The `Regenerate Appsmith export` Action and the manual process now share one staging command:

```bash
node scripts/prepare-appsmith-release-export.mjs \
  --source /path/to/reviewed-appsmith-candidate \
  --source-sha "$APP_SOURCE_SHA" \
  --production-source /path/to/pinned-appsmith-master \
  --production-source-sha "$APP_DESCRIPTOR_SHA" \
  --output "appsmith/Rooted Psyche Membership Ops.json" \
  --provenance appsmith/EXPORT_PROVENANCE.json
```

The production-source path provides the existing `signaturegate-postgres` native descriptor, while the script stages the source, applies `appsmith-rebind-datasource.mjs` if needed, verifies all SQL action datasource descriptors, generates the JSON with `appsmith-export.mjs`, and checks source/export parity. None of this changes live Appsmith secrets/connections or publishes the app. For repeatability, the Action requires exact `appsmith_ref` and `production_descriptor_sha` commit inputs and checks out both separately, then invokes the same command. See [the canonical export workflow](../../appsmith/EXPORT.md) for both invocation paths and limitations.

During the approved cutover, verify the *actual* PostgreSQL database name and role through Appsmith and n8n, retain the production integration modes, and verify deployed revision. Keep `VERSION=1.1.0` and the release tag unmodified until production acceptance and final packaging.

## 6. Prepare the master PR and export

The reviewed baseline is backend main `9556662677f2567fa71de73c3444d74c5d6fba65`, Appsmith development `666c9bcaefa6bf22c5683f7819bdbbc55e114482` plus [correction PR #10](https://github.com/RayzorDuff/SignatureGate-Appsmith/pull/10) at `322816a92aec2f9309b7d39a9c0099a841156ce5`, and Appsmith master `48905ca281271889cf6cb778cd0249a221b87c82`. Refresh heads before final packaging. Preserve all five PR #8 repairs and unrelated master changes, including its Cash Deposits widget arrangement and internal-routing work. PR #9 remains excluded.

Prepare a separate production candidate from reviewed feature changes, with a per-file master-only disposition. **Do not merge development wholesale into master.** The Appsmith production master descriptor is reused, not re-created. Explicitly review the ERP API fallback and both confirm/retry `mode: "test"` controller calls before accepting production integrations; changing only a fallback does not switch those calls. Preserve manual signing selection and deliberate storage destinations. Do not initiate production synchronization during source preparation.

**Canonical build after candidate merge:** use `scripts/prepare-appsmith-release-export.mjs` (or the `Regenerate Appsmith export` Action at the pinned, accepted Appsmith SHA), as shown in the shared procedure above. Do not independently repeat the old rebind-and-raw-export commands; the shared script stages a temporary copy and runs rebind, verify, export and source/export checks. Compile native JS collections and bindings, retain ERP widgets/actions, and require CI. Saved datasource connection settings and published revision still require runtime verification.

Review source IDs, native identities, descriptors, jsPDF and all pages/actions/collections. Commit the final accepted JSON to `appsmith/Rooted Psyche Membership Ops.json` only after the production-bound source is pinned. Keep VERSION at 1.1.0 and no final tag while the release gates remain open. Reconcile changelog, coordinated dependency/release notes, checksums and publication order at final acceptance; a development dependency version is not a released/deployed pin.

No production SQL, datasource switch, publication, master merge or tag has been performed by this preparation.
