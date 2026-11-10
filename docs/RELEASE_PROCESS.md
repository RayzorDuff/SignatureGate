# Release process

`VERSION` is canonical. The README, changelog, versioned release notes, and `vX.Y.Z` tag must agree with it.

```bash
# Example only — use the version and date of the release being prepared.
make prepare-release VERSION=1.2.0 RELEASE_DATE=YYYY-MM-DD
# Complete docs/CHANGELOG.md and releases/v1.1.1/RELEASE_NOTES.md.
make release-check
git diff --check
```

Run this from a clean `main` branch. Preparation changes files only; it does not commit, tag, push, deploy, migrate the database, import Appsmith, or publish a GitHub release. Release notes must list migrations and deployment order whenever applicable.

For a coordinated Rooted software release, record the exact MushroomProcess, SignatureGate, RootedOps, and BookWorks tags in the coordination manifest. Coordination records compatibility; it does not imply identical version numbers.

## SignatureGate v1.2.0 and the first Appsmith release

The coordinated plan is in [`releases/v1.2.0/RELEASE_PLAN.md`](../releases/v1.2.0/RELEASE_PLAN.md). SignatureGate's changelog records the combined release, identifying changes by subproject; Appsmith-specific release notes record its source revision and link back to that changelog.

Before tagging, complete the reviewed Appsmith development-to-master reconciliation, preserving production-only fixes, actual datasource identities and explicit ERP/integration modes. After the approved Appsmith candidate has been merged into `master`, use `Regenerate Appsmith export` (`.github/workflows/regenerate-appsmith-export.yml`) with the exact production-bound SignatureGate-Appsmith commit SHA as `appsmith_ref`. Wait for the action's commit of `appsmith/Rooted Psyche Membership Ops.json`, pull it, verify source/export consistency, and run `make release-check`. Record the workflow run and export checksum in the release evidence. This action does not deploy or publish the application.

The Action and local process both invoke [`scripts/prepare-appsmith-release-export.mjs`](../scripts/prepare-appsmith-release-export.mjs). The script uses a disposable Appsmith source copy, the native production PostgreSQL descriptor from Appsmith `master`, and the existing rebind/verify/export tools. Use the **exact merged production Appsmith commit SHA** rather than a moving branch when preparing release evidence. The workflow's checkout of `master` for the descriptor is a separate input: record its resolved commit and confirm it matches the reviewed production baseline. Do not run it with raw `chatgpt_development` as a production candidate.

The generated export must be reviewed/committed in SignatureGate, but **does not** apply Appsmith's saved connection credentials or database target, change n8n/ERP modes, merge Appsmith branches, or publish the application. Check the actual production connection/database role and deployed app revision during the approved cutover. For further detail, use [`appsmith/EXPORT.md`](../appsmith/EXPORT.md) and the [v1.2.0 production promotion runbook](../releases/v1.2.0/PRODUCTION_UPGRADE_AND_PROMOTION.md).
