# Phase 2 progress — Agreement Types, identity notes and packaging prerequisites

Status: **in progress; unreleased**. Development is authorized while the [Phase 1 live evidence gate](PHASE_1_VALIDATION.md) is gathered. No production migration, datasource switch, publication or release tag has been performed.

## Candidate provenance

The naming/documentation follow-up is published in SignatureGate-Appsmith `078e24d` on `chatgpt_development`, based on the editor revision `9405851`. SignatureGate `f45bd0a` contains the notes/seed/naming implementation. These source revisions do not establish a deployed editor or published production revision. The documentation publication boundary has now been clarified: technical identifiers are allowed, while actual operational identity/contact/financial/product/account values remain private.

SignatureGate-Appsmith `chatgpt_development`: `f08296a84ea30b20dbf948f0260426e832890c9c` (first Phase 2 increment, based on `2746b2712f2bd91b508c1d58f7025ce444abef78`). Backend changes are the SignatureGate commit containing this document, based on `71c08610013322d1bacfe9ac294ff4b2a1996e49`. The operator reports pulling this Appsmith development revision into the test editor; an independently observed editor SHA and production publication SHA remain pending.

New migration SHA-256: `574a862369297919a3d0b062acd9341ce6aaecc95edd01e139808939c6524abd`.

## Implemented

- `Agreement Templates` has a document-reviewer-only Agreement Type form with key, display name, description, integer sort order and active state. It rejects blank/invalid fields and duplicate active or inactive keys; successful creation resets the form and refreshes type selectors. Failed creation preserves input. A refresh failure reports that creation succeeded so operators do not repeat the write.
- `public.create_agreement_type(...)` checks the canonical document-reviewer account, independently of membership, normalizes key/name, rejects duplicates and atomically records creation and `agreement_type.created` audit details. An audit failure rolls back creation. The Appsmith action passes the signed-in email directly, rather than a form parameter or stored actor.
- `Agreement Templates` uses the canonical actor lookup and accepts authorized people without membership. Other pages' legacy actor lookups remain separate Phase 2 work.
- The Appsmith exporter retains flat/nested datasource descriptors, `jslibs`/legacy library descriptors and widgets nested beneath embedded canvases. Conflicting dependency descriptors and unattached widgets fail generation. The export workflow now runs preservation fixtures, exact-source semantic checks and release asset checks before committing generated JSON.
- Fresh-bootstrap validation found malformed dollar quotes in two existing donation-financial permission helpers in `db/schema.sql`; their delimiters are repaired without changing their logic.
- Terminology validation keeps the two current `Individual Profile` role controls mandatory. Five retired practitioner-assignment controls are validated when present in an older export. Four of the earlier fourteen findings were caused by the exporter dropping the two existing role controls; ten were obsolete checks for the five removed controls.

The packaged `appsmith/Rooted Psyche Membership Ops.json` remains the previous shipped artifact. The scratch candidate is test-bound and must not be used as the production release export. Final packaging still uses the existing action pinned to the production-bound Appsmith master SHA.

## Validation completed

| Check | Result / limit |
| --- | --- |
| Canonical schema bootstrap | Pass on isolated PostgreSQL 18.3 through PGlite 0.5.8 with uuid-ossp; psql client commands removed only for this embedded runner |
| Agreement Type migration | Applied twice successfully after bootstrap; transaction wrapper and ON_ERROR_STOP retained in shipped SQL |
| `verify_agreement_type_administration.sql` | Pass: empty table, canonical nonmember reviewer, normalized fields, duplicate keys, denied roles/accounts, invalid fields, inactive type, actor audit, audit-failure rollback; synthetic records rolled back |
| `verify_person_roles.sql` | Pass on the same isolated canonical database |
| Appsmith `tests/agreement-type-flows.mjs` | Pass: nonmember reviewer initialization, required/key/order validation, inactive duplicates, role denial, database error, successful refresh and committed-creation refresh failure |
| Export preservation/rejection fixtures | Pass: flat/nested descriptors, library dedup/conflict, embedded canvases, separate action body, missing library and orphan rejection |
| Current development export semantic checks | Pass: 18 pages, 339 actions, 14 collections, four datasource descriptors, one jsPDF library; source widgets/actions/collections preserved |
| Fresh candidate release asset checks | Pass, including retained configured role controls; deliberately broken role terminology is rejected in both page variants |
| Phase 1 catalog collector SQL | Executes successfully on isolated canonical PostgreSQL; actual PostgreSQL 16.13 captures received and privately reviewed; effective-definition dispositions still pending |
| Repository checks | `make release-check`, all 722 Appsmith JSON parses, all 14 JS syntax checks and `git diff --check` pass |

The initial isolated checks now have live PostgreSQL 16.13 evidence: the operator reports applying Agreement Type administration and passing its rollback-only SQL checks on `signaturegate_test`, then successfully creating an Agreement Type through the new form on `chatgpt_development`. Remaining UI permission, selector, layout, prepared-query, import, Git synchronization and publication checks still require evidence before Appsmith #2 closes. See [LIVE_EVIDENCE_REVIEW.md](LIVE_EVIDENCE_REVIEW.md); no identity or created type values are recorded.

