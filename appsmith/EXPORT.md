# Appsmith release export

Canonical source: `RayzorDuff/SignatureGate-Appsmith` split source. The shipped
`appsmith/Rooted Psyche Membership Ops.json` is generated, never hand-edited.

Both local generation and **Regenerate Appsmith export** use
`scripts/prepare-appsmith-release-export.mjs`. It requires two exact 40-character
commit pins and clean Git checkouts, including untracked files. Moving branches,
tags, dirty inputs and mismatched HEADs fail before staging. Inputs must be reviewed
production-bound source and the approved existing native production descriptor.

The script copies source to a disposable directory, reuses the exact
`signaturegate-postgres` descriptor, optionally rebinds staged test SQL actions,
rejects remaining test references, generates the JSON and verifies source/export
preservation. It fixes the previous flag parser defect and has a dedicated
end-to-end synthetic regression test. It writes deterministic provenance with
both source commits, descriptor/export SHA-256 and object counts. Neither inputs
nor any live datasource, credential, workflow or publication are modified.

## Local generation

Use separate clean worktrees for the reviewed source and descriptor baseline.
Replace the pins with the finally reviewed commits; the example candidate is not
approval to publish it. Output/provenance must be outside both input checkouts.

```bash
APP_SOURCE_SHA=50a3b887e34e5905c3daeb208fcd1bfca03824ce
APP_DESCRIPTOR_SHA=48905ca281271889cf6cb778cd0249a221b87c82
node scripts/prepare-appsmith-release-export.mjs \
  --source /path/to/clean-reviewed-appsmith-candidate \
  --source-sha "$APP_SOURCE_SHA" \
  --production-source /path/to/clean-pinned-appsmith-master \
  --production-source-sha "$APP_DESCRIPTOR_SHA" \
  --output "appsmith/Rooted Psyche Membership Ops.json" \
  --provenance appsmith/EXPORT_PROVENANCE.json

node scripts/test-prepare-appsmith-release-export.mjs
node scripts/test-appsmith-export.mjs
node scripts/test-appsmith-rebind-datasource.mjs
python3 scripts/validate_release.py --assets
git diff --check
```

For a disposable candidate, choose temporary output/provenance paths and compare
both outputs across two builds. Do not commit it as the final shipped artifact
before its source has been reviewed/frozen. After master merge, regenerate with
the exact merged source SHA even if the content is unchanged.

## GitHub Actions

Run the workflow on the intended SignatureGate packaging branch with:

- `appsmith_ref`: exact reviewed production source commit (no default/moving ref).
- `production_descriptor_sha`: exact reviewed descriptor baseline commit.

The Action checks out those two commits separately, invokes the same preparer,
checks the result and commits **both** JSON and `EXPORT_PROVENANCE.json` to the
selected backend branch. This writeback is packaging only. It does not merge
Appsmith, publish, migrate, change VERSION or tag a release.

Before publishing, separately verify actual saved database/role and private
service routing, explicit confirm/retry ERP modes **and** API fallback, signing
mode, paper workflow production credential bindings and deployed revisions.
Git datasource descriptors do not contain actual connection targets/secrets.
Development stays on its existing test datasource. Preserve bank selection,
refresh lookup, automatic synchronization, retry/status and historical Drive
links; optional additional ERP/Drive acceptance remains deferred.

Current evidence, operational gates and rollback boundaries are in
[PREPRODUCTION_HANDOFF.md](../releases/v1.2.0/PREPRODUCTION_HANDOFF.md).
