# Directory server startup schedule repair

## Observed failure

On October 15 the operator returned the version 2 diagnostic from `chatgpt_development` Directory: editor and published configurations both returned HTTP 200 with zero scheduled actions/errors, no navigation initializer and no execution request following the observed startup fetch. [Projected evidence](evidence/served_directory_startup.json) contains only technical metadata; raw Console attachments stay private. This establishes an empty served Directory schedule, not every other page's installed state or why registration was lost.

Appsmith 2.4.2 excludes computed schedules from native Git (`Layout.layoutOnLoadActions` has Public/Export views, not Git). Its application import post-hook rebuilds layouts, but logs and continues after a layout update failure. Neither adding computed schedules to native Git nor treating a successful pull as a scheduler pass is appropriate.

## Repair attempt received October 18

The [projected operator result](evidence/directory_startup_rebuild_attempt.json) stops at the first setting request with HTTP 400. Both installed function modes were reported as ON_PAGE_LOAD; no successful update is confirmed. The helper did not collect the error response body, so the cause of the 400 and whether anything was saved before that response remain unknown. No rebuild or live page acceptance is claimed.

**Correction:** the helper's `before_user_set_on_load: false` values are not evidence of false stored flags. `ActionCE_DTO.userSetOnLoad` has Internal/Git serialization views, not Public. The helper collapsed an omitted value into false and incorrectly required that internal flag in the public save response. Its synthetic success fixtures included a field the real public response omits. Installed run modes are valid observations; the explicit-user flag is unknown. The earlier assertion and inference are withdrawn.

The attachment contains many identical executions within seconds. Repeated evaluation, including Chrome Live Expressions, can repeat an immediately invoked script; the cause of these repeated evaluations is not established. Remove any Live Expression containing either startup script. Do not run the old repair again. Its download path now returns a retirement notice with **zero requests**, even if repeatedly evaluated.

## Superseding operator result and next step

The operator subsequently recreated the Directory objects and reports automatic table loading works, while navigation and other pages still fail. Appsmith synchronized that work at 3763b0a. [NATIVE_OBJECT_IDENTITY_AND_STARTUP.md](NATIVE_OBJECT_IDENTITY_AND_STARTUP.md) records the actual saved-mode mismatch and the identity-preserving source correction. Its focused development pull/reload sequence supersedes the previous native-setting toggles. Do not repeat the retired Console repair or delete the objects again.

## Verification scope

`node scripts/test_directory_startup_rebuild.mjs` checks the retired download under 100 evaluations: zero requests and no browser/application-state access. Previous synthetic API passes are historical and superseded by the failed installed request and corrected public-response contract. `node scripts/test_appsmith_startup_inspection.mjs` retains the existing read-only inspector coverage. Live startup repair remains unaccepted.

Official v2.4.2 contracts (tag independently resolves to `834c591b7ba97c38b44539cefdbbc5bd7ad39328`):

- [Internal/Git-only explicit-user flag](https://github.com/appsmithorg/appsmith/blob/834c591b7ba97c38b44539cefdbbc5bd7ad39328/app/server/appsmith-interfaces/src/main/java/com/appsmith/external/models/ce/ActionCE_DTO.java)
- [Native client run-behaviour request](https://github.com/appsmithorg/appsmith/blob/834c591b7ba97c38b44539cefdbbc5bd7ad39328/app/client/src/api/ActionAPI.tsx)
- [Native function settings](https://github.com/appsmithorg/appsmith/blob/834c591b7ba97c38b44539cefdbbc5bd7ad39328/app/client/src/pages/Editor/JSEditor/JSEditorToolbar/components/JSFunctionSettings.tsx)
- [Setting save and layout rebuild](https://github.com/appsmithorg/appsmith/blob/834c591b7ba97c38b44539cefdbbc5bd7ad39328/app/server/appsmith-server/src/main/java/com/appsmith/server/services/ce/LayoutActionServiceCEImpl.java)
- [Layout serialization views](https://github.com/appsmithorg/appsmith/blob/834c591b7ba97c38b44539cefdbbc5bd7ad39328/app/server/appsmith-server/src/main/java/com/appsmith/server/domains/Layout.java)
- [Import post-hook and tolerated layout failures](https://github.com/appsmithorg/appsmith/blob/834c591b7ba97c38b44539cefdbbc5bd7ad39328/app/server/appsmith-server/src/main/java/com/appsmith/server/applications/imports/ApplicationImportServiceCEImpl.java)