## Test deployment and live acceptance

Confirm Phase 1's actual test datasource target and deployed canonical prerequisites first. The migration requires `agreement_types`, `audit_log`, canonical person accounts and `issue19_has_role`; it does not upgrade an older pre-canonical schema.

From the SignatureGate server checkout, apply the new backend migration **to test before pulling the frontend**:

```bash
cd ~/signaturegate
git pull --ff-only
sudo docker exec -i signaturegate-postgres \
  psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  < db/migrations/agreement_type_administration.sql
sudo docker exec -i signaturegate-postgres \
  psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  < db/tests/verify_agreement_type_administration.sql
```

Then pull `SignatureGate-Appsmith/chatgpt_development` in the test editor, reload and verify:

1. A canonical document reviewer without membership can open the page and create a type. Practitioner-only, donations-reviewer-only and unauthorized accounts cannot create it; the database denies direct calls too.
2. Key/name/order/active/description are correct; active types appear in the existing template selectors without manual database editing; inactive types do not. Existing types and templates remain usable.
3. Empty or invalid fields and duplicate keys, including inactive existing keys, fail without a row or audit entry. Successful creation records exactly one audit attributed to the reviewer.
4. First-type setup works on a separate disposable empty-type database. Do not delete operational test or production types to stage the empty-table test.
5. Inspect desktop/narrow-width form layout, keyboard behavior, actual prepared-query results and clean page initialization; commit any editor-generated metadata and re-pull to prove Git sync preservation.
6. Import the freshly generated candidate into a disposable Appsmith application and verify dependencies and nested role widgets. Retest `Company Profile` initialization after the pull.

Record deployed backend/frontend SHAs, Appsmith/PostgreSQL versions, actor roles and evidence in the acceptance ledger. Add this migration, with checksum and verified prerequisites, to the production manifest only after Phase 1's actual comparison and restored-copy rehearsal.

## Remaining Phase 2 work

Reporting categories, canonical practitioner-scoped cash/history and core staff authorization have automated coverage; accepted operator permission observations are recorded below. Remaining gates include deployed canonical provider/company-contact acceptance, `Intake` contact/agreement parity, protected upload/integration/principal review and candidate runtime checks. Legacy `Members – Intake` remains until parity is proven. The 175 source fallback findings and obsolete upload reference remain tracked for contextual repair and runtime acceptance.

## Linode validation follow-up

The fresh bootstrap now closes the transaction opened by the appended ERP synchronization section. Without that closing COMMIT, psql disconnect would discard that section and later additions. Bootstrap persistence and Agreement Type behavior without a prerequisite migration pass on isolated PostgreSQL. The Linode helper verifies both release APIs through a separate psql connection before collecting the canonical catalog. See [LINODE_VALIDATION_COMMANDS.md](LINODE_VALIDATION_COMMANDS.md) for commands and deployment evidence tools; no current database has been changed by these tools here.

## Identity notes increment

`party_identity_notes.sql` now runs as one explicit transaction with `ON_ERROR_STOP`. Its historical import records one decision per membership in `member_identity_note_backfill`, without duplicating private note text in provenance. The operator-only, invoker-rights `backfill_member_identity_notes()` is revoked from PUBLIC. Existing identity text and original participant notes are retained. Already copied legacy fragments are recognized; changed/previously blank sources are not recopied after the first decision. Prior audited canonical edits and clears take precedence and are marked `preserved_edit` for private review. This policy does not reconstruct cleared notes or automatically resolve historical conflicts.

The existing note APIs and Appsmith controls remain compatible. No frontend pull beyond the existing `chatgpt_development` is needed for this increment. Canonical bootstrap includes the provenance objects and helper; the forward migration initializes historical provenance on existing deployments.

Isolated PostgreSQL checks pass on both fresh bootstrap and forward migration applied twice: individual/company read, add/edit/clear; nonmember manager/document/donations reviewer permissions; practitioner/unknown/disabled denial; required reason; normalization/no-op audit; audit-failure rollback; original-source preservation; multiple historical memberships; already copied/blank/changed/cleared source reapplication; provenance-write failure rollback. Tests use synthetic fixtures and roll back. PostgreSQL 16.13 and Appsmith live checks for this increment remain pending.

Follow [NOTES_VALIDATION_COMMANDS.md](NOTES_VALIDATION_COMMANDS.md) in order. Capture effective definitions privately before the test migration. Apply and repeat only against `signaturegate_test`, run rollback-only verification, refresh the catalog and check Profile/`Intake` behavior. Production still requires effective-definition review and a restored-copy upgrade rehearsal.


## Documentation, naming and seed follow-up

