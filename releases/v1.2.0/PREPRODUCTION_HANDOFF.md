# v1.2.0 pre-production handoff — November 10, 2026

**Preparation complete for review; production promotion is still gated.**
VERSION remains 1.1.0. No production database, saved datasource, workflow,
published application or release tag was changed.

## Reviewed source and accepted results

- Backend baseline: `f07f0de32218cac6fb01b295113dac53a0670c75`; this preparation PR adds the files indexed in `evidence/preproduction_completion.json`.
- Appsmith [draft production candidate PR #16](https://github.com/RayzorDuff/SignatureGate-Appsmith/pull/16): `50a3b887e34e5905c3daeb208fcd1bfca03824ce`, built from accepted development `2d2c3b2e012d2e73e7e0c6bf351ef8721e84e5f5` and descriptor/master `48905ca281271889cf6cb778cd0249a221b87c82`.
- All 80 master-only changed paths have explicit dispositions in the Appsmith candidate. All 966 tracked native identity records are retained. Its 21 retained cash controls keep master's relative layout below the navigation/access header. Both ERP controller calls and the API fallback use production mode only in the candidate. Shared development remains test-bound.
- Disposable export: 17 pages, 475 actions, 30 collections, one JS library, 235 production PostgreSQL actions. Exact source/descriptor pins and digest are in the evidence index. It is **not** the shipped JSON, and must be regenerated if the candidate changes or merges under a different SHA.
- Existing source/controller checks and targeted promotion/export/manifest/history-verifier tests passed locally. Candidate CI and backend preparation CI must pass before merges; record their actual conclusions in the PRs.
- Previously accepted paper upload/retrieval/reviewer/audit recovery, Intake, cash, authorization and 12-file restored-production rehearsal remain accepted. See the original evidence reports. No full SQL suite or accepted browser workflow was repeated.

## Database candidate and protected evidence

The manifest now explicitly selects the 12 rehearsed forward migrations, skips
11 legacy replays, and skips generic terminology adoption. It pins source hashes,
prerequisites, affected data and recovery boundaries. Its `candidate_forward_order`
matches the accepted rehearsal, including person-contact correction before Intake.
This is a **proposed execution list subject to private baseline review**, not an
assertion that every legacy file was historically executed. Structural parity and
the prerequisite check support reuse; current definitions must still be confirmed.

The nine final environment proofs stay false. Existing scoped restore success is
recorded separately instead of overstating owner/ACL/recovery acceptance.

Use `capture_protected_upgrade_evidence.sql` on the same fresh isolated restore
before and after the selected migrations. It captures roles/memberships, schema,
object owners, effective ACLs, function security/configuration/returns, constraints
and historical row-content digests. `compare-protected-upgrade-evidence.py` fails
on changed/missing preexisting entries or invalid backfill relationships/chunks.
New objects still require explicit grant review. Captures are PRIVATE; never
commit their outputs, row IDs, global-role files or backups.

Intentional mutation: `party_identity_notes.sql` executes its historical backfill,
updating `people.notes` and its timestamp, and adding provenance. Original member
notes remain untouched. The general history digest excludes only these people
fields and newly added organization notes; privately review original canonical
notes, `preserved_edit` decisions and expected imported chunks. The verifier is
not proof of unchanged note wording or effective invoker authorization.

`check_upgrade_invoker_permissions.sql` takes the **actual** Appsmith and n8n DB
role names. It reports schema usage, new private-table rights, function EXECUTE,
owner/security mode and superuser/BYPASSRLS status. It makes no grants. Review the
actual invoker dependency graph and an approved least-privilege policy; do not
solve a denied receipt by broadly granting PUBLIC or running the app as superuser.
Existing production app/helper compatibility is supported by retained signatures
and accepted comparison evidence, but still needs private role/ownership review
and a protected read-only old-app query check before cutover.

## Smallest remaining required gates

1. **Protected environment proof:** on the operator host, complete owner/ACL-preserving restore, actual-principal review, historical note/content checks, old-app read compatibility, writer isolation and recovery exercise. Refresh the selected/skipped baseline if anything drifted. This workspace has neither the operator's private captures/backup nor access to its Docker daemon; these results cannot be invented from Git.
2. **Runtime configuration proof:** record actual deployed compatible RootedOps SHA; inventory the exact live n8n revisions, Header Auth, credentials, internal routes and worker state; probe actual DB name/role through saved Appsmith/n8n connections. The paper workflow source explicitly references `signaturegate_test` on both PG nodes: prepare reviewed production bindings using the existing production credential, preserving the shared test credential. Verify the deployed inventory-scope Code matches the pinned correction. No blind reimport/activation.
3. **Final reviewed promotion:** pass both PRs' CI, review the source/layout and final pinned export, then authorize maintenance/migration/publication separately. No release readiness claim before the two private gates above.

A new ERP synchronization replay, new Drive upload acceptance and a new browser
test framework remain deferred. Existing bank selection/refresh/automatic sync/
retry/status and historical Drive access are preserved. These deferred tests are
not additional release blockers. Full issue closure for #19/#20/navigation/routing
can still require broader evidence than the accepted v1.2.0 functional slice.

## Exact operator sequence for the approved next session

1. Review backend preparation PR and Appsmith #16, require passing CI, and record approvals. Merge backend preparation only when reviewed. Keep Appsmith master merge/publication for the authorized promotion window. Refresh both heads; resolve any new master changes explicitly.
2. Freeze the reviewed Appsmith candidate. Check out its exact SHA and the recorded descriptor SHA into separate clean worktrees. Run the command in [EXPORT.md](../../appsmith/EXPORT.md) twice to a disposable output; compare SHA-256 and provenance. After the approved Appsmith master merge, regenerate with the exact merged SHA, review/commit the shipped JSON and `EXPORT_PROVENANCE.json` in SignatureGate. Do not copy this disposable candidate over the shipped artifact.
3. Complete the protected preparation below before production maintenance approval. At maintenance, isolate application writes, webhooks, schedulers and queue consumers. Back up live Appsmith/workflow configuration privately. Capture final production schema/owners/roles and a custom DB dump plus no-password global roles; checksum and verify a restore. Do not start migrations until the approved selected list and recovery evidence match this final baseline.
4. Run only `candidate_forward_order` from the approved manifest, with every source hash verified, using `psql -X -v ON_ERROR_STOP=1` against **signaturegate**. This is a later authorized operator action, not a command authorized by this document. Respect each file's own transaction; stop on the first error. Never glob migration files, run schema bootstrap, or run terminology adoption implicitly.
5. Before resuming writes, verify selected definitions, role/EXECUTE/table permissions, actor/account links, historical content/backfill, cash-date guards, receipts and constraints. Compare private pre/post evidence and run only a newly necessary targeted verification. Confirm the old app's read contract if it remains live during this interval.
6. Publish the approved Appsmith revision using the existing reviewed production datasource. Verify `current_database()`/`current_user` through that saved datasource and published source revision. Development stays on `signaturegate_test`; merging Git does not apply credentials or guarantee publication.
7. Promote only reviewed workflow/configuration differences with original identities/auth/bindings. Verify actual caller-container routing and the recorded deployed RootedOps contract without creating an ERP transaction. Confirm paper production PG bindings and inventory scope. Resume compatible consumers in a controlled order only after schema/app/workflow checks pass; monitor existing receipts/queues without resending uncertain requests.
8. Record production acceptance and final artifact/backend/Appsmith/dependency SHAs. Complete release notes, then use the established release process to change VERSION/README/changelog to 1.2.0, run release checks, and only then create/publish the coordinated tag/release. None of these final actions has occurred here.

## Protected restore/recovery procedure

Run on the operator host with `umask 077`; keep everything under the ignored
`private-v120-evidence/` or external backup directory. Use a **fresh** disposable
PostgreSQL 16.13 container with Docker `--network none`, a distinct container name,
and a bootstrap role that does not collide with captured production roles.

Restore the reviewed `pg_dumpall --globals-only --no-role-passwords` output into
that isolated cluster before restoring the custom archive. Create the rehearsal
database with the captured production DB owner/locale. Restore with owners and
ACLs retained (`pg_restore --single-transaction --exit-on-error`; **omit**
`--no-owner --no-acl`). Stop on missing roles, ownership or ACL errors. Do not
restore roles or the archive into the live cluster for this rehearsal.

For example, with the actual isolated container and DB already verified:

```bash
# REHEARSAL_CONTAINER must be the newly isolated container, never the live one.
sudo docker inspect --format '{{.HostConfig.NetworkMode}}' "$REHEARSAL_CONTAINER"
# Require exactly 'none'; then capture on signaturegate_rehearsal before changes.
sudo docker exec -i "$REHEARSAL_CONTAINER" psql -X -qAt -v ON_ERROR_STOP=1 \
  -U "$REHEARSAL_ADMIN" -d signaturegate_rehearsal \
  < releases/v1.2.0/capture_protected_upgrade_evidence.sql \
  > private-v120-evidence/protected-before.jsonl
```

Verify all manifest hashes and review the 12-file order, then apply the selected
files **only to the isolated rehearsal**. Capture `protected-after.jsonl` with
the same command and run:

```bash
python3 scripts/compare-protected-upgrade-evidence.py \
  private-v120-evidence/protected-before.jsonl private-v120-evidence/protected-after.jsonl
sudo docker exec -i "$REHEARSAL_CONTAINER" psql -X -qAt -v ON_ERROR_STOP=1 \
  -v app_role="$ACTUAL_APP_DB_ROLE" -v workflow_role="$ACTUAL_N8N_DB_ROLE" \
  -U "$REHEARSAL_ADMIN" -d signaturegate_rehearsal \
  < releases/v1.2.0/check_upgrade_invoker_permissions.sql \
  > private-v120-evidence/invoker-permissions.jsonl
```

Privately review the exclusions and all new objects/grants, and run read-only
queries from the pinned old application under its real invoker role in this
protected cluster. Verify restoration of the pre-upgrade backup/configuration in
a second isolated recovery target; compare owners/ACLs/history again. The existing
12 successful rollback-only functional scripts do not need another complete run
unless a changed source or actual failure justifies it.

## Rollback boundaries

- **Before migration:** restore the previous app/workflow/configuration revisions; no DB rollback is needed if it is unchanged.
- **Within a failing file:** that file's transaction rolls back; earlier files may already be committed. Keep writers stopped. Approve a forward repair or perform the rehearsed full restore, never a guessed down migration.
- **After migration, before reopening writes:** Git rollback alone cannot undo the schema/backfill. Use the verified backup plus roles/ACLs and matching app/workflow revision if compatibility fails.
- **After reopening writes/external effects:** a pre-cutover restore can lose new records or resurrect queue work. Freeze writers, preserve post-cutover receipts/audits/external IDs, reconcile them, and authorize recovery separately. Never re-upload, resend signing, or repeat ERP events to make a test pass.
