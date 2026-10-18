# Test confidence and operator workload

High confidence applies to the behavior and environment actually exercised. It is not a percentage or certification of the entire release. Reuse passing evidence when the relevant code and prerequisites are unchanged. Each increment should request only consequential runtime gaps, normally one to three focused operator scenarios. Existing source/SQL checks supply regression coverage; a new browser harness is deferred beyond this release.

| Behavior | Evidence | Confidence and remaining scope | Manual request |
| --- | --- | --- | --- |
| Canonical roles, Participant self-read and denied writes | Actual source-query tests; `verify_application_authorization.sql`; operator's successful test migration twice and checks at backend `26531cf` | High for tested SQL/resource invariants. Operator also reports reasonable practitioner/reviewer boundaries and expected Participant restrictions | No repeat of the full role matrix for this increment |
| Denied-page navigation and Contributor choice labels | Source/controller checks plus operator confirmation | High for the reported development UI behavior | No repeat |
| Intake email validation | Synthetic valid/invalid/blank controller fixtures plus operator confirmation | High for the practical email formats exercised | No repeat |
| Cash lifecycle, totals, print/tally, immutable confirmation and correction | Isolated canonical SQL suite; operator's successful PostgreSQL test correction verification | High for covered SQL invariants; deployed ERP delivery remains separate | Do not repeat backend cases manually |
| Reason-aware revival and audit atomicity | New rollback-only SQL checks: blank/legacy calls, unauthorized reviewer, unchanged donation, exact cash restoration, original/new rationale, repeat/missing/ineligible/active-batch denial and audit-failure rollback | High in the isolated canonical database; operator PostgreSQL 16.13 test migration/reapplication/rollback checks pass at 50f4650; final dialog Exclude/Revive is accepted | No repeat |
| Explicit action execution modes | Observed Appsmith sync `f412b81` changed 24 guarded actions from Manual to Automatic; source-mode regression checks and official v2.4.2 server contract | Explicit Manual choices are now pinned with `userSetOnLoad: true`. Source-level confidence is high; persistence through the next live pull must be inspected | Agent checks the next synchronized repository commit; no per-action manual inspection requested |
| New reconciliation dialog controller | VM checks for exact row/mode, no write on open/cancel/blank reason, fresh authority/account, double click, write failure and committed-refresh warning; actual prepared source SQL; registration/export checks | High for covered controller contracts; operator accepted final dialog rendering and revival | No repeat |
| Reports categories and financial guards | Actual source-query fixtures for all six groups and boundary cases; source/controller tests | High for covered query math and authorization. Deployed rendering has less evidence | A final candidate smoke check only if a reporting dependency changes or UI/runtime errors appear |
| Paper upload, Documenso, Listmonk, inventory HTTP and ERP/bank routes | Source review and isolated logic do not establish deployed destination, credentials, caller authorization or side effects | Integration acceptance remains open; development paper upload stays disabled | Defer targeted synthetic route checks until a reviewed test destination is available |
| Production upgrade and recovery | Fresh bootstrap cannot establish behavior on existing production data, owners or grants | Protected restored-copy rehearsal and ordered manifest remain required | One controlled deployment/recovery sequence in its release phase |

## Accepted operator evidence

The operator reports `Permission validation exit code: 0` after pulling backend `26531cf`. The supplied sequence used `ON_ERROR_STOP` and `set -e` for both authorization migration applications, authorization verification and confirmed-date correction verification. Detailed logs were not supplied; no private records or configuration are copied into Git. This is accepted operator execution evidence, not an independent log inspection.

The operator confirms retained navigation on denied pages, clear Contributor choices, generally reasonable practitioner/reviewer permissions, expected Participant-only restrictions and fixed Intake email validation. These observations do not certify every external endpoint or every combined-role scenario. They remove the need to repeat the same broad manual smoke checklist.

## Current operator request