Active setup/integration guides now use the canonical schema and retained functional migration/test names, rather than retired historical installation files. The terminology inventory reference is `docs/TERMINOLOGY_INVENTORY.md`. `Directory`'s Appsmith JS collection and registered action filenames are renamed descriptively as `directoryFlows`, with Git synchronization identifiers retained. Pull the matching development update only after preserving editor work; verify `Directory` initialization and its profile/operations/release routes.

`db/seeds/organization_terminology.sql` reconstructs the earlier public 14-concept initialization, including Spiritual Practitioner defaults, and preserves existing overrides on repeat. The fresh schema previously provided its tables but not these rows. Participant presentation remains a Phase 3 requirement; the seed and tests must be revised with that implementation. `appsmith/SCREENS.md` is explicitly marked historical and scheduled for a complete update after navigation acceptance, before packaging.

Validation for this follow-up passes: seed fresh/repeat behavior and override/activation/timestamp/attribution preservation; seeded terminology behavioral SQL; repository naming positive/negative checks; Appsmith JSON parse and `Directory` registration consistency; exact-source candidate export (18 pages, 339 actions, 14 collections, four descriptors, one library); Agreement Type flow regression; `make release-check` and whitespace checks. Live PostgreSQL 16 and `Directory` editor round-trip remain pending.


Architecture now includes Listmonk consent/list separation and RootedOps/ERPNext deposit accounting. The party identity guide distinguishes individual/company identity, Participant/Contributor capacities and system permissions; documentation uses Rooted Psyche Participant and Facilitator/Spiritual Practitioner presentation while preserving literal database/API/current page identifiers. `LISTMONK_CONTRIBUTOR_LIST_ID` and newsletter/Participant-communications mappings are documented against the committed worker. `n8n/CASH_DEPOSIT_ERP_INTEGRATION.md` records RootedOps-owned workflow/API contracts and the pending released-dependency gate. No actual account, transaction, credential or live mapping values are copied into these documents.


## Live notes SQL acceptance and Reports increment

The notes follow-up at backend `f45bd0a` confirms two successful committed migration runs, zero historical sources processed on repeat, and successful rollback-only behavioral verification on PostgreSQL 16.13. Appsmith's actual datasource returns `signaturegate_test`/16.13. Canonical notes SQL acceptance now passes live; Profile/Intake behavior and restored-production upgrade still require acceptance.

`Reports` now uses the canonical current actor and person-based practitioner assignments. Canonical-only document reviewers, donations reviewers and practitioners need no Participant record to enter. Donation totals are guarded independently in SQL by Donations Reviewer permission. The page clears stale authorization/compatibility state and filters retained financial selections and displayed results when the current account is not authorized.

Contribution reporting includes six count/dollar groups: all contributions, individual contributors, company contributors, anonymous cash, unresolved provider imports and Participant-linked individual contributions. The first four identity categories are disjoint and reconcile to the overall total; Participant-linked is an overlapping individual subset based on current shared person identity and active Participant capacity, not the donation's legacy participant projection. Archived contributor history remains attributable. Stable metric keys remain compatible; labels say Participant.

`tests/report-access.mjs` verifies canonical nonmember entry, denial/error state clearing, retained-selection denial and cached financial-result isolation. `tests/reporting-sql.mjs` executes the actual action SQL on an isolated canonical database with artificial fixtures and bind parameters. It checks all six groups, canonical assignment scope, direct financial selection denial, ending Participant capacity without changing historical contribution totals, removed roles and disabled accounts. Appsmith import/editor/Git round-trip validation is still pending; see [REPORTS_VALIDATION.md](REPORTS_VALIDATION.md).

Cash Deposits, Audit Log, remaining legacy Intake paths, reason-aware revival, practitioner-scoped cash/history, and company contact-person representation remain separate Phase 2 work. This increment does not broaden practitioner financial visibility or promote development to production.


## Permission regression follow-up

Operator runtime feedback found critical permission and email/cash-refresh failures. [PERMISSION_REVIEW.md](PERMISSION_REVIEW.md) records the canonical role/resource model, repairs and regression evidence; [PERMISSION_VALIDATION.md](PERMISSION_VALIDATION.md) gives the backend-first test sequence. Participant capacity grants only self-read access. Document Reviewers can perform participant/practitioner operations and record pending anonymous cash without membership; financial review/deposits remain Donations Reviewer-only. Scope and atomic audit are enforced in the new database APIs, not inferred from cached flags. Live acceptance, provider-resolution/contact parity and external endpoint authorization remain open release gates.

The permission review follow-up guards client audit insertion by canonical Participant write scope and fixes canonical reviewer duplicate access on legacy Intake. Actual source tests pass for forged audit actors, denied Participant/unassigned writes and canonical nonmember reviewer enrollment. Development paper-evidence upload is disabled pending destination/authentication validation after automatic approval review; its integration/parity gate remains open. The n8n export remains unchanged; only the isolated inventory filter helper is committed.

## Operator permission acceptance and reason-aware reconciliation

