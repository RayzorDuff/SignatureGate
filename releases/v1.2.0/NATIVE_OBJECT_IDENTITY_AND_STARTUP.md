# Native object recreation and Directory startup

## Accepted navigation checkpoint

October 18: the operator reports navigation working correctly across all pages. This supersedes the failures and startup instructions below. No further object recreation, Console repair or navigation matrix is requested. New table presentation/Intake work is covered in [PRESENTATION_AND_INTAKE_RECOVERY.md](PRESENTATION_AND_INTAKE_RECOVERY.md).

## Historical Copy to Page checkpoint

The operator now accepts Directory, including its navigation. Other pages remain at Checking page access after their navigation objects were replaced using Appsmith Copy to Page. Native checkpoint `d62bc8da2c1c1d4611f937bdcc66fa64f00fff3e` preserves Directory's On-page-load initializer but records **all 17 destination initializers as Manual/false**. [Mode comparison](evidence/navigation_startup_modes.csv) records each page without operational data. These are Git metadata flags, not an inference from the public DTO's omitted explicit-user field.

Correction [Appsmith `7c7032f`](https://github.com/RayzorDuff/SignatureGate-Appsmith/commit/7c7032f1821280b343d6a7248e0adde7dec59e98) restores the 17 initializer registrations through the identity-preserving generator. All 540 current resource identities match the operator's copy checkpoint. The 85 function-metadata changes explicitly retain Manual for presentation helpers and On page load for initialize; no widget, function body, query body or datasource is changed. The generation regression now resets every destination initializer to Manual before checking restoration and identity preservation.

Appsmith's [copy saga](https://github.com/appsmithorg/appsmith/blob/834c591b7ba97c38b44539cefdbbc5bd7ad39328/app/client/src/ce/sagas/JSActionSagas.ts) posts newly identified functions. The [creation path](https://github.com/appsmithorg/appsmith/blob/834c591b7ba97c38b44539cefdbbc5bd7ad39328/app/server/appsmith-server/src/main/java/com/appsmith/server/services/ce/LayoutActionServiceCEImpl.java) explicitly defaults new actions to Manual outside the page-clone event. This matches the observed checkpoint; native object copying does not establish startup-setting preservation.

All 32 declared startup methods across 18 pages pass source/controller checks; capability menus, identity/default/reapplication tests, 32 collection/795 expression syntax checks, 231 literal routes and private candidate preservation (18 pages/508 actions/32 collections/four datasources/one JS library) pass. Directory's live result is accepted. The corrected other-page editor/deployed schedules are not yet accepted.

The follow-up [Appsmith `3743789`](https://github.com/RayzorDuff/SignatureGate-Appsmith/commit/3743789c7b26ebe7f2549defea228393a259bf94) also repairs two bare empty-column fallbacks reintroduced in the native Contributors table. Its existing regression passes 227 mapped-column and 217 typed-vector cases; no additional manual test is requested. This latest checkpoint includes the startup correction.

## Earlier recreation finding

The operator reports that recreating the Directory JS object made page-load settings stick and fixed automatic Directory table loading. Navigation still starts with only People and Organizations, and other pages still have access/startup problems. Accept the table result; do not infer that the remaining pages passed.

## Synchronized source finding and correction

Appsmith checkpoint `3763b0a98f2fcb0faf3d35931ab23bd042dba3e3` recreates both Directory JS collections and their functions with new sync identities. Its saved modes are:

| Function | Mode in that checkpoint | Corrected mode |
| --- | --- | --- |
| `directoryFlows.load` | On page load | Preserved |
| `navigationLabels.initialize` | Manual | On page load, explicitly selected |
| `navigationLabels.label` | On page load | Manual; presentation helper |

This is the synchronized checkpoint, not a claim that newer unsynchronized editor changes cannot exist. The saved initializer mode explains why no automatic menu authority read is requested from that source. The formatter must not replace the initializer as a startup hook.

Development correction: [SignatureGate-Appsmith `4b1f56f`](https://github.com/RayzorDuff/SignatureGate-Appsmith/commit/4b1f56fb1fcffc78825b3548cac298ddb9fa08a9).

The generator previously replaced existing sync identities with generated name strings. This is a confirmed source-tooling defect: regeneration would undo the operator's recreation identities. It now preserves all **540 existing action/collection sync identities**, retains native metadata extensions/default arguments and current-page title geometry, and rejects duplicate/missing identities before writing. Only new resources receive fresh UUID-based identities, persisted once. Native JSON normalization alone no longer rewrites files. No duplicate action/collection sync IDs were found in this tracked checkpoint; a runtime stored-object association defect remains a hypothesis, not a proven duplicate-ID root cause. Existing identities on other pages are not rotated speculatively.

The native checkpoint restores `isAsync` metadata on other pages; it is retained without making that deprecated field an acceptance requirement. The recreated and now-working Directory loader omits per-function async/client-side flags. The source dispatch test now accepts that observed native representation, while still requiring the actual async source method and correct collection/function registration.

## Automatic evidence and limits

- `python3 tests/navigation-generation.py`: reproduces the Manual initializer/On-page-load formatter checkpoint, corrects the intended hook without replacing identities, retains native argument defaults/extensions/title size, verifies byte-stable reapplication, one-time new-resource identities and duplicate rejection.
- All 540 sync identities compare unchanged against the operator's synchronized checkpoint. Generator `--check` and 32 actual async startup declarations pass.
- Controller fixtures dispatch the 32 declared startup functions across 18 pages; navigation capability/account cases, 32 collection/793 expression syntax checks and 231 literal routes pass. These do not run Appsmith's server scheduler.
- A private generated candidate preserves 18 pages, 508 actions, 32 collections, four datasource descriptors and one JS library. The shipped Appsmith JSON is unchanged. Source fingerprints are refreshed; live import/startup/access remain open.

## Superseded operator sequence (historical only)

1. Pull Appsmith `chatgpt_development` through `3743789` (includes `7c7032f`). Existing copied IDs and synchronized UI changes are preserved. Commit any newer editor-only changes before pulling rather than discarding them.
2. Open **Terminology Administration in the editor**, reload once and do not click Refresh/Retry. Report whether its authorized form and navigation groups appear. No Directory or broad role-matrix retest is requested.
3. Only if the editor passes, use the normal Appsmith Deploy workflow **while chatgpt_development remains selected**, then reopen that same page in the deployed development app with `branch=chatgpt_development`. Report pass/fail separately for editor and deployed view. This is development publication/validation, not master or production promotion. If the editor fails, stop before deployment and return its current-page access message only.

The saved editor and deployed view have separate startup schedules; a source pull alone must not be reported as deployed acceptance. No further JS-object recreation, Console repair, SQL command or role change is requested. The shipped Appsmith JSON, production datasource, master branch, release version and tags remain unchanged.
