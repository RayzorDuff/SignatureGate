# Linode commands for Phase 1 steps 2–5

The existing databases remain `signaturegate` and `signaturegate_test`. These commands create a separate empty canonical reference database, `signaturegate_release_v1_2_0`, in the same PostgreSQL container. It is for catalog comparison; it is not a replacement production/test database and no Appsmith datasource should point to it.

Run each block separately and stop on an error. These commands do not apply migrations to either current database, pull Appsmith changes, execute workflows or publish applications.

## Setup

```bash
cd ~/signaturegate
git pull --ff-only
export SG_EVIDENCE="$HOME/signaturegate-release-evidence/v1.2.0"
umask 077
mkdir -p "$SG_EVIDENCE"
```

Step 1's existing JSON captures are inputs. The comparison script validates their database names and required content before creating anything.

## 2. Create canonical database and compare catalogs

```bash
bash scripts/capture_release_database_comparison.sh "$SG_EVIDENCE"
```

The script uses `createdb --template=template0 --owner=signaturegate`, loads `db/schema.sql` with `ON_ERROR_STOP`, checks release APIs through a second connection, captures the new database and produces `database-differences.csv`. All database commands use the same container/client/server as production. Differences remain `pending_review`.

If `signaturegate_release_v1_2_0` already exists, the script stops without dropping/reusing it. To make a new reference after preserving earlier evidence, use a new suffix and a new evidence directory containing copies of the test/production captures:

```bash
mkdir -p "$SG_EVIDENCE/recheck"
cp "$SG_EVIDENCE/database-test.json" "$SG_EVIDENCE/database-production.json" "$SG_EVIDENCE/recheck/"
SG_VALIDATION_DB=signaturegate_release_v1_2_0_recheck \
  bash scripts/capture_release_database_comparison.sh "$SG_EVIDENCE/recheck"
```

Do not treat the CSV row count as a migration count. Grants, extension differences, legacy objects and function signatures need individual review; some differences are intentional. The initial comparison does not check historical data/backfill integrity.

## 3. Capture Appsmith and other deployed service versions

```bash
python3 scripts/capture_release_services.py \
  --evidence "$SG_EVIDENCE" --rootedops "$HOME/RootedOps"
python3 -m json.tool "$SG_EVIDENCE/deployed-services.json"
cat "$SG_EVIDENCE/n8n-version.txt" "$SG_EVIDENCE/erpnext-app-versions.txt"
```

The collector reads the actual containers/images, digest/version labels and a small allowlist of service URLs/list mappings. It also records the host RootedOps checkout and compares tracked custom-app files with those mounted in ERPNext. A host Git SHA alone is not deployed-version evidence; extra deployed files/dependencies still require review. Missing containers/version commands are recorded as unavailable rather than assumed successful.

Appsmith's Git and published state and actual datasource execution must be observed in Appsmith. In the development editor, create a temporary PostgreSQL query named `qReleaseEnvironmentCheck`, set it to manual execution, select the actual `signaturegate-postgres-test` datasource, and run:

```sql
SELECT current_database() AS database_name,
       current_setting('server_version') AS postgres_version,
       current_timestamp AS observed_at;
```

Expected development result: `signaturegate_test`. Repeat using the production application's actual `signaturegate-postgres` datasource; expected result: `signaturegate`. Record each datasource/action identity and result, plus editor branch/commit and published revision/evidence. Check published bindings separately. Keep unknown published SHAs marked PENDING; a remote Git head cannot establish what is published. Remove the temporary query after recording the result, without committing/deploying it. Preserve preexisting editor work and defer pulling the new `Agreement Templates` implementation until its backend prerequisite is installed on test.

Prepare a local review record without overwriting one already started:

```bash
test -e "$SG_EVIDENCE/operator-verification.md" || \
  cp releases/v1.2.0/OPERATOR_EVIDENCE_TEMPLATE.md "$SG_EVIDENCE/operator-verification.md"
nano "$SG_EVIDENCE/operator-verification.md"
```

## 4. Capture workflow revisions and configuration mappings

```bash
python3 scripts/capture_release_services.py --evidence "$SG_EVIDENCE" --workflows
python3 -m json.tool "$SG_EVIDENCE/n8n-publication-status.json"
```

This exports workflow drafts and, when the installed CLI advertises `--published`, published/active versions separately. Only summaries are saved: workflow IDs/revisions, activation flags, definition/query hashes, route targets and credential IDs/names. Raw exports are held briefly inside a private temporary container directory and removed; credential values, header bodies, pinned records and code bodies are not saved. Dynamic expressions and credential connection targets require inspection in n8n. If published export is unavailable, confirm the running revision in n8n; draft metadata does not establish it. No workflow execution/activation/import is requested. CLI reference: <https://docs.n8n.io/hosting/cli-commands/>.

Capture database-side template mappings and mailing defaults, using read-only queries against both current databases:

```bash
(
  set -e
  for SG_CURRENT_DB in signaturegate_test signaturegate; do
    sudo docker exec -i signaturegate-postgres \
      psql -X -qAt -v ON_ERROR_STOP=1 -U signaturegate -d "$SG_CURRENT_DB" \
      < releases/v1.2.0/capture_integration_configuration.sql \
      > "$SG_EVIDENCE/configuration-$SG_CURRENT_DB.jsonl"
  done
)
```

The JSONL capture has one JSON object per line. Missing template objects/fields are reported, not created. It contains template configuration and mailing defaults, without signed agreement/person/contact records. Verify these mappings against live Documenso/Listmonk and credential host/database targets in n8n; the effective worker environment/list IDs are in `deployed-services.json`. Record actual ERP mode and any dynamic target review in `operator-verification.md`.

## 5. Package evidence for review; keep the gate pending

Validate the captured JSON/JSONL, create checksums and prepare one archive:

```bash
bash scripts/package_release_evidence.sh "$SG_EVIDENCE"
```

The helper stops before packaging if any required capture is missing, invalid, empty or incomplete. Keep live evidence outside the public Git repository. Provide the archive for release review; catalog differences and operator evidence determine the required forward upgrades. The reviewed ordered manifest, ledger dispositions and environment/release-plan updates are committed after that analysis. Capturing/archiving alone does not mark Phase 1 complete or authorize production migration.
