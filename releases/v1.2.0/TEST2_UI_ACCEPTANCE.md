# Test2 UI acceptance checkpoint

Updated November 2, 2026. Owner scope clarification: **Additional end-to-end ERPNext synchronization and Google Drive storage acceptance testing is deferred and nonblocking for v1.2.0. Existing functionality must remain intact.** Core deposit confirmation and local/NocoDB agreement intake/review remain required. Production promotion remains on hold. This report contains sanitized release results only.

## Scope and preserved evidence

The existing development application was exercised through its installed Appsmith browser preview using synthetic records and an authorized linked staff account. Results below describe actual interface interactions, not a production deployment or complete integration certification.

The current repository baseline is SignatureGate `main` at `ba7eec08120e82bb97b5034fe6a5d816e2a51705` (merged PR #33) and SignatureGate-Appsmith `chatgpt_development` at `666c9bcaefa6bf22c5683f7819bdbbc55e114482` (merged PR #8). The earlier accepted development baseline `ceb26ff02166d69ed0c64b0c77811f8b22164a67`, including PR #7, remains historical evidence. Narrow inspection confirmed the five PR #8 repair areas remain installed in the development application. Prior successful 47-check PostgreSQL suites, Appsmith CI, and focused former-Participant migration/rollback checks remain accepted historical evidence. They were not repeated. Prior source synchronization and backup checkpoints remain preserved; no synchronization recovery was repeated.

## Configuration results

| Check | Result | Evidence or limit |
| --- | --- | --- |
| Browser navigation and authenticated editor | PASS | Existing development application opens and responds to navigation, selection, form entry and writes. |
| Restricted development datasource | PASS | Saved development connection uses the existing restricted application role; Appsmith queries and synthetic writes authenticate successfully. No new credentials were generated. |
| Development n8n routing | PASS | Development workflow actions use the isolated test destination. The shared production destination was preserved. |
| Required local paper workflow | FAIL — unresolved | One authenticated synthetic dispatch did not produce a durable reservation or agreement. Optional ERP/Drive readiness is explicitly nonblocking; neither is required to diagnose this local failure. No production workflow was invoked. |
| Complete database isolation certification | BLOCKED for promotion | Focused read-only review narrowed the earlier concern: connection permission alone did not demonstrate business-data access or privileged routine execution outside the dedicated test database. Treat residual test connection policy as deployment hardening; production effective grants and isolation still require private review before promotion. |

## Actual browser acceptance

| Workflow | Result | Observed outcome |
| --- | --- | --- |
| Directory | PASS | Listed synthetic staff and both Intake records; search, contextual actions and View Profile worked. |
| Individual Profiles | PASS | Explicit selected identity, Participant/Contributor capacities, contacts and staff controls loaded. |
| Company Profile | PASS after focused fix | Opened a separately prepared synthetic organization from Directory; saved identity, linked an existing synthetic contact person and confirmed persistence after reload. A second rename verified the saved name remains in the input. Organization fixture creation itself is not claimed as a UI pass. |
| Reports | PASS after focused fix | Authorized staff without Participant enrollment could see report controls and execute a report returning metric rows. |
| Two consecutive Participant Intakes | PASS | Two separate synthetic enrollments committed, with an explicit reset between them. The second also enabled Contributor capacity. Both used enrollment-only agreement handling and disabled mailing subscriptions. |
| Intake recovery check | PASS | Check saved Intake confirmed the committed result without replaying enrollment or signing. |
| Former-Participant contact correction | PASS after focused fixes | Reviewer selected a retained email, an active target and a reason; reassignment succeeded. Source lost the transferred email and the target profile showed it, preserving its existing primary email. Other ended-enrollment contact writes stayed disabled. The former fixture was prepared separately through the existing audited lifecycle routine; lifecycle UI acceptance is not claimed. |
| Contributor identity | PASS | Contextual Contributor Functions selected the intended synthetic individual and showed the correct Contributor identity. |
| Cash entry and review | PASS | A synthetic contribution stored 1,234 cents and was verified through Cash Deposits, moving to Cash on Hand. |
| Draft deposit batching | PASS | Created one draft batch and added the verified contribution. The batch showed one item and 1,234 cents. |
| Contribution amount display | PASS after focused fix | Contribution history displayed 12.34 for 1,234 stored cents. |
| Pending Contribution list refresh and review | PASS after focused fix | A separate 56-cent contribution appeared in the pending queue, verified successfully and left that queue without a refresh failure. The original contribution was not replayed. |
| Deposit preparation/confirmation — historical local test | PASS — limited historical evidence | The now-rejected Appsmith PR #9 was installed in development for this test; it is closed without merging and is not the release candidate. Through the actual interface, the existing synthetic 1,234-cent draft moved to prepared and confirmed with a local destination/reference and 1,234 actual cents. Prepared destination locked, Prepare/Confirm disabled after completion, and no ERP request was required. Focused verification found one preparation audit, one confirmation audit and no eligibility for the deposited contribution to re-enter Cash on Hand. |
| Confirmed deposit printable record | PASS | The browser generated a nonempty one-page PDF containing confirmed status, the synthetic reference/destination and 12.34 amount. No PDF or actor details are published here. |
| ERPNext accounting synchronization | Additional end-to-end testing DEFERRED — nonblocking | Preserve existing bank selection, refresh lookup, automatic synchronization, retry and dynamic status. No new accounting transaction or replay acceptance is claimed. Deferral does not authorize disabling the integration. |
| Google Drive paper storage | Additional acceptance testing DEFERRED — nonblocking | Preserve existing provider functionality and runbook. No new Drive upload/retrieval acceptance is claimed, and no feature removal or disablement is authorized. |
| Agreement Type setup and selection | PASS | The empty selector was caused by missing reference records. Created the minimum synthetic type through the existing Agreement Templates administration form; it appeared in the selector. One creation audit was recorded. Required fields and an existing type key disabled creation. No new administration subsystem was needed. |
| Agreement creation and review | BLOCKED | Reference-data blocker is resolved. One local/NocoDB paper creation/review is the current core acceptance path and has not completed. Digital signing integration prerequisites are a separate limitation. No signing request was triggered. |
| Paper agreement upload and review | FAIL — unresolved | The supported NocoDB fallback was configured with isolated test credentials and the current workflow. Anonymous webhook access was denied. The browser controller stalled during PDF selection, then recovered. One synthetic upload was submitted; the interface retained an uncertain checkpoint. Receipt lookup did not establish completion; focused verification found neither an upload reservation nor an agreement. The executing revision matched the saved workflow. No second storage upload was submitted. Tracked in #36. Storage identity, retrieval, reviewer access, completion audit and approval remain unaccepted. Google Drive is deferred and nonblocking, separately tracked in #34. |

## Demonstrated defects and focused repairs

[Appsmith PR #8](https://github.com/RayzorDuff/SignatureGate-Appsmith/pull/8) contains the release fixes installed in development for acceptance:

- Canonical staff authorization for Reports visibility.
- Required reason/target inputs and target loading for former-Participant contact correction.
- Two-decimal contribution amounts preserving cents.
- Pending donation JSON lookup compatible with prepared SQL parameters.
- Company identity input retaining its newly saved name.

Targeted contact authorization/selection regression checks and a focused profile-loader check passed. Full automated suites were not repeated. PR #8 and the sanitized acceptance documentation in SignatureGate PR #33 are merged.

## Focused authorization acceptance

| Sensitive workflow | Result | Observed boundary |
| --- | --- | --- |
| Former-Participant contact reassignment | PASS (denial) | A synthetic canonical actor with no staff roles saw no accessible profile or reassignment controls in browser preview. |
| Agreement review | PASS (denial) | The same actor received the workspace access-denial message and no review or upload controls in browser preview. |
| Deposit confirmation | PASS (denial) | The same actor received the Donations Reviewer requirement and no confirmation interface. |

The existing test sign-in was temporarily linked to the synthetic unprivileged canonical person; this was not a second independent Appsmith login. The original synthetic reviewer link was restored and its backend access rechecked. These are focused interface-denial results, supported by the previously accepted native authorization tests; they do not claim a new full permission-matrix run or direct forged-request testing.

## Remaining integration findings

**Agreements:** Existing schema, administration form and permission path work with a fresh reference table. The one synthetic type remains reusable. Do not invent a Documenso template identifier or activate signing until the isolated service, test credential and template are available. Complete one creation and authorized reviewer transition, including evidence/audit checks.

**Cash and ERP:** Cash entry, review, deposit preparation and confirmation remain required. Preserve the pre-PR #9 development behavior, including the ERP bank-account selector, refresh lookup, automatic synchronization after confirmation, Retry ERP Sync and dynamic status. PR #9 was closed without merging after failing Development checks; its capability reductions are rejected. The historical synthetic deposit, PDF, audit and eligibility results remain useful evidence of the local transaction but do not establish acceptance of the restored selector/integration or approve PR #9. A new end-to-end ERP synchronization test is not a release gate; existing integration functionality must remain intact. Inspect and restore only affected development objects, preserving PR #8 and unrelated changes. Do not reset the application wholesale or modify production.

**Paper:** NocoDB is an intended supported fallback. Its isolated workflow configuration is prepared, but one synthetic upload was dispatched after file-picker recovery, but no durable reservation or agreement was produced (#36). Retrieval, review and durable evidence/audit acceptance remain open. No duplicate upload was dispatched. The development evidence origin was rebound privately to the test destination; that environment delta must be retained in configuration review. Additional Google Drive acceptance testing is deferred and nonblocking for v1.2.0; its existing functionality and runbook must remain intact. The earlier isolated test checkpoint reported its node disabled; this is a test-configuration observation, not an approved release change. Later isolated validation needs test-only OAuth authorization, folder access and a private reviewer retrieval check. Do not infer storage privacy from a successful health check or authenticated upload endpoint.

The browser controller lost its tabs during the file-picker operation. A fresh Appsmith tab subsequently responded; this is not evidence of an Appsmith or server outage. No browser reset loop or shared-service rebuild was performed.

## Open issue disposition

Classification is for release scope and evidence; an open issue is not automatically a request for additional development. Closure requires its stated acceptance requirements.

| Repository / issue | Classification | Disposition |
| --- | --- | --- |
| SignatureGate #12 | Already implemented; closed | Two consecutive browser Intakes and reset/recovery passed in the preserved checkpoint. Closed from this evidence. |
| SignatureGate #23 | Already implemented; closed | Canonical Directory, selected Individual/Company Profiles and Reports passed; retired legacy Directory is not restored. Closed from this evidence. |
| SignatureGate #14 | Already implemented; awaiting remaining evidence | Former-Participant email reassignment passed. Broader collision messaging and phone/address cases are not all claimed; keep open. |
| SignatureGate #19 | Already implemented; awaiting remaining evidence | Canonical individual/company identity, Contributor and contact work are implemented with substantial accepted evidence. Provider resolution, relationship/reporting and other issue-wide criteria are not all closed by this checkpoint; keep open and avoid another general identity rewrite. |
| SignatureGate #20 | Already implemented; awaiting remaining evidence | Central terminology and Participant/Spiritual Practitioner UI adoption are accepted. Remaining external-template inventory and complete issue checklist still need disposition; legal/board document approval remains outside software acceptance. |
| SignatureGate #17 | Required to release v1.2.0 under current scope | Local preparation, confirmation and printable PDF now passed. Focused verification also found one preparation audit, one confirmation audit and no re-entry of the deposited contribution into Cash on Hand. Preserve prior native immutability/eligibility evidence; leave broader issue wording open for disposition of its now-deferred ERP criterion. Additional ERP end-to-end testing is deferred by owner decision; existing functionality must remain. |
| SignatureGate #18 | Safe to defer after v1.2.0 — owner decision | Additional ERPNext deposit synchronization acceptance is nonblocking. Keep open and preserve the existing integration. |
| SignatureGate #34 | Safe to defer after v1.2.0 — owner decision | Google Drive storage validation is explicitly nonblocking. Preserve the existing implementation and runbook; defer additional acceptance only. |
| SignatureGate #36 | Required to release v1.2.0 | Resolve the local paper request failure before durable reservation, then complete browser creation, retrieval, review and evidence/audit acceptance. |
| SignatureGate #29 | Required before promotion for release-used routes | Required development destinations have been isolated; complete final source/deployed reconciliation and reviewed production configuration separately. Broader routing work must not expand this acceptance cycle. |
| SignatureGate #13 | Safe to defer after v1.2.0 | Cancellation actor-display defect is not exercised here; keep open. Reclassify if signing acceptance shows lost attribution or authorization impact. |
| SignatureGate #10 | Safe to defer after v1.2.0 | Broader provider address canonicalization remains unresolved; no new provider reprocessing or address migration is included. Preserve provenance and keep open. |
| SignatureGate #27 | Safe to defer after v1.2.0 | Explicit post-release browser-test infrastructure; no framework added. |
| SignatureGate-Appsmith #2 | Already implemented; closed | Fresh-table Agreement Type creation, selector refresh/reuse, creation audit, required fields and duplicate-key guard observed. Closed from this evidence. |
| SignatureGate-Appsmith #4 | Already implemented; awaiting remaining evidence | Existing grouped navigation is retained. Complete residual accessibility/mobile checklist separately; do not redesign navigation for this release. |
| SignatureGate-Appsmith #5 | Required before promotion for release-used routes | Development isolation is distinct from reviewed production routing. Never merge development wholesale into production. |

## Migration, rollback and promotion readiness

**Not ready for promotion.** The current upgrade manifest remains explicitly non-executable: 24 entries have undecided selected/skipped dispositions, and all nine environment proofs remain false. Older narrative counts are historical; use the current manifest. Successful fresh-database suites do not prove an upgrade of the actual installed production baseline.

Before promotion, finish the remaining core local workflows and pin the compatible **released and deployed** dependencies actually used by that release scope. Deferring additional ERP testing does not authorize removing existing dependency contracts or disabling functionality. The latest published RootedOps release rechecked at this checkpoint is v1.1.0. Distinguish missing optional test prerequisites from regressions in existing ERP/Drive functionality; preserve the latter contracts.

Then review the actual production definitions, staff ownership/grants and data invariants privately, select the exact ordered forward changes, verify backup restoration and rehearse that sequence on a protected restored copy with workers/destinations isolated. Verify historical identity, contribution and agreement preservation plus recovery at the schema/application boundary. Rollback must use the reviewed compatible application/configuration rollback and verified recovery plan, not a blind bootstrap or unreviewed down migration.

After those gates, review the production-bound Appsmith environment delta and exact source/export, changelog, VERSION and coordinated dependency pins. Production datasource switching, publication, tags and release remain separate approval-gated actions. None occurred in this checkpoint.

## Concise release blockers

1. Complete one local/NocoDB agreement creation/review and evidence upload/retrieval/audit cycle. Google Drive is not a prerequisite.
2. Verify the test2 development app preserves/restores the pre-PR #9 deposit capabilities and PR #8 repairs. PR #9 is closed and must not be merged. Retain historical local deposit, print, audit and eligibility evidence; additional end-to-end ERP testing is not required.
3. Finish the current upgrade manifest decisions, private production ownership/grants review, verified restore/rehearsal/recovery and released/deployed dependency pin.
4. Review the final production-bound Appsmith configuration/export and packaging; obtain explicit production-promotion approval.

All prior PASS results remain accepted. No full SQL/Appsmith CI suite, test-environment rebuild, shared-service restart, navigation redesign or new automated framework was introduced.
