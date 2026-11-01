# Native startup and deferred agreement follow-up

October 19, 2026. Appsmith development checkpoints: **f409997** restores startup metadata; **0f8452c** repairs Participant agreement selection. These changes are frontend-only and require no Linode SQL or repeat Intake migration.

## Accepted evidence

The operator reports Atomic Intake validation exit code 0 on signaturegate_test after backend 96c5b8b, retirement of legacy Intake, and successful Create agreement later enrollment. Private screenshots show staged progress, completed enrollment and a successful read-only Check saved Intake receipt lookup. Accept those observations without repeating the Intake. Mode-specific final publication provenance remains separate. No operational names, contacts, addresses, record IDs, financial data or screenshots are copied into Git.

## Navigation investigation

The four preceding agent commits were 8b91bf0 (documentation), aca3d48 (CI runner pin), 48090b3 (legacy Intake retirement and menu update) and d65619c (deferred Intake). Their retained navigationLabels JS source and persistent identities were unchanged; the retirement commit removed the legacy People menu item. This comparison does not establish why an earlier installed server stopped scheduling correctly.

After native recreation/copy commits 670c512 and 3405a7d, saved Directory initialize is On Page Load, but all sixteen destination initializers are Manual with userSetOnLoad false. That source state explains why destination startup cannot run automatically. Both latest failed CI runs stop at the navigation-generation check; both PostgreSQL concurrency jobs pass. The earlier retirement CI failure concerned expected-conflict runner bookkeeping and was already fixed by aca3d48; later runs passed.

f409997 restores the existing destination initializers to On Page Load, deliberately pins presentation helpers Manual and restores the initializer timeout. All 85 existing function metadata resources retain their IDs, native fields and collection relationships; no JS body or widget layout changes. The full suite and both jobs in [run 39231514790](https://github.com/RayzorDuff/SignatureGate-Appsmith/actions/runs/39231514790) pass. Generator tests reproduce copied Manual settings and verify identity preservation and byte-stable reapplication. These tests dispatch saved actions in an isolated harness; they do not execute Appsmith's server scheduler.

## Agreement selection

The saved Agreement Type widget was explicitly hidden. The two catalog reads required Document Reviewer, although the page permits assigned practitioners, and template loading raced type loading with widget state taking precedence over explicit query parameters.

0f8452c makes Agreement Type visible to the same staff audience as the template selector, preserving the operator's layout. Both reads use canonical selected-Participant write scope. Types load before templates; a valid selected type is retained, otherwise the first active type is selected. Explicit type parameters take precedence even while the widget renders an old selection. Type changes clear the old template; inactive types/templates are excluded. Empty results and read failures produce distinct feedback. Final template validation rejects a previous type's stale selection. Read-only Participant access grants no agreement management authority.

The actual controller and prepared source SQL run against synthetic canonical-schema fixtures. They cover assigned practitioner and canonical nonmember reviewer, self/unassigned/other-target denial, delayed widget hydration, valid selection retention, inactive/empty catalogs, failure feedback and stale-template rejection. Reading options creates no agreement, audit or external request. The full suite now includes five disposable SQL suites. Both jobs in [run 39232029483](https://github.com/RayzorDuff/SignatureGate-Appsmith/actions/runs/39232029483) pass at exact Appsmith source 0f8452cbf1ae9901e1d328e68664a6771cc5e1d6: application checks and PostgreSQL 16.13 contract/concurrency. Deployed rendering and actual signing delivery are separate acceptance gates.

## Focused native validation

1. Preserve any newer editor work, then pull chatgpt_development through **0f8452c** into the existing test-bound app and use its normal development Deploy. Cold-reload Participant Functions with the existing authorized account; confirm Checking page access clears and permitted navigation appears without Refresh Access. Open one other permitted page and confirm navigation remains available. Do not recreate or copy the JS objects again.
2. On Participant Functions select the existing test Participant. Confirm Agreement Type is visible, choose the intended active type and confirm matching templates populate; changing type clears the old template selection. This check needs no new Intake, signing submission or external email. Digital sending separately requires an active Participant email; deferred Intake legitimately permits phone plus address without email.

Return only pass/fail and editor or deployed-development mode. If startup still stalls, use the existing read-only startup diagnostic and return its projected schedule/flags, without raw DSL, query results or account information. Do not rerun the broad role matrix or individual negative cases already exercised automatically.

## Remaining release work

Phase 1 still needs final published/datasource/effective-definition and integration-principal evidence. Phase 2 retains protected paper delivery, reviewed external signing/mailing/inventory/ERP routes and policy/earlier cash-observation dispositions. Phase 3 now needs the focused native startup/selector acceptance above, plus remaining keyboard/mobile/profile and service/document terminology work. Phase 4 requires protected restored-production rehearsal and installed ownership/grants/history/recovery. Phases 5–7 retain the reviewed ordered manifest, compatible released/deployed RootedOps/workflows, environment promotion, final changelog/export/dependencies and release packaging. No production SQL, datasource switch, master promotion, final export, VERSION bump or tag is part of this increment.