The operator's run at backend `26531cf` reports exit code 0 for two authorization migration applications and the authorization/confirmed-date correction checks. The operator confirms denied-page navigation, Contributor-choice clarification, reasonable practitioner/reviewer boundaries, expected Participant restrictions and corrected Intake email validation. Detailed logs were not supplied; this records operator execution/observation evidence without copying private values. Broad manual permission/email checks need no repetition for unchanged behavior.

Cash reconciliation revival now requires a new reason and audits it atomically alongside the original exclusion reason, notes and identity. The retained two-argument API fails closed with a reason-required error. The shared Exclude/Revive dialog requires an explicit operator reason, captures the clicked row, checks fresh authority/account and distinguishes failed writes from committed refresh failures. New rollback SQL, controller and actual query-binding tests pass; live application and one Appsmith dialog integration scenario remain.

[TEST_CONFIDENCE_AND_MANUAL_VALIDATION.md](TEST_CONFIDENCE_AND_MANUAL_VALIDATION.md) distinguishes high-confidence SQL/controller contracts from browser/integration/upgrade gaps. Operator work is limited to a test-only automated script and one focused UI scenario in this increment. No new browser harness is added to v1.2.0. Production restore/manifest, external publication, paper upload and final navigation remain open release gates.

During publication preparation, live Appsmith sync `f412b81` exposed 24 guarded actions automatically changed back to Automatic mode. The increment preserves that synchronized parent and pins the observed Manual choices with the explicit-choice flag used by Appsmith v2.4.2. Metadata regression checks cover those choices and new reconciliation actions; the next post-pull repository sync should be inspected automatically for persistence. The source contract and confidence limits are documented in TEST_CONFIDENCE_AND_MANUAL_VALIDATION.md.

The synchronized source review also found practitioner-administration client audit insertion still trusted a caller actor and lacked a SQL guard. It now requires canonical practitioner administration permission and uses only the signed account; actual action tests deny Participant/practitioner-only inserts and verify nonmember Document Reviewer attribution. This needs no additional manual matrix.

## Canonical provider review and attribution correction

Provider review still required legacy staff membership, and reassignment was a direct unaudited SQL update. `provider_donation_administration.sql` now uses canonical reviewer authority, atomic contributor resolution/creation and reasoned reassignment. Automatic matching combines contact candidates rather than falling through after ambiguity. New Participant enrollment requires the existing Directory Manager/both-reviewer combination, two contacts and one shared person; Contributor-only creation never creates Participant capacity. Contributor and Participant mailing preferences remain independent.

Rollback SQL and actual action-binding tests cover duplicate/provider conflicts, ambiguous/contradictory contacts, nonmember reviewers, stale legacy flags, explicit enrollment, unchanged financial/provider history, active-batch protection and audit-failure rollback. Controller tests cover exact clicked-row/cents display, reasons, cancel/account/role changes, double clicks and singular write/refresh outcomes. The older on-load assertion now checks Appsmith's explicit Manual/true contract, consistent with the execution-setting repair; no action is changed back to automatic mode.

[PROVIDER_REVIEW_VALIDATION.md](PROVIDER_REVIEW_VALIDATION.md) limits operator work to one test-only automated sequence and one changed-dialog check. The previous cash migration/dialog results are not assumed: the new runner includes its pending migration and tests. No post-pull system commit beyond `cce43f3` has been observed; execution-setting persistence remains pending automatic inspection. Company contact-person representation, remaining Intake/contact parity, disabled paper upload, external endpoint/principal trust, restored upgrade and navigation remain open. Phase 2 is not declared complete.

## Company-contact and Cash Deposits access follow-up

Provider review is published at backend `03a6be4` / Appsmith `8b1208e`. The operator reports successful cash test migration/reapplication and rollback validation at backend `50f4650` (exit 0); Exclude/Revive UI acceptance is blocked by Cash Deposits reporting missing permission. Profile roles without an account link do not prove the signed-in actor's authority. Cash initialization now uses one canonical returned authority with account/stale-refresh checks, explicit lookup invocation, distinct loading/error/unlinked/denied states and a safe boolean diagnostic. No role is implicitly granted. Automated startup/controller/prepared SQL checks pass; live account-state/runtime acceptance is pending.

Explicit audited company-to-contact-person relationships and Company Profile link/archive/reactivate controls are implemented. Fresh/repeat SQL, permissions/directory scope, multiple/shared/standalone identities, optimistic versions, audit rollback and prepared bindings/controller checks pass in isolation. No identity merge, enrollment, permission, donation or mailing inheritance is introduced. This closes the source representation gap; deployment/rendering and protected-upgrade acceptance remain open. See DIRECTORY_REVIEW_VALIDATION.md for one backend-first command and the immediate cash-page check.

Phase 2 remains open for Intake/contact/agreement parity, paper upload and external principal/endpoint trust, consolidated candidate runtime acceptance and live increment evidence. Terminology/navigation/SCREENS remain Phase 3 work; restored upgrade and release packaging have not commenced.


## Accepted directory/cash results and staged workflow feedback

