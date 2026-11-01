# Release process

`VERSION` is canonical. The README, changelog, versioned release notes, and `vX.Y.Z` tag must agree with it.

```bash
make prepare-release VERSION=1.1.1 RELEASE_DATE=2026-08-13
# Complete docs/CHANGELOG.md and releases/v1.1.1/RELEASE_NOTES.md.
make release-check
git diff --check
```

Run this from a clean `main` branch. Preparation changes files only; it does not commit, tag, push, deploy, migrate the database, import Appsmith, or publish a GitHub release. Release notes must list migrations and deployment order whenever applicable.

For a coordinated Rooted software release, record the exact MushroomProcess, SignatureGate, RootedOps, and BookWorks tags in the coordination manifest. Coordination records compatibility; it does not imply identical version numbers.

## SignatureGate v1.2.0 and the first Appsmith release

The coordinated plan is in [`releases/v1.2.0/RELEASE_PLAN.md`](../releases/v1.2.0/RELEASE_PLAN.md). SignatureGate's changelog records the combined release, identifying changes by subproject; Appsmith-specific release notes record its source revision and link back to that changelog.

Before tagging, use `Regenerate Appsmith export` (`.github/workflows/regenerate-appsmith-export.yml`) with the exact production-bound SignatureGate-Appsmith commit SHA as `appsmith_ref`. Wait for the action's commit of `appsmith/Rooted Psyche Membership Ops.json`, pull it, verify source/export consistency, and run `make release-check`. Record the workflow run and export checksum in the release evidence. This action does not deploy or publish the application.