All-page navigation and the three-table presentation plus completion/reload/reset sequence are accepted in deployed development. Reload clearing form fields while retaining the completion notice/disabled button is correct; Reset clears the persistent guard. Do not repeat these unchanged tests.

The active Intake API now provides database atomicity and durable owner/key/payload replay, with read-only receipt recovery. Source/controller/four disposable-SQL suites pass: 24 supported intakes, 14 complete server rollback/retry boundaries, eight atomic request/lost-response cases, account/owner/payload isolation and signing no-replay. Native Select captions, Directory Participant/Contributor buttons and profile text have default/alternate/legacy configuration checks; the read-only terminology table covers active and reserved concepts. Candidate preservation retains 18 pages, 514 actions, 32 collections, four datasource descriptors and one library.

Use [ATOMIC_INTAKE_AND_TERMINOLOGY_VALIDATION.md](ATOMIC_INTAKE_AND_TERMINOLOGY_VALIDATION.md): apply the new API to test before frontend pull, explicitly adopt Participant presentation if the installed member key still says Member, then one synthetic Contributor-only Intake/receipt observation and the reported captions/table during ordinary navigation. No broad role/contact/cash matrix, deliberately failed live signing route or production operation is requested. The agent checks the next native Git synchronization rather than asking for per-action inspection.

Real multi-session locking, PostgreSQL 16 owners/grants/restored upgrade, native SDK and external delivery remain separate gates. The historical evidence below supplies no extra current manual request.

## Appsmith synchronization finding

The live post-pull system commit `f412b81` changed 24 guarded read/API actions from Manual to Automatic while retaining `userSetOnLoad: false`. Other synchronized SQL changes were whitespace only and are preserved. The development increment was rebased onto that commit rather than replacing it.

The official [v2.4.2 on-load implementation](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/server/appsmith-server/src/main/java/com/appsmith/server/onload/internal/OnLoadExecutablesUtilCEImpl.java) recalculates modes for actions whose `userSetOnLoad` is false, and respects an explicit Manual/true choice. The [run-behavior setter](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/server/appsmith-server/src/main/java/com/appsmith/server/services/ce/LayoutActionServiceCEImpl.java) uses that same true flag for a user's deliberate choice. The repaired metadata applies this contract to the observed actions, including bank/inventory APIs, and the new reconciliation writes/controllers. This is source evidence; the agent should inspect the next post-pull synchronization commit for persistence rather than asking the operator to audit every setting.

## Provider increment

[PROVIDER_REVIEW_VALIDATION.md](PROVIDER_REVIEW_VALIDATION.md) records high-confidence source/SQL/controller coverage and one remaining live reassignment-dialog scenario. Its test-only runner includes the unreported preceding cash increment, so operator work remains one automated command. Previous confirmations are reused; no full role/email/negative-case matrix is requested. New provider creation/resolution, role and ambiguity/conflict cases are exercised automatically. Fresh SQL evidence does not replace protected restore or deployed execution-principal/external-service authentication review.

## Accepted directory and workflow checkpoint

Operator reports directory-review runner exit 0 at `8a08e74` and final cash Exclude/reveal/reason/Revive success. Initial Cash access required Retry, but the later opening passed without Retry. Terminology opens after Retry; first-load reliability remains open. The read-only observation and SDK gaps below qualify these results.

Controller/prepared-SQL Intake tests cover 24 enrollment/contact/consent cases. Signing and ERP HTTP remain stubs in automatic checks; queue creation does not prove external Listmonk completion. Earlier cash pending-review observation, multi-action recovery, live delivery and restored-production rehearsal remain open.

The retained legacy Members–Intake page also blocks paper selection before any identity write. Its upload execution code is removed and paper controls are disabled. Its digital stage messages remain available; no external upload request is made. The pre-write boundary and disabled controls are exercised automatically.


## Operator checkpoint at 93b2082

Read-only cash observation exit 0 on `signaturegate_test`: both Intake APIs exist, the latest exclusion concerns a verified donation and is still active, and the two most recent exclusions are for different donations. No intervening verification was found for the earlier of those two records. This does not establish which row was selected in the earlier UI report and does not prove a same-donation status regression. Preserve the unresolved display/history observation for consolidated acceptance; no repeat exclusion is requested.

