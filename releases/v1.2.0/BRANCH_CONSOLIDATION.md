# SignatureGate branch consolidation

Checkpoint: November 1, 2026. The owner authorized merging release work into SignatureGate `main`, with production schema deployment kept separate. SignatureGate-Test continues to use SignatureGate-Appsmith `chatgpt_development`; this is not authorization to promote that application to `master` or deploy production changes.

The remote audit used main `8fd3878745f75269f3da5328939cd73d6517e323`. Fourteen topic/legacy branch heads were inspected: thirteen were already ancestors of main. The only unique commit was the old datasource-export fix in PR [#22](https://github.com/RayzorDuff/SignatureGate/pull/22). Its intended behavior is already covered by the newer recursive datasource collector and exact-source preservation tests introduced by `5d4f6c9`.

Reconcile PR #22 by merging current main into its branch and retaining the complete current exporter. The resulting code/assets/schema match the pre-consolidation main tree; only this audit and the release-status pointer are added. Use a merge commit so the original branch commit remains reachable. Do not reintroduce the historical non-recursive collector or rewrite branch history. No branches are deleted.

| Remote branch | Audited head | Disposition |
| --- | --- | --- |
| `appsmith-git-test` | `3c57fcb9d4b7` | Already contained in main |
| `chatgpt/appsmith-datasource-rebind` | `51ba0def4265` | Already contained in main |
| `chatgpt/issue-17-cash-deposit-backend` | `958142323052` | Already contained in main |
| `chore/appsmith-export-generator` | `875cbd9e7070` | Already contained in main |
| `feature/appsmith-e2e-foundation` | `5cdd875ae4d7` | Already contained in main |
| `fix/appsmith-export-datasources` | `6a0d353ef0dc` | Remaining exporter fix; reconcile history and retain the newer implementation |
| `fix/canonical-regression-fixtures` | `bc3fa3e03ce0` | Already contained in main |
| `patch/2a7f80f-terminology-admin` | `2a7f80f17838` | Already contained in main |
| `patch/issue20-appsmith-json-repair` | `679defa0f360` | Already contained in main |
| `repair/appsmith-monolithic-issue20` | `679defa0f360` | Already contained in main |
| `restore/cash-deposit-migrations` | `a464751a9325` | Already contained in main |
| `tmp/appsmith-membership-ops-import-patch` | `679defa0f360` | Already contained in main |
| `work/appsmith-json-repair` | `679defa0f360` | Already contained in main |
| `work/appsmith-membership-ops-repair` | `679defa0f360` | Already contained in main |

## Validation and release tracking

- The exporter fixture checks pass for flat/nested datasources, exact body/library preservation, embedded canvases and rejected orphan/conflicting assets.
- A temporary development-source export retains 17 pages, 472 actions, 30 collections, four datasources and one JS library; the exact-source preservation validator passes. The shipped application JSON is not replaced by this consolidation.
- `make release-check` and `git diff --check` pass. Inspect the main-to-proposed changed-file list: only documentation changes are intended; no code/assets/schema deletions.
- Canonical SQL PR [#31](https://github.com/RayzorDuff/SignatureGate/pull/31) is already merged into main. Its [native PostgreSQL 16 run](https://github.com/RayzorDuff/SignatureGate/actions/runs/41320554004/job/124889618627) passed 47 checks twice, with public data unchanged after each check.
- Appsmith datasource-audit PR [#6](https://github.com/RayzorDuff/SignatureGate-Appsmith/pull/6) is already merged into `chatgpt_development`. Both [CI jobs](https://github.com/RayzorDuff/SignatureGate-Appsmith/actions/runs/41321024058) pass. Keep Appsmith development and production promotion separate.

The remaining release gates are live Test2 datasource/principal verification, private Drive/NocoDB upload/retrieval/review, isolated integration acceptance, reviewed forward migrations and restore rehearsal, a released RootedOps dependency pin, and final production-bound changelog/export/version/tag packaging. Historical October UI acceptance is not evidence that the restored shared Test2 deployment has passed these gates. Browser-harness expansion remains deferred under #27.

Production schema changes are deployed only after testing and an independently reviewed rollout sequence. This consolidation does not execute SQL, change saved datasource credentials, use Lish, publish an application, alter shared services or deploy to production. Shared console access still requires `~/bin/test2-console-lock signaturegate` and separate Screen sessions, with service changes coordinated separately.
