# Page startup and authority lookup repair

Operator observation on October 13: menu text now renders, but navigation capabilities disappear on page transitions, Directory/Cash require manual Refresh, profiles remain Loading, and role-gated pages display permission messages for a multi-role account. Manual Refresh access resolves menu capabilities. This supports a startup/lifecycle failure; it does not establish missing grants. No supplied operational records, contacts, amounts or screenshots are committed.

Repair source: SignatureGate-Appsmith `ec6fdc43074b2a06e583dffdac57cfd595a52b7c` on `chatgpt_development`. This is not a deployed/published revision.

## Source changes

- One sign-in-aware navigation initializer is explicitly registered on every page. Navigation authority and labels are Manual/true reads invoked after sign-in hydration, not independent Automatic reads against an empty email. There is one retry for a failed authority read, account/route/pass isolation, an explicit lookup-error state and default captions if only terminology lookup fails. Refresh access uses the same initializer.
- All 32 page-load JS registrations now carry their actual async function body, `isAsync: true`, `clientSideExecution: true` and the deliberate on-load choice. A source synchronizer rejects missing/stale registration metadata. Reports access initialization is explicitly on load rather than Manual.
- Existing `qPageAccess`/`qCurrentFacilitator` reads are Manual/true and invoked by initializers after sign-in, preventing an independent early empty-email response from overwriting the current lookup. Agreement Templates, Audit Log and Reports now explicitly read `qPageAccess` as well as their existing actor lookup. The original automatic metadata was insufficient to ensure that a successful page initializer left the display authority loaded.
- Empty or stale authority responses no longer show the generic missing-permission banners. A current-account response with denied capabilities still shows denial. Audit and legacy Intake await their initial refresh. The repeated practitioner wording in Sacrament Release's denied caption is corrected.

No roles, grants, database functions, datasource selection, resource scopes or write authorization are changed. Startup performs existing reads; the explicit cash bank-account read remains part of the existing authorized Cash initializer. No signing, mailing, deposit posting, enrollment or extra record creation is introduced.

Appsmith v2.4.2's [on-load scheduling utility](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/server/appsmith-server/src/main/java/com/appsmith/server/onload/internal/OnLoadExecutablesUtilCEImpl.java), [client page-load dispatcher](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/client/src/sagas/ActionExecution/PluginActionSaga.ts) and [native import fixture](https://github.com/appsmithorg/appsmith/blob/v2.4.2/app/client/cypress/fixtures/ImportApps/JSOnLoadImport.json) inform the registration checks. Their source contracts do not prove the deployed schedule, rule out cyclic dependencies or show which individual defect caused every observed symptom.

## Automatic confidence

`tests/page-startup.mjs` selects actual registered on-load actions, resolves their collection/method identities and awaits them using synthetic query/widget fixtures. All 32 dispatches across 18 pages pass with delayed sign-in, including directory/cash population, fresh page authority, Reports and selected profiles. It also covers empty-response versus denied banners, bounded transient/persistent menu failures, unlinked accounts, default labels and stale route/account completion. Existing permission, workflow, profile, cash, report, agreement-type, terminology and audit regressions pass. Source registration consistency, binding/entry syntax, generated navigation, literal routes and export preservation also pass.

This harness does not execute Appsmith's server scheduler, database permissions or browser SDK. It detects source registration/dispatch gaps that direct controller tests missed. The live issue remains open until the repaired source is pulled and startup observed; missing metadata is a repaired source gap, not a proven sole deployed root cause. Prior migration/role/cash/email evidence is reused.

## Focused operator validation

No Linode SQL or migration command is needed. Preserve editor changes, pull the matching `chatgpt_development` source in Appsmith and reload the test app.

1. Cold-open Directory and do not click Refresh or Refresh access. After startup, permitted workflow groups and the existing accessible directory rows should appear automatically. Open one Individual/Company through its row's View Profile; it must finish loading. A direct profile link without an ID should show the selection message and Back, not remain Loading or reuse an old selection.
2. Navigate to Agreement Templates (or Participant Functions) and then Cash Deposits using that same authorized account. Check first-load access, expected existing content and automatic return of the permitted menus without Refresh. These are read-only observations; do not create records, send agreements or post accounting entries.

Return pass/fail and page/error class only. If startup still needs Refresh, capture the first on-load debugger error message (especially a cyclic dependency, missing collection/action or execution error) and the page name; omit query results, request bodies and identifying values. That evidence will distinguish deployed scheduling/registration failure from a failing read. Do not bootstrap a manager, grant more roles or repeat the full manual matrix.