Cash Deposits opens without Retry. Terminology Administration opens with the authorized form after Retry Access; permission is correct, but first-load reliability is not yet accepted. The controller now retries one failed terminology-data read separately from the access read, keeps the form closed until labels load, and distinguishes data failure from denied access. Source tests cover cold/persistent label failure and account change during loading; the live root cause remains unproven.

The operator will navigate interfaces independently. This walkthrough does not block independent development. Reuse passing backend and dialog evidence; no migration or new service request is introduced by this checkpoint.


## Phase 3: selected-profile entry

Individual/Company profiles are hidden from direct native navigation. Directory opens them with an explicit person/company UUID. A link with no ID never reuses an old stored selection; malformed/inaccessible links show a safe message and Back to Directory. Loaders are explicitly on page load, use current-account/route tokens, retry one failed primary read and leave content hidden until dependent reads finish. Stale primary responses and account/route changes fail closed in the covered controller cases. Overlapping secondary-query data and real SDK lifecycle behavior still require runtime acceptance. Profile DB actions are pinned Manual/true and run after the selected primary record is resolved; existing signed SQL/resource guards remain.

Controller fixtures cover valid/missing/invalid/access-denied links, saved-selection refusal, cold/secondary read failures, route/account changes and late A-to-B primary responses. Company relationship regressions and exact-source export preservation pass. Real Appsmith dependency/SDK rendering remains a consolidated acceptance check; use the operator's forthcoming walkthrough, not another full role/identity matrix. No DB migration or permission grant is introduced.


## Navigation/Participant successor sequence

Use NAVIGATION_AND_PARTICIPANT_VALIDATION.md: one test-only configuration/rollback command and the existing operator walkthrough. High confidence applies to canonical menu SQL, generated 18-page dispositions, role/account cases, stable routes, alternate/colliding labels and profile controller isolation. Native keyboard/mobile/rendering and Git pull persistence still need targeted observation. No new browser harness, extra service request or broad role/contact/cash regression matrix is requested.


## Phase 4 source/runtime preflight increment

All 175 audited bare-field empty-table fallbacks were repaired. Actual empty-vector tests identified nine additional out-of-scope currentRow fallbacks and ten null scalar fallbacks; all 194 affected columns now return arrays without evaluating a row when empty. Tests exercise 225 mapped empty columns and 215 direct column vectors with null/text/number/boolean rows. Populated mapping code is preserved. Menu visibility is now always boolean when actor data is unavailable, and role/cache cases assert the property types.

The unused Individual Profile upload action referenced a nonexistent FilePickerIndividualAgreement. No controller/widget invoked it; the dormant unvalidated action is retired. Enabled workflows are unchanged and paper remains blocked pending integration validation. The source auditor now accepts legal comments before export default and records the current source revisions/worktree state rather than a hard-coded initial revision. These are checked-pattern source results, not certification of all live Appsmith lint/runtime or external endpoints.


## Configured workflow copy and safe audit rendering

Static alert prefixes, Intake stage/completion copy and Reports metric labels now consume the shared formatter. Actual record/contact values and route/API identifiers are outside the formatter. Controller tests stub that presentation boundary for independent behavior checks; the 24 actual-SQL Intake cases also exercise the real alternate-label helper (Attendee/Guide/Sponsor) without changing role keys or saved identities.

Audit details render configured Participant/practitioner headings while preserving stored record wording. All dynamic display values are HTML-escaped, only HTTP(S) links without embedded credentials/control characters are emitted, path IDs are encoded and new-window links use noopener/noreferrer. Malformed detail JSON, null attachment entries and unsafe URLs receive safe text outcomes. Synthetic rendering tests cover these cases without an external request. Remaining dynamic/template/service/document captions are still a release inventory/runtime gate; executed documents are untouched.
