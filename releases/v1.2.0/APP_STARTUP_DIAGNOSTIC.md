# Actual Appsmith startup schedule inspection

On October 14, the operator reports essentially unchanged startup symptoms after the `ec6fdc4` repair. **Cold startup remains failed.** No further broad interface walkthrough or role grant is requested. Synthetic controller/registration passes do not certify the deployed scheduler.

The next evidence is the page configuration Appsmith actually serves, rather than another source-based prediction. [inspect_appsmith_startup.js](inspect_appsmith_startup.js) reads the current development page's editor and published-view metadata with two same-origin GETs. It preserves the `chatgpt_development` branch header, requests no DSL migration, executes no action/query and prints only known page/controller names, schedule counts, HTTP availability, cyclic-error flags and a transport request count. It omits page DSL, function bodies, cookies, request bodies and record/query results. Logs remain private unless this projected summary is returned.

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

Alternatively, open the committed script and copy its contents. The script refuses other branches and only reads page metadata endpoints observed in the current tab. If it reports no observed request, reload Directory and run it before other navigation. A 403 on the editor request is recorded as unavailable; it does not require changing roles or sharing credentials.

## How the result narrows the fault

| Result | What it establishes |
| --- | --- |
| Editor includes `navigationLabels.initialize`, published view omits it | Served startup schedules differ; inspect development publication state before changing controllers again. A branch URL alone does not prove the published schedule matches the pulled source |
| Both schedules omit the initializer | The declared source hook did not become a served startup hook; inspect Git reconstruction/layout scheduling |
| A cyclic dependency flag is true | Appsmith reported a scheduling dependency error; identify its software action/widget names from the debugger before repairing that dependency |
| Published initializer exists, no cycle flag, zero action-execution requests | The schedule is present but plugin reads were not observed; investigate client dispatch/JS execution. The transport count is a clue, not proof that a particular controller ran |
| Reads are observed but access/data remain absent | Investigate the first startup read/SDK error. No private query results are needed to begin that review |

The diagnostic is tested with synthetic editor/view drift, matching schedules, cycle reports, 403 responses, wrong branches, unobserved pages and private fields embedded in API fixtures. Its projection excludes those private fields. It has not yet run against the operator's Appsmith installation.

## Corrected Git representation assumption

The [v2.4.2 Git serializer](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/server/appsmith-server/src/main/java/com/appsmith/server/helpers/ce/CommonGitFileUtilsCE.java) intentionally removes individual JS action bodies. The JS object source is serialized separately. [ActionConfiguration](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/server/appsmith-interfaces/src/main/java/com/appsmith/external/models/ActionConfiguration.java) marks `isAsync` deprecated and says not to use it. Missing per-function body/async metadata was therefore an invalid standalone failure diagnosis in the prior increment. Redundant bodies/deprecated fields and acceptance assertions are removed; the source checker now validates declaration identity and the actual async source method. The failed deployed result remains authoritative.

No database schema/configuration, roles, production datasource, master promotion, operational records or release tag is changed by this inspection.
