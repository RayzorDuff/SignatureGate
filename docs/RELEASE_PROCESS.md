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