Operator reports `validate_directory_review_test.sh` exit 0 after pulling `8a08e74`. Provider/company API application twice and the runner's rollback checks are accepted. Cash access succeeded after Retry; the final Exclude/hidden-row/reveal/required-reason/Revive sequence restored `cash_on_hand`. Earlier pending-review observation remains open and receives read-only sanitized correlation, not another mutation request.

Terminology's initializer was Manual. It is now explicitly on page load, waits for sign-in, retries one failed read and uses account-bound loading/ready/unlinked/denied/error states. Cash similarly retries one failed startup read; writes and returned denial are never retried automatically. Post-disposition table selection is cleared.

Intake, Member Functions digital signing, ERP confirmation/retry and profile mailing requests now show stages. Signing only claims email delivery when explicitly confirmed; mailing stages report queued requests. Intake mailing checkboxes are applied to actual SQL; dual-capacity phone/address contacts reuse the audited role-assignment API. Staff profile mailing actions verify signed authority and the contact's selected identity in SQL before mutation. Intake audit actor is bound to the signed account. Twenty-four synthetic controller/prepared-SQL enrollment cases pass, alongside permission/action-mode/cash/provider/company/controller regressions. External API calls are stubbed and do not certify actual delivery.

Paper Intake now stops before records/files, matching the Member Functions integration boundary. Atomic recovery across independently committed Intake actions, paper route acceptance, live stage/SDK checks, external trust and consolidated runtime validation remain release gates. See INTAKE_PROGRESS_AND_ACCESS_VALIDATION.md for the reduced operator sequence.

The retained legacy Members–Intake page also blocks paper selection before any identity write. Its upload execution code is removed and paper controls are disabled. Its digital stage messages remain available; no external upload request is made. The pre-write boundary and disabled controls are exercised automatically.


## Operator checkpoint at 93b2082

Read-only cash observation exit 0 on `signaturegate_test`: both Intake APIs exist, the latest exclusion concerns a verified donation and is still active, and the two most recent exclusions are for different donations. No intervening verification was found for the earlier of those two records. This does not establish which row was selected in the earlier UI report and does not prove a same-donation status regression. Preserve the unresolved display/history observation for consolidated acceptance; no repeat exclusion is requested.

Cash Deposits opens without Retry. Terminology Administration opens with the authorized form after Retry Access; permission is correct, but first-load reliability is not yet accepted. The controller now retries one failed terminology-data read separately from the access read, keeps the form closed until labels load, and distinguishes data failure from denied access. Source tests cover cold/persistent label failure and account change during loading; the live root cause remains unproven.

The operator will navigate interfaces independently. This walkthrough does not block independent development. Reuse passing backend and dialog evidence; no migration or new service request is introduced by this checkpoint.


## Phase 3: selected-profile entry

Individual/Company profiles are hidden from direct native navigation. Directory opens them with an explicit person/company UUID. A link with no ID never reuses an old stored selection; malformed/inaccessible links show a safe message and Back to Directory. Loaders are explicitly on page load, use current-account/route tokens, retry one failed primary read and leave content hidden until dependent reads finish. Late A-to-B or account results cannot expose another profile. Profile DB actions are pinned Manual/true and run after the selected primary record is resolved; existing signed SQL/resource guards remain.

Controller fixtures cover valid/missing/invalid/access-denied links, saved-selection refusal, cold/secondary read failures, route/account changes and late A-to-B primary responses. Company relationship regressions and exact-source export preservation pass. Real Appsmith dependency/SDK rendering remains a consolidated acceptance check; use the operator's forthcoming walkthrough, not another full role/identity matrix. No DB migration or permission grant is introduced.


## Phase 3 generated navigation and Participant presentation

Grouped capability-aware Menu Buttons are generated for all 18 pages from one registry, with shared presentation helpers and explicit read-only automatic lookups. Native Directory/title/sign-in remain available, profiles require explicit context, and unfinished event/queue pages remain unlisted. Menu authority matches current account and existing page SQL; it does not grant access. Default captions use Participant and Spiritual Practitioner while source page IDs and API keys remain compatible. Static widget copy is formatted without rewriting record values or executed documents. Audit links to retired Members - Profile now use Member Functions.

The explicit terminology initializer defaults the member compatibility concept to Participant, preserving installed overrides on repeat. Existing test labels are adopted through an authenticated Directory Manager API, with alternate-label/no-op/audit and unchanged-role/capacity/agreement invariants. Menu tests cover all dispositions and role/cache cases; profile/controller/prepared-query/export checks are reused. Source capability review uses the official v2.4.2 contracts. NAVIGATION_AND_PARTICIPANT_VALIDATION.md gives one test-only preparation command and targeted rendering/keyboard/mobile/profile observations for the operator's existing walkthrough. Remaining controller/service/document labels, external integration/recovery and live SDK gates remain open; SCREENS now documents the candidate rather than the obsolete starter outline.


## Phase 4 source/runtime preflight increment

