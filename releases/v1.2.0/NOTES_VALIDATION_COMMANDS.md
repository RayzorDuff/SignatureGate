# Next Linode validation sequence: identity notes

Use `signaturegate_test` for migration and behavioral verification. Production commands below are catalog reads only. Do not bootstrap either existing database or replay all migrations. Keep evidence outside Git, restrict access, and do not attach unreviewed logs to public issues.

**October 11 result:** steps 1–3 passed on live test at `f45bd0a`; the actual Appsmith datasource reports `signaturegate_test`/16.13. Do not repeat migration simply to produce another transcript. Continue the outstanding synthetic UI checks in step 4. Production rehearsal remains pending.

## 1. Pull and capture differing effective definitions privately

```bash
cd ~/signaturegate
git pull --ff-only
release_evidence="$HOME/signaturegate-release-evidence/v1.2.0/notes-increment"
mkdir -p "$release_evidence"
chmod 700 "$release_evidence"
umask 077
git rev-parse HEAD > "$release_evidence/source-sha.txt"

(
  set -e
  for release_db in signaturegate_test signaturegate; do
    sudo docker exec -i signaturegate-postgres \
      psql -X -qAt -v ON_ERROR_STOP=1 -U signaturegate -d "$release_db" \
      < releases/v1.2.0/capture_effective_definition_review.sql \
      > "$release_evidence/definitions-$release_db.json" \
      2> "$release_evidence/definitions-$release_db.log"
    python3 -m json.tool "$release_evidence/definitions-$release_db.json" > /dev/null
  done
)
```

Continue only when both captures succeed and parse. The files contain function/view definitions and grant metadata; operational literals may occur in those definitions. They are private review material, not Git artifacts.

## 2. Apply the notes migration to test, twice

The second run verifies deployed reapplication. Both runs are explicit transactions and preserve original participant notes. A provenance record prevents later reruns copying a changed legacy source or undoing a canonical edit/clear. Previously edited identities are preserved; their old source remains available for private operator review. No automatic deletion or merging of operational notes is performed.

```bash
sudo docker exec -i signaturegate-postgres \
  psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  < db/migrations/party_identity_notes.sql \
  > "$release_evidence/notes-migration-first.log" 2>&1
```

Stop on a nonzero exit status. On success:

```bash
sudo docker exec -i signaturegate-postgres \
  psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  < db/migrations/party_identity_notes.sql \
  > "$release_evidence/notes-migration-repeat.log" 2>&1
```

Stop on a nonzero exit status. The repeat's `historical_memberships_processed` should be zero unless a new membership was inserted between runs. Investigate any failure privately; do not paste operational error context into Git.

## 3. Run rollback-only behavioral checks on test

```bash
sudo docker exec -i signaturegate-postgres \
  psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  < db/tests/verify_party_identity_notes.sql \
  > "$release_evidence/notes-verification.log" 2>&1
```

Expected: successful checks followed by `ROLLBACK`. Fixtures cover individual/company read/write/clear, canonical nonmember roles, practitioner/unknown/disabled denial, required reason, no-op audit, audit failure rollback, existing historical copies, multiple memberships, preserved edits, blank/changed sources and repeated import. They print no operational values. Keep the log private because database failure context can contain values.

Then refresh the catalog:

```bash
sudo docker exec -i signaturegate-postgres \
  psql -X -qAt -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  < releases/v1.2.0/capture_database_inventory.sql \
  > "$release_evidence/database-test-after-notes.json"
python3 -m json.tool "$release_evidence/database-test-after-notes.json" > /dev/null
```

## 4. Validate Appsmith on the existing test branch

No frontend change is required for this increment. Retain `chatgpt_development`; verify its actual datasource using:

```sql
SELECT current_database() AS database_name,
       current_setting('server_version') AS postgres_version;
```

Expected: `signaturegate_test`, PostgreSQL 16.13. Run this through the actual Appsmith datasource, rather than only psql.

Using synthetic test identities, validate in this order:

1. `Directory` manager: add/edit notes on `Individual Profile`; save with a reason; reload to verify persistence. Submit without a reason to verify denial and unchanged notes.
2. Document reviewer without membership: edit an accessible individual with membership. Practitioner-only and unauthorized accounts cannot read or change identity notes.
3. Donations reviewer without membership: add/edit/clear notes on `Company Profile`; reload and verify. Also verify an accessible individual contributor.
4. Clear individual notes, rerun the test migration, reload and verify the cleared state is preserved. Use synthetic notes; do not clear an operational identity just to stage this test.
5. `Intake`: create a synthetic individual and company with notes; verify notes land on their respective canonical profiles. Verify the existing submission and contact controls still initialize correctly.
6. Continue the remaining Agreement Type permission/validation/layout/Git/import checks in [PHASE_2_PROGRESS.md](PHASE_2_PROGRESS.md). A successful normal creation alone does not complete that acceptance set.

Record only pass/fail, roles, versions, source SHAs and remaining gaps in Git. Keep identity values, audit details, screenshots, database dumps and workflow/configuration data private.

## 5. Package this private follow-up for review

After all commands succeed and the UI results are recorded privately, package the new folder without changing the original evidence archive:

```bash
tar -C "$HOME/signaturegate-release-evidence/v1.2.0" \
  -czf "$HOME/signaturegate-v1.2.0-notes-followup.tar.gz" notes-increment
chmod 600 "$HOME/signaturegate-v1.2.0-notes-followup.tar.gz"
```

This archive remains private. Phase 1 stays open until effective differences and deployment targets are reviewed; Phase 2 continues independently while those release blockers are resolved.
