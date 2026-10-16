# Directory server startup schedule repair

## Observed failure

On October 15 the operator returned the version 2 diagnostic from `chatgpt_development` Directory. Both editor and published configurations returned HTTP 200 with **zero scheduled actions, zero on-load errors and no navigation initializer**. The original startup request was observed and no action-execution request followed it. The two repeated summaries agree. [The projected evidence](evidence/served_directory_startup.json) contains technical names, counts and flags only; the full Console attachment remains private.

This establishes an empty served **Directory** schedule, not the installed state of every other page or the precise reason registration was lost. Source declarations alone are not acceptance evidence. Do not repeat the role or database migration tests.

Appsmith 2.4.2 intentionally excludes the computed schedule from native Git serialization (`Layout.layoutOnLoadActions` has Public/Export views, not Git). It rebuilds layouts in its application import post-hook. That post-hook logs and continues after a layout update failure. Consequently, neither adding computed schedules to native Git nor treating a successful pull as a scheduler pass is appropriate.

Its native `setRunBehaviour` operation saves the function's explicit mode and **updates the containing page layout even if the supplied mode was already selected**. The bounded repair below uses that path for the two existing Directory functions. It also reads their actual installed modes, helping distinguish missing/stale declarations from a stale computed schedule. It does not assume which of those caused this failure.

## One development repair and observation

1. Open Directory on `chatgpt_development`. Paste [rebuild_directory_startup.js](rebuild_directory_startup.js) into Chrome Console and run **once**. This is a configuration repair, not the preceding read-only inspection: it sets `navigationLabels.initialize` and `directoryFlows.load` to run on page load through Appsmith's native API. The entire two-function identity allowlist is checked before the first write. Missing/ambiguous functions stop the repair; it does not create functions or guess IDs.
2. Return the small JSON result. Expected success is `status: "editor_schedule_rebuilt"`, with `after.navigation_registered: true`, `after.directory_registered: true` and `after.error_count: 0`. Before/after mode/count metadata is safe to return. Do not return raw API responses or the JS collections.
3. **Only if that succeeds:** open Directory in Appsmith's editor (pencil icon), reload once and check whether its table and authorized menus load without Refresh or Refresh access. Report pass/fail only. This observes the repaired editor schedule; the published app is unchanged until an explicit development deployment. Do not deploy, promote or repeat the other page tests yet.

If the result is stopped/blocked, return it and stop this sequence. `attempted_functions` distinguishes an attempted setting from a confirmed `updated_functions` response; a failed response does not prove that the setting was not saved. The script never automatically retries a write. A 403 concerns Appsmith editor permissions; it is not grounds to grant a SignatureGate database role. Existing Escape/Directory navigation remains available.

The static-URL path reads the normal view-bootstrap response privately to obtain the current page ID; that platform endpoint may apply normal Appsmith DSL migrations, as a regular reload does. All direct page reads request `migrateDsl=false`. The repair changes only the two development function run settings and the server's computed editor layout. It invokes no application SQL/actions, integration, deployment or release operation and changes no function bodies, datasource, role or operational record. Any settings diff should later be preserved through the normal Appsmith Git workflow before broader development sync; no Appsmith source commit is asserted here.

## Verification scope

`node scripts/test_directory_startup_rebuild.mjs` exercises synthetic API responses: the exact two-setting allowlist, unchanged-mode rebuild, all pre-write identity/plugin/function guards, wrong branch, denied reads, partial save failure without retry, response identity mismatch, remaining scheduler errors, ID/static/legacy routes and private-field omission. `node scripts/test_appsmith_startup_inspection.mjs` verifies the existing reader. These checks do not execute the deployed Appsmith server. Runtime repair and cold Directory acceptance remain pending the operator result; remaining pages are still open.

Official v2.4.2 contracts:

- [Native run-behaviour API](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/server/appsmith-server/src/main/java/com/appsmith/server/controllers/ce/ActionControllerCE.java)
- [Setting save and layout rebuild](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/server/appsmith-server/src/main/java/com/appsmith/server/services/ce/LayoutActionServiceCEImpl.java)
- [JS collection metadata read](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/client/src/ce/api/JSActionAPI.tsx)
- [Computed layout serialization views](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/server/appsmith-server/src/main/java/com/appsmith/server/domains/Layout.java)
- [Import post-hook and tolerated layout failures](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/server/appsmith-server/src/main/java/com/appsmith/server/applications/imports/ApplicationImportServiceCEImpl.java)