All 175 audited bare-field empty-table fallbacks were repaired. Actual empty-vector tests identified nine additional out-of-scope currentRow fallbacks and ten null scalar fallbacks; all 194 affected columns now return arrays without evaluating a row when empty. Tests exercise 225 mapped empty columns and 215 direct column vectors with null/text/number/boolean rows. Populated mapping code is preserved. Menu visibility is now always boolean when actor data is unavailable, and role/cache cases assert the property types.

The unused Individual Profile upload action referenced a nonexistent FilePickerIndividualAgreement. No controller/widget invoked it; the dormant unvalidated action is retired. Enabled workflows are unchanged and paper remains blocked pending integration validation. The source auditor now accepts legal comments before export default and records the current source revisions/worktree state rather than a hard-coded initial revision. These are checked-pattern source results, not certification of all live Appsmith lint/runtime or external endpoints.


## Configured workflow copy and safe audit rendering

Static alert prefixes, Intake stage/completion copy and Reports metric labels now consume the shared formatter. Actual record/contact values and route/API identifiers are outside the formatter. Controller tests stub that presentation boundary for independent behavior checks; the 24 actual-SQL Intake cases also exercise the real alternate-label helper (Attendee/Guide/Sponsor) without changing role keys or saved identities.

Audit details render configured Participant/practitioner headings while preserving stored record wording. All dynamic display values are HTML-escaped, only HTTP(S) links without embedded credentials/control characters are emitted, path IDs are encoded and new-window links use noopener/noreferrer. Malformed detail JSON, null attachment entries and unsafe URLs receive safe text outcomes. Synthetic rendering tests cover these cases without an external request. Remaining dynamic/template/service/document captions are still a release inventory/runtime gate; executed documents are untouched.

## October 15: served startup evidence and bounded native repair

The version 2 Console inspection returned empty editor and published Directory schedules (HTTP 200, no cycle/error flag, no startup execution request). This is actual served configuration evidence; the raw Console attachment is private. The native Git format deliberately omits computed schedules, and Appsmith's import post-hook tolerates layout-update failures. The exact registration/import failure remains unproven. A guarded native two-setting repair and server schedule verification are prepared in DIRECTORY_STARTUP_REBUILD.md, with synthetic API tests for preflight/partial failure/privacy. Live repair, cold Directory loading and other pages remain open. No role, database or production operation is part of this increment.

## October 18: failed native API repair and corrected evidence scope

The installed server returned HTTP 400 on the first Directory setting request; no successful save/rebuild is confirmed. Both functions report ON_PAGE_LOAD. The helper's explicit-user flags cannot be read from the public DTO and were incorrectly reported false. Its success fixture/acceptance assertion is withdrawn. Repeated identical invocations also appear in the private log. The old mutating download is retired (100 repeated evaluations make zero requests). DIRECTORY_STARTUP_REBUILD.md now uses the installed editor's Settings controls for the two existing functions, stops on any save error and requests one editor reload only after successful saves. No root cause for the 400 or live fix is claimed.

## October 18: native recreation checkpoint and identity-preserving correction

The operator reports Directory table cold loading works after JS-object recreation; menus and other-page access remain failed. The native sync 3763b0a changes both Directory collections/function identities, but saves navigationLabels.initialize Manual and navigationLabels.label On page load. Development 4b1f56f corrects those modes without changing any of the 540 existing action/collection sync IDs. The generator formerly overwrote native identities on reapplication; it now preserves them and native defaults/extensions/layout, assigns identities once only for new resources and rejects duplicates. No duplicate tracked identities were found and no runtime identity-corruption root cause is asserted. Controller/generation/source/export checks pass; minimal live validation is NATIVE_OBJECT_IDENTITY_AND_STARTUP.md, not another role matrix.

## October 18: native Copy to Page resets startup registration

Directory and its navigation now pass the operator's check. After copying navigationLabels through Appsmith to the other pages, d62bc8d records all 17 copied initializers Manual/false. Source 7c7032f restores their explicit On-page-load mode while preserving all 540 existing copied identities, native defaults and synchronized widgets. The generation regression now simulates the reset on every destination. All 32 source startup dispatches and navigation/syntax/route/export preservation checks pass; deployed scheduler acceptance remains open. Next validation is one Terminology editor check and the same page after development-branch publication only if the editor passes. No production promotion, SQL or repeated role/Directory matrix is requested.

The follow-up Appsmith checkpoint 3743789 repairs two Contributors table computed columns that native synchronization reintroduced with bare empty fallbacks. The existing regression now passes 227 mapped-column and 217 typed-vector cases. It includes 7c7032f's startup correction; pull through this latest checkpoint for the one-page editor/deployed-development check. No additional manual table case is requested.

## October 18 — accepted navigation, presentation and Intake recovery

