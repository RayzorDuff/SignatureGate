# Actual Appsmith startup schedule inspection

**Result received October 15:** version 2 confirms empty Directory schedules in editor and published mode, with no reported cycle. See [DIRECTORY_STARTUP_REBUILD.md](DIRECTORY_STARTUP_REBUILD.md) for the failed API attempt and subsequent recreation. The current next step is [NATIVE_OBJECT_IDENTITY_AND_STARTUP.md](NATIVE_OBJECT_IDENTITY_AND_STARTUP.md); no repeat inspection or Console write is requested.

On October 14, the operator reports essentially unchanged startup symptoms after the `ec6fdc4` repair. **Cold startup remains failed.** No further broad interface walkthrough or role grant is requested. Synthetic controller/registration passes do not certify the deployed scheduler.

The October 15 operator attachment contains repeated **No page metadata request was found** errors from the original inspector, not a served-schedule report. This is a diagnostic failure; it does not establish absent hooks, denied roles or a cyclic schedule. The console's draft/performance warning does not establish the cause of the application failure either. Raw console output remains private.

Version 2 of [inspect_appsmith_startup.js](inspect_appsmith_startup.js) supports Appsmith 2.4.2's static URLs and combined first-load response. It no longer requires a separate page request in Resource Timing. For an ID-based URL it reads editor/view metadata directly. For a static URL it reads the regular **view bootstrap**, projects its published page schedule, then reads that page's editor metadata. Both paths use at most two same-origin GETs with `chatgpt_development` pinned. No application action, SQL query or integration operation is invoked.

The combined response includes broader Appsmith configuration and the signed-in user profile; none is printed or retained. Only known page/controller names, counts, availability and error flags are projected. The normal view-bootstrap endpoint uses Appsmith's own DSL migration path, just as a normal reload does; this is not a guarantee of zero platform metadata changes. Direct page reads explicitly pass `migrateDsl=false`. The script does not call the combined **edit** endpoint. No raw DSL, bodies, cookies, account identifiers, URLs or record/query results belong in returned evidence.

## One operator sequence

1. Open **Directory** in the `chatgpt_development` Appsmith app and reload. Do not click Refresh or Refresh access.
2. Open Chrome's JavaScript Console (on Mac: Option–Command–J). Paste the complete contents of `inspect_appsmith_startup.js` and run it.
3. Return only the JSON summary printed by the script. Do not send a network archive or complete API responses.

To copy the script on the Mac after pulling SignatureGate:

```bash
cd ~/GitHub/SignatureGate
git pull --ff-only
pbcopy < releases/v1.2.0/inspect_appsmith_startup.js
```

Alternatively, open the committed script and copy its contents. The script refuses other branches, resolves the current URL without printing it and blocks redirected fetches. Confirm the returned JSON includes `diagnostic_version: 2`. Missing timing history is now supported: `startup_request_observed: false` and a **null** action-request count mean the original transport history is unavailable, not that no action ran. Do not repeatedly run the old script or repeat the role matrix. A 403 on the editor request is recorded as unavailable; it does not require changing roles or sharing credentials.

## How the result narrows the fault

| Result | What it establishes |
| --- | --- |
| Editor includes `navigationLabels.initialize`, published view omits it | Served startup schedules differ; inspect development publication state before changing controllers again. A branch URL alone does not prove the published schedule matches the pulled source |
| Both schedules omit the initializer | The declared source hook did not become a served startup hook; inspect Git reconstruction/layout scheduling |
| A cyclic dependency flag is true | Appsmith reported a scheduling dependency error; identify its software action/widget names from the debugger before repairing that dependency |
| Published initializer exists, no cycle flag, observed startup request and zero action-execution requests | The schedule is present but plugin reads were not observed; investigate client dispatch/JS execution. The transport count is a clue, not proof that a particular controller ran |
| Reads are observed but access/data remain absent | Investigate the first startup read/SDK error. No private query results are needed to begin that review |

The diagnostic is tested with synthetic static combined responses, ID/UUID/custom/legacy routes, absent timing history, unrelated/foreign requests, editor/view drift, matching schedules, cycle reports, 403/network failures, invalid identities, wrong branches and private fields embedded in bootstrap/API fixtures. These checks verify the reader and its projection, not the live startup scheduler. Version 2 subsequently ran on the operator's installation and returned the Directory result recorded above.

The relevant platform contracts are [static route patterns](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/client/src/ce/constants/routes/appRoutes.ts), [combined startup parameters and response](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/client/src/sagas/InitSagas.ts), [combined GET URLs](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/client/src/api/services/ConsolidatedPageLoadApi/url.ts) and [direct metadata GETs](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/server/appsmith-server/src/main/java/com/appsmith/server/controllers/ce/PageControllerCE.java).

## Corrected Git representation assumption

The [v2.4.2 Git serializer](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/server/appsmith-server/src/main/java/com/appsmith/server/helpers/ce/CommonGitFileUtilsCE.java) intentionally removes individual JS action bodies. The JS object source is serialized separately. [ActionConfiguration](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/server/appsmith-interfaces/src/main/java/com/appsmith/external/models/ActionConfiguration.java) marks `isAsync` deprecated and says not to use it. Missing per-function body/async metadata was therefore an invalid standalone failure diagnosis in the prior increment. Redundant bodies/deprecated fields and acceptance assertions are removed; the source checker now validates declaration identity and the actual async source method. The failed deployed result remains authoritative.

No database schema/configuration, roles, production datasource, master promotion, operational records or release tag is changed by this inspection.
