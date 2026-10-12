# Test confidence and operator workload

High confidence applies to the behavior and environment actually exercised. It is not a percentage or certification of the entire release. Reuse passing evidence when the relevant code and prerequisites are unchanged. Each increment should request only consequential runtime gaps, normally one to three focused operator scenarios. Existing source/SQL checks supply regression coverage; a new browser harness is deferred beyond this release.

| Behavior | Evidence | Confidence and remaining scope | Manual request |
| --- | --- | --- | --- |
| Canonical roles, Participant self-read and denied writes | Actual source-query tests; `verify_application_authorization.sql`; operator's successful test migration twice and checks at backend `26531cf` | High for tested SQL/resource invariants. Operator also reports reasonable practitioner/reviewer boundaries and expected Participant restrictions | No repeat of the full role matrix for this increment |
| Denied-page navigation and Contributor choice labels | Source/controller checks plus operator confirmation | High for the reported development UI behavior | No repeat |
| Intake email validation | Synthetic valid/invalid/blank controller fixtures plus operator confirmation | High for the practical email formats exercised | No repeat |
| Cash lifecycle, totals, print/tally, immutable confirmation and correction | Isolated canonical SQL suite; operator's successful PostgreSQL test correction verification | High for covered SQL invariants; deployed ERP delivery remains separate | Do not repeat backend cases manually |
| Reason-aware revival and audit atomicity | New rollback-only SQL checks: blank/legacy calls, unauthorized reviewer, unchanged donation, exact cash restoration, original/new rationale, repeat/missing/ineligible/active-batch denial and audit-failure rollback | High in the isolated canonical database; live migration/engine check pending | Run the test-only script once; no hand-crafted negative SQL cases |
| Explicit action execution modes | Observed Appsmith sync `f412b81` changed 24 guarded actions from Manual to Automatic; source-mode regression checks and official v2.4.2 server contract | Explicit Manual choices are now pinned with `userSetOnLoad: true`. Source-level confidence is high; persistence through the next live pull must be inspected | Agent checks the next synchronized repository commit; no per-action manual inspection requested |
| New reconciliation dialog controller | VM checks for exact row/mode, no write on open/cancel/blank reason, fresh authority/account, double click, write failure and committed-refresh warning; actual prepared source SQL; registration/export checks | High for covered controller contracts; moderate for Appsmith 2.4.2 modal rendering and SDK integration | One focused dialog scenario below |
| Reports categories and financial guards | Actual source-query fixtures for all six groups and boundary cases; source/controller tests | High for covered query math and authorization. Deployed rendering has less evidence | A final candidate smoke check only if a reporting dependency changes or UI/runtime errors appear |
| Paper upload, Documenso, Listmonk, inventory HTTP and ERP/bank routes | Source review and isolated logic do not establish deployed destination, credentials, caller authorization or side effects | Integration acceptance remains open; development paper upload stays disabled | Defer targeted synthetic route checks until a reviewed test destination is available |
| Production upgrade and recovery | Fresh bootstrap cannot establish behavior on existing production data, owners or grants | Protected restored-copy rehearsal and ordered manifest remain required | One controlled deployment/recovery sequence in its release phase |

## Accepted operator evidence

The operator reports `Permission validation exit code: 0` after pulling backend `26531cf`. The supplied sequence used `ON_ERROR_STOP` and `set -e` for both authorization migration applications, authorization verification and confirmed-date correction verification. Detailed logs were not supplied; no private records or configuration are copied into Git. This is accepted operator execution evidence, not an independent log inspection.

The operator confirms retained navigation on denied pages, clear Contributor choices, generally reasonable practitioner/reviewer permissions, expected Participant-only restrictions and fixed Intake email validation. These observations do not certify every external endpoint or every combined-role scenario. They remove the need to repeat the same broad manual smoke checklist.

## Current increment: one automated command and one UI scenario

On Linode, before pulling the matching Appsmith development update:

```bash
cd ~/signaturegate
git pull --ff-only
bash releases/v1.2.0/validate_cash_reconciliation_test.sh
```

Expected exit code **0**. The script targets only `signaturegate_test`, applies the migration twice and runs rollback-only revival/lifecycle/correction checks with private logs. Stop on failure. The existing canonical authorization migration must already be installed; the operator's prior successful run satisfies that prerequisite. Do not run `db/schema.sql` on an existing database.

After success, preserve unsynchronized editor work, pull Appsmith `chatgpt_development` and reload with its test datasource. As a Donations Reviewer, use one disposable, synthetic verified Cash on Hand donation:

1. Click **Exclude**, provide a synthetic reason and confirm. The dialog must render correctly and the intended row must become excluded.
2. Display excluded rows and click **Revive**. Confirm stays disabled for a blank reason. **Cancel** must leave the row excluded.
3. Open **Revive** again, provide a new synthetic reason and confirm. The dialog closes and that row returns to Cash on Hand with one success notification. This also exercises real widget bindings and SDK refresh behavior that VM tests cannot establish.

Return only script exit code and this scenario's pass/fail or error class. Do not send operational contacts, amounts, screenshots, account values or detailed audit contents. Role denial, malformed reasons, direct calls, audit rollback, active-batch conflicts, double clicks and refresh failures have automatic coverage and need no manual repetition in this increment.

## Appsmith synchronization finding

The live post-pull system commit `f412b81` changed 24 guarded read/API actions from Manual to Automatic while retaining `userSetOnLoad: false`. Other synchronized SQL changes were whitespace only and are preserved. The development increment was rebased onto that commit rather than replacing it.

The official [v2.4.2 on-load implementation](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/server/appsmith-server/src/main/java/com/appsmith/server/onload/internal/OnLoadExecutablesUtilCEImpl.java) recalculates modes for actions whose `userSetOnLoad` is false, and respects an explicit Manual/true choice. The [run-behavior setter](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/server/appsmith-server/src/main/java/com/appsmith/server/services/ce/LayoutActionServiceCEImpl.java) uses that same true flag for a user's deliberate choice. The repaired metadata applies this contract to the observed actions, including bank/inventory APIs, and the new reconciliation writes/controllers. This is source evidence; the agent should inspect the next post-pull synchronization commit for persistence rather than asking the operator to audit every setting.