The operator accepts navigation across all pages. Previous other-page cold-start failures are superseded; no object recreation, Console repair or broad role/navigation test is requested. Appsmith development `4f37de2` repairs literal table title expressions and the incorrect URL/date column in Agreement Templates and removes nine redundant page headings. `688de0b` removes the tenth nested Intake heading and adds persistent account-scoped Intake checkpoints before first identity writes, blocked ordinary replay, known ID retention and explicit acknowledgment before resetting an interrupted intake. Table titles use readable deployment defaults; live configurable titles are not supported by the installed title editor.

Automatic verification includes 22 table contracts, independent date/null/invalid/empty outcomes, 24 existing real-SQL/controller Intake cases and 32 pre/post-action-commit failure cases, reload/reset/account isolation, signing recovery and storage failure before first write. Generation preserves all existing native identities; two new Intake method identities are added. Source, guarded-action, access/profile/provider/terminology/workflow cases pass. A private candidate preserves 18 pages, 510 actions, 32 collections, four datasource descriptors and one JS library. The shipped export is untouched.

The application now has a locked reproducible test harness rather than depending on a private local module path. The public screen guide is reconciled after accepted navigation. [PRESENTATION_AND_INTAKE_RECOVERY.md](PRESENTATION_AND_INTAKE_RECOVERY.md) records the bounded development renderer/storage observations and the recovery limitations. No new Linode SQL application is needed. Database atomicity/server idempotency, paper/integration principals, restored upgrade and production publication remain open. RootedOps' latest published release remains v1.1.0 as checked October 18; repository VERSION 1.5.25 is not a dependency release/deployment pin.

The ledger also preserves an unresolved policy conflict: the original anonymous-cash criterion requests practitioner-only entry, while accepted canonical tests deliberately deny it and permit reviewer entry. Do not silently broaden authority to satisfy an old criterion. Resolve its explicit disposition before final release acceptance.


## October 18 — atomic persistence and remaining terminology controls

The operator accepts the earlier three-table presentation and completion/progress/reload/reset sequence in the deployed development view. Empty fields after reload with a retained completion notice/disabled button are correct; Reset clears the persistent guard. Those unchanged checks are reused.

Backend `ad6cf01` adds atomic new-party Intake, a private technical receipt and canonical owner/key/payload idempotency. It preserves explicit mailing consent and existing role/contact/practitioner/agreement invariants and includes all database stages, completion audit and queue entries in one transaction. Appsmith `e0eb001` uses the API, keeps progress feedback, persists the request UUID and inspects saved receipts without replaying enrollment or signing. Contributor-only individual DOB is retained on the new identity. Digital HTTP follows commit with the existing agreement ID; missing receipts still require in-flight uncertainty handling. Legacy Intake remains a separate parity/retirement gate.

The full reproducible suite passes: 24 controller/prepared-SQL supported intakes, 24 backend enrollment/replay combinations, 14 complete rollback/retry boundaries, 14 explicit input rejections, role/owner/payload/account conflicts, eight atomic request/lost-response cases and signing no-replay. These are fresh isolated PostgreSQL fixtures; real PostgreSQL 16 activation, owners/grants, concurrent sessions and protected restored-production rehearsal remain open. The draft now has 21 undecided steps and nine unverified proofs and remains non-executable.

Appsmith `1a73856` corrects native Select labelText/placeholder binding generation, configured Directory Participant/Contributor row buttons and Individual/Company contact copy. Terminology Administration has a manager-only read-only active/reserved key/kind/label/state/description table and refreshes its current navigation-label query on save. Default/alternate/legacy configuration cases preserve stable capacity values. An installed member=Member requires explicit audited Participant adoption; the reserved participant concept is not enrollment. Source tests cannot replace the new-control native observation. Backend `3ed59e4` removes the obsolete standalone terminology import.

Use [ATOMIC_INTAKE_AND_TERMINOLOGY_VALIDATION.md](ATOMIC_INTAKE_AND_TERMINOLOGY_VALIDATION.md): one test migration command before frontend pull, existing audited Participant adoption where needed and a narrow development observation. Phase status now separates implemented source, remaining code milestones and actual deployment/restore/integration evidence. No production change, master promotion, shipped export replacement, VERSION bump or tag is performed.

The Phase 4 permission indicator auditor now reads split executable bodies before metadata fallbacks and recognizes optional-chain sign-in references. Synthetic source-precedence fixtures pass. Indicators remain source review aids, not deployed authorization certification.

## Contributor reporting and configured page-name increment

Appsmith `7a679b6` prioritizes explicit Contributor attribution and adds Participants Created/Contributors Created based on independent capacity timestamps. The optional active-Participant donation subset is separate and overlaps Contributor totals. Ended/archived capacity creation remains historical within current authorization scope. Metric choices, chart series and report table labels honor installed vocabulary; compatibility keys are hidden and old selections normalize. Saved menu/title regression checks exercise configured Participant/Contributor names on all pages without renaming stable routes or granting roles.

