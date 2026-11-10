# Appsmith release export (production-bound)

**Canonical Appsmith application source:** `RayzorDuff/SignatureGate-Appsmith`, split source.

**Checked-in release artifact:** `SignatureGate/appsmith/Rooted Psyche Membership Ops.json`. It is generated, never hand-edited. The export and its source must be pinned to a reviewed Appsmith commit.

## One shared build path: local and GitHub Actions

Both the manual command and the **Regenerate Appsmith export** workflow invoke the same production preparation script: `scripts/prepare-appsmith-release-export.mjs`.

The preparation script:

1. Copies the requested, reviewed Appsmith source into a disposable directory; it **never edits** the development checkout.
2. Obtains the existing **native production datasource descriptor** (`datasources/signaturegate-postgres.json`) from the Appsmith `master` baseline; it does not create an invented datasource identity or credentials.
3. If the staged source contains `signaturegate-postgres-test`, runs the existing `appsmith-rebind-datasource.mjs` dry run and real metadata rebind to `signaturegate-postgres`; drops the staged test descriptor. If it is already production-bound, performs verification without rebinding.
4. Runs `appsmith-rebind-datasource.mjs --verify --expected-datasource signaturegate-postgres`, creates the monolithic export with `appsmith-export.mjs`, validates its native source/export preservation with `validate_appsmith_source_export.py`, and rejects lingering test PostgreSQL datasource references.
5. Deletes the disposable source directory. The generated JSON is the only intended output.

The script only changes **source metadata in the temporary copy**. Appsmith's saved connection settings, credentials, database name and published application state live outside Git and **must be verified in the runtime**. Rebinding a native datasource descriptor does not retarget a shared live connection, nor does it automatically switch hard-coded ERP `mode: "test"` controller calls to production. Verify signing/ERP/NocoDB/Drive/inventory routing and master-only changes before publication.

## Local regeneration

Clone both repositories (or supply their paths):

```bash
cd ~/GitHub/SignatureGate
node scripts/prepare-appsmith-release-export.mjs \
  --source "$HOME/GitHub/SignatureGate-Appsmith" \
  --production-source "$HOME/GitHub/SignatureGate-Appsmith" \
  --output "appsmith/Rooted Psyche Membership Ops.json"

node scripts/test-appsmith-export.mjs
python3 scripts/validate_release.py --assets
git diff --check
```

The `--production-source` checkout **must contain the approved Appsmith master datasource descriptor**. If the development checkout lacks it, use **two distinct checkouts/worktrees** for `--source` and `--production-source`; passing the development checkout for both will correctly fail instead of inventing a production datasource.

## GitHub Actions

Run **SignatureGate → Actions → Regenerate Appsmith export**, selecting the exact reviewed Appsmith production candidate commit or `master`. Default: `master`. The workflow checks out the requested source and a separate Appsmith `master` descriptor baseline, invokes the same script, validates the generated export and commits it when changed, using the existing workflow's writeback behavior.

**Do not select raw `chatgpt_development` for production promotion.** First review development vs Appsmith `master`, preserve master-only repairs and native IDs, prepare the production candidate, verify explicit production integration modes, pass required CI, then merge the reviewed candidate into Appsmith `master` or select a pinned, reviewed production candidate ref. The Action does not perform a Git branch merge, an Appsmith publish, a database migration or a release tag.

For the safest recurring release order: accepted development → reviewed Appsmith production candidate and Appsmith master merge → generate/export into SignatureGate from pinned Appsmith master commit → validate and review artifact difference → backend/schema and service deployment during approved cutover → runtime datasource identity and published revision checks → final version, release notes and tag.

For the current v1.2.0 cutover, follow [the production promotion runbook](../releases/v1.2.0/PRODUCTION_UPGRADE_AND_PROMOTION.md). The restored-production schema rehearsal is documented separately; its success does **not** authorize automatic master merge, production datasource switching or deployment.
