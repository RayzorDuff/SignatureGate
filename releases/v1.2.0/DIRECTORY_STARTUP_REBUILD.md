# Directory server startup schedule repair

## Observed failure

On October 15 the operator returned the version 2 diagnostic from `chatgpt_development` Directory: editor and published configurations both returned HTTP 200 with zero scheduled actions/errors, no navigation initializer and no execution request following the observed startup fetch. [Projected evidence](evidence/served_directory_startup.json) contains only technical metadata; raw Console attachments stay private. This establishes an empty served Directory schedule, not every other page's installed state or why registration was lost.

Appsmith 2.4.2 excludes computed schedules from native Git (`Layout.layoutOnLoadActions` has Public/Export views, not Git). Its application import post-hook rebuilds layouts, but logs and continues after a layout update failure. Neither adding computed schedules to native Git nor treating a successful pull as a scheduler pass is appropriate.

## Repair attempt received October 18

The [projected operator result](evidence/directory_startup_rebuild_attempt.json) stops at the first setting request with HTTP 400. Both installed function modes were reported as ON_PAGE_LOAD; no successful update is confirmed. The helper did not collect the error response body, so the cause of the 400 and whether anything was saved before that response remain unknown. No rebuild or live page acceptance is claimed.

**Correction:** the helper's `before_user_set_on_load: false` values are not evidence of false stored flags. `ActionCE_DTO.userSetOnLoad` has Internal/Git serialization views, not Public. The helper collapsed an omitted value into false and incorrectly required that internal flag in the public save response. Its synthetic success fixtures included a field the real public response omits. Installed run modes are valid observations; the explicit-user flag is unknown. The earlier assertion and inference are withdrawn.

The attachment contains many identical executions within seconds. Repeated evaluation, including Chrome Live Expressions, can repeat an immediately invoked script; the cause of these repeated evaluations is not established. Remove any Live Expression containing either startup script. Do not run the old repair again. Its download path now returns a retirement notice with **zero requests**, even if repeatedly evaluated.

## Next bounded native editor sequence

No replacement Console write script, migration, role grant or broad UI matrix is requested.

1. Open development **Directory** using the pencil icon. Confirm Appsmith's selected branch is `chatgpt_development`.
2. Open JS object **navigationLabels → Settings**. For **initialize**, select **Manual**, wait for the setting save, then select **On page load** and wait for that save. If either save reports an error, stop immediately and return only its software error code/message, omitting record/contact data. Do not attempt the second function or reload after a failed save.
3. If those saves succeed, open **directoryFlows → Settings** and do the same for **load**. Do not click Run.
4. If all saves succeed, reload **Directory in the editor** once. Report whether its authorized menus and table load without Refresh/Refresh access. Do not deploy/publish or repeat other pages yet.

If On page load is unavailable, report the visible software choices rather than substituting another mode. The native editor uses the installed client request contract. Its setting handler saves explicit run behaviour and rebuilds the containing page layout. This tests that native path without claiming an identified cause for the prior 400. Successful saves alone do not establish a working cold page: the final editor observation is required.

The sequence changes the two development run settings and derived editor configuration. No database commands, role changes, function-body edits or datasource changes are needed. Do not pull over the resulting editor changes; preserve any settings diff through Appsmith Git after the focused check and before later source synchronization. Published/deployed acceptance is separate.

## Verification scope

`node scripts/test_directory_startup_rebuild.mjs` checks the retired download under 100 evaluations: zero requests and no browser/application-state access. Previous synthetic API passes are historical and superseded by the failed installed request and corrected public-response contract. `node scripts/test_appsmith_startup_inspection.mjs` retains the existing read-only inspector coverage. Live startup repair remains unaccepted.

Official v2.4.2 contracts (tag independently resolves to `834c591b7ba97c38b44539cefdbbc5bd7ad39328`):

- [Internal/Git-only explicit-user flag](https://github.com/appsmithorg/appsmith/blob/834c591b7ba97c38b44539cefdbbc5bd7ad39328/app/server/appsmith-interfaces/src/main/java/com/appsmith/external/models/ce/ActionCE_DTO.java)
- [Native client run-behaviour request](https://github.com/appsmithorg/appsmith/blob/834c591b7ba97c38b44539cefdbbc5bd7ad39328/app/client/src/api/ActionAPI.tsx)
- [Native function settings](https://github.com/appsmithorg/appsmith/blob/834c591b7ba97c38b44539cefdbbc5bd7ad39328/app/client/src/pages/Editor/JSEditor/JSEditorToolbar/components/JSFunctionSettings.tsx)
- [Setting save and layout rebuild](https://github.com/appsmithorg/appsmith/blob/834c591b7ba97c38b44539cefdbbc5bd7ad39328/app/server/appsmith-server/src/main/java/com/appsmith/server/services/ce/LayoutActionServiceCEImpl.java)
- [Layout serialization views](https://github.com/appsmithorg/appsmith/blob/834c591b7ba97c38b44539cefdbbc5bd7ad39328/app/server/appsmith-server/src/main/java/com/appsmith/server/domains/Layout.java)
- [Import post-hook and tolerated layout failures](https://github.com/appsmithorg/appsmith/blob/834c591b7ba97c38b44539cefdbbc5bd7ad39328/app/server/appsmith-server/src/main/java/com/appsmith/server/applications/imports/ApplicationImportServiceCEImpl.java)