The read-only development CI workflow pins SignatureGate `0a8df7c`; [run 39183903296](https://github.com/RayzorDuff/SignatureGate-Appsmith/actions/runs/39183903296) passed the locked full suite at Appsmith `7a679b6`; fresh SQL fixtures cover contribution reconciliation, dates/history and financial/assignment/account guards. The focused JS fixture harness passed during the local workspace outage. See STATUS.md for the full CI outcome and [REPORTS_VALIDATION.md](REPORTS_VALIDATION.md) for the only new native rendering observation. No database migration or production promotion is introduced.

## October 19 — unified Intake parity and real PostgreSQL contention

The operator reports the audited Participant adoption/rollback sequence at backend 4b697c9 exits 0 on signaturegate_test. No sign-in address or operational data is recorded. The atomic API runner has not yet been reported; apply it before the current frontend.

Backend 9c64493 and Appsmith d65619c add explicit Create agreement later, with two contacts and practitioner assignment, no-email phone/address enrollment and no agreement, signing call or release eligibility. Eighteen added controller/SQL cases supplement the existing 24 cases. Appsmith 48090b3 retires the duplicate page/native/menu routes and seventeen unused active-Intake actions after parity. Regression tests additionally exposed/fixed canonical duplicate lookup for nonmember reviewers and an unpinned Manual signing action. Browser audit cannot manufacture completion; the transaction owns that event.

The candidate has 17 pages, 469 actions, 30 collections, four datasource descriptors and one PDF library. Exact-source export preservation passes; the shipped artifact remains unchanged. The read-only source inventory and permission indicators are refreshed without query bodies or operational records.

Appsmith aca3d48 pins backend d85fecb in [CI run 39194685976](https://github.com/RayzorDuff/SignatureGate-Appsmith/actions/runs/39194685976). Both application-checks and postgres-intake-concurrency pass. The latter runs the atomic contract twice-applied source on PostgreSQL 16.13 and observes real lock waits for commit/replay, rollback/retry, changed payload and changed owner. Each leaves exactly one enrollment, receipt and completion audit; the disposable database is removed. Seven lifecycle/barrier safety tests also pass normally and under optimized Python. An earlier runner failure after an expected conflict was corrected and is superseded by this passing run.

[UNIFIED_INTAKE_VALIDATION.md](UNIFIED_INTAKE_VALIDATION.md) requests only the installed API runner and one synthetic deferred Intake/native retirement observation. No repeated broad role, cash, collision or real signing-failure matrix is requested. Protected paper delivery, restored-production ownership/history/recovery, deployed integrations and RootedOps release/promotion/packaging remain gates.


## October 19 — accepted Intake and native startup/agreement follow-up

Operator atomic runner at backend 96c5b8b exits 0. Deferred Intake with progress and saved-receipt lookup is accepted. Appsmith f409997 retains native IDs and restores copied destination initialize methods from Manual to On Page Load; both GitHub jobs pass. Appsmith 0f8452c shows Agreement Type, scopes both catalog reads to canonical Participant write access, loads types before templates and rejects stale selections. Actual controller/prepared SQL checks cover reviewer/assigned practitioner, unauthorized scope, delayed widget rendering and empty/inactive/error cases. Full local checks and private candidate export preservation pass. Focused native checks and remaining phase gates are in NATIVE_STARTUP_AND_AGREEMENT_SELECTION.md; no database change accompanies this repair.


## October 19 — protected no-email paper agreement path

Navigation and agreement selectors are operator-accepted. Backend b0be1ba/aa21d67 adds canonical scoped upload reservation, atomic completion/evidence/receipt/audit, owner/payload replay guards and reasoned cancellation tombstones. The new header-authenticated n8n workflow validates a bounded signed PDF/PNG/JPEG before storage, uses bound SQL and retains no execution payloads. Appsmith 8cb2981/2b969e7 enables the existing paper controls without email, preserves existing object IDs, provides stages/read-only recovery and keeps independent Document Reviewer approval. Full local checks, source export preservation and six disposable SQL suites pass; the PostgreSQL 16 runner now includes migration/rollback paper contracts. Installed credentials/storage and the focused successful upload/review remain open; see PAPER_AGREEMENT_VALIDATION.md. Intake uses Create agreement later followed by Participant Functions for paper enrollment.


## October 19–20 — private Drive option and actual file JSON transport

Recovered the March 20 Drive-through-n8n decision; no dedicated issue was located. Pulled operator Appsmith aa59cd0 and workflow Header Auth 81b8f08 before edits. Appsmith 6bee614 serializes the complete action body with files as an array, adds the provider selector and controlled Drive links without changing accepted navigation. SignatureGate 575d4c4 preserves NocoDB/old receipts while adding confirmed private Drive references and provider-bound replay. RootedOps 58d2021/1.5.26 forwards the private folder/default settings. Existing paper workflow IDs and credentials remain; the generic uploader and other Header Auth changes are untouched. CI 39366285224 passes both application and PostgreSQL 16.13 paper-storage contracts. Live OAuth/native file transport remains the focused validation gap in GOOGLE_DRIVE_PAPER_VALIDATION.md.
