# SignatureGate v1.2.0 completion and production release plan

Planned release: **v1.2.0** (unreleased). This is the first coordinated release of **SignatureGate-Appsmith**.

Prepared October 11, 2026, for SignatureGate #17, #18, #19, #20, and #23, and SignatureGate-Appsmith #2 and #4.

## Release objective

Complete and validate the application on **SignatureGate-Appsmith/chatgpt_development**, prove the production database upgrade, switch the release candidate from test configuration to production configuration, and merge and publish that exact candidate on **master**. SignatureGate database and integration changes belong on **SignatureGate/main**.

Treat completion as three separate milestones:

1. **Code complete:** every in-scope acceptance criterion has an implementation and passing development evidence.
2. **Production ready:** the upgrade has passed on a restored production copy, production dependencies are present, and environment-specific changes have been reviewed.
3. **Released and verified:** production has the required database definitions, master contains the validated candidate, Appsmith has published it, and production smoke checks pass.

Passing source checks alone does not establish any of these milestones.

## Release ownership, changelog, and Appsmith artifact

- SignatureGate `main` owns this release plan, the database/integration deliverables, `docs/CHANGELOG.md`, and the packaged Appsmith JSON.
- SignatureGate-Appsmith `chatgpt_development` owns functional application development; `master` receives the validated production-bound application. Its first release is part of the v1.2.0 release set. Record its exact source SHA and eventual release/tag identity separately; do not invent a prior Appsmith release baseline.
- Keep `VERSION` at the current released **1.1.0** during implementation. Prepare **1.2.0** only when final packaging and acceptance are ready; do not create a release tag or mark a release published during planning.
- Use **SignatureGate/docs/CHANGELOG.md as the authoritative combined product changelog**, with entries grouped or identified as database, integrations, and Appsmith. Reconcile every change since the actual `v1.1.0` tag using repository history, issue evidence, and the embedded JSON diff; the current Unreleased section is a starting point, not an exhaustive record.
- Maintain Appsmith-specific release notes in SignatureGate-Appsmith for the first release, recording its own source SHA, prerequisites, application changes, and a link to the combined v1.2.0 changelog. An independent Appsmith changelog may be adopted later; duplicate hand-maintained changelogs are not a prerequisite for this release.
- At release, commit the generated **`appsmith/Rooted Psyche Membership Ops.json`** into SignatureGate. Use the existing **`.github/workflows/regenerate-appsmith-export.yml`** action (`Regenerate Appsmith export`) with **`appsmith_ref` set to the exact production-bound master commit SHA**. Run it against the intended SignatureGate release branch (`main` for this plan), wait for its generated-export commit, pull that commit, and verify the file against the pinned Appsmith source. A branch name alone is not sufficient release provenance.
- The action regenerates and commits the JSON; it does not publish Appsmith, validate live datasource connections, apply migrations, update release metadata/changelogs, or create a release tag. Its present JSON shape checks must be followed by the full release and semantic source/export checks.
- Record the Appsmith source SHA, export workflow run URL, export checksum, SignatureGate packaging commit, production database verification, and publication evidence in the final release notes/manifest. Record the final SignatureGate release tag's resolved SHA after tagging to avoid a self-referential manifest.

The final packaging gate is: production-bound Appsmith source frozen and published; exact-source export committed to SignatureGate; changelog coverage since v1.1.0 reconciled; VERSION/README/release notes updated to 1.2.0; source/export validation and release checks passing. Only then create the final release tags and release records.

## Reviewed baseline and initial findings

| Component | Reviewed revision |
| --- | --- |
| SignatureGate/main | 9fb5aa53b60baa670fe86fabe63e6b5752be0109 |
| SignatureGate-Appsmith/chatgpt_development | 2746b2712f2bd91b508c1d58f7025ce444abef78 |
| SignatureGate-Appsmith/master | 0b7739f2a4a20ef89808d2c76658682b3a1c39c4 |
| SignatureGate-Appsmith/production_development | 7c0a7e7cc48e5b522744bb0b934b636b9eb4857f |

The development-to-master snapshot differs across **818 files**. This is a coordinated application release, rather than another isolated Cash Deposits cherry-pick. Re-fetch these refs before implementation or promotion.

Checks actually performed for this plan:

- **make validate** and **make release-check** passed in SignatureGate.
- All **708 Appsmith JSON files** parsed.
- All **14 Appsmith JS objects** passed Node JavaScript syntax checks.
- No remaining literal Members - Directory page-name references were found in current Appsmith page files, including the dash variants checked.
- Reports now contains both **qCurrentFacilitator** and **qReportTimeSeries**.
- A source scan found **175 table-column expressions with bare generated fallback identifiers** across ten pages. This is a source-pattern count, not a measured live Appsmith linter count. These need contextual repair and import/pull verification.
- **202 SQL actions** reference **signaturegate-postgres-test**. The exported datasource is a descriptor; its actual database connection must be verified in Appsmith.
- Both Individual Profile and Company Profile are still directly visible in navigation.
- Members – Intake still exists and is visible.
- No Appsmith-specific validation scripts, Makefile, or CI workflow are present in the inspected Appsmith tree.

The recent user-verified Company Profile repair is the working baseline: recreating its JS object in Appsmith restored page-load execution. Preserve the recreated object and its Appsmith-generated registration metadata. Do not normalize its execution settings just because earlier exported metadata appeared inconsistent.

Production database state, deployed n8n/RootedOps versions, Appsmith runtime linter state, and the complete live permissions matrix have **not** been inspected during this planning pass.

## Issue completion matrix

| Issue | Evidence available now | Work needed to reach closure |
| --- | --- | --- |
| [SignatureGate #17](https://github.com/RayzorDuff/SignatureGate/issues/17) — Cash Deposit Management | Latest issue comment reports a real production batch, preparation/confirmation, date correction, ERP bank-account choices, and successful downstream reconciliation. Operational work is substantially implemented. | Verify every donor type, exclusions/revival, print output, exact totals, concurrent assignment prevention, prepared vs actual deposit date, audit records, and confirmed composition immutability on the final candidate. Reconcile the original criteria with later scope comments separating ERP ownership into #18. |
| [SignatureGate #18](https://github.com/RayzorDuff/SignatureGate/issues/18) — RootedOps/ERPNext synchronization | Latest comments report successful production Journal Entry creation and Bank Transaction reconciliation, preserved failed attempts, stable idempotency, retries, and non-writing development mode. | Retain that evidence; verify retry/idempotency, failure recovery, synchronization status, correction/reversal policy, and already-confirmed batches missing ERP documents. Confirm deployed RootedOps/n8n compatibility and production routing. |
| [SignatureGate #19](https://github.com/RayzorDuff/SignatureGate/issues/19) — Independent contributor identity | Directory/profile/intake consolidation and contributor actions are present; recent work adds identity notes and richer collision reporting. Contact reassignment has earlier live verification. | Full acceptance audit across all identity/capacity combinations, migration integrity, Givebutter resolution, contact ownership, membership ending/re-entry, company contacts, notes, mailing preferences, practitioner scope, and contributor reporting. Retire Members – Intake after parity tests. |
| [SignatureGate #20](https://github.com/RayzorDuff/SignatureGate/issues/20) — Configurable terminology | Terminology registry, administration page, and inventory exist. An October 10 comment adds **Member → Participant** to the display migration. | Complete active UI/generated-text terminology, including Participant labels and navigation; demonstrate an alternate configuration without source edits; update the Documenso inventory and documentation. Preserve internal identifiers and historical signed documents. |
| [SignatureGate-Appsmith #2](https://github.com/RayzorDuff/SignatureGate-Appsmith/issues/2) — Agreement Type administration | Agreement Types can be listed/selected, but the inspected Agreement Templates page has no Agreement Type creation form or creation action. | Implement authorized, audited creation with type key, display name, sort order, and active state; validate required fields/duplicate keys; verify empty-table setup and selector refresh. |
| [SignatureGate-Appsmith #4](https://github.com/RayzorDuff/SignatureGate-Appsmith/issues/4) — Grouped navigation | Current export still has flat native navigation and visible profile pages. Unauthorized and event pages are already hidden; Agreements - Queue is also hidden. | Inspect installed Appsmith capabilities, choose and document a maintainable grouped-menu approach, implement capability-aware entries, hide context-dependent profiles, preserve routes, and test Git synchronization, keyboard access, and ordinary mobile widths. Do not expose unfinished event/queue pages automatically. |
| [SignatureGate #23](https://github.com/RayzorDuff/SignatureGate/issues/23) — Git-sync regression | Its two missing Reports SQL actions now exist. Members - Directory has been retired and replaced by Directory, whose loader catches query failures. | Original missing-source defect appears repaired and legacy-directory portion is superseded. Confirm Reports execution and Directory refresh/profile navigation in the deployed candidate before closing. Remaining canonical-role and report-category work belongs in #19/#20 unless the original regression still reproduces. |

## Phase 1 — Establish the complete acceptance and deployment inventory

**Purpose:** turn the broad issues into a bounded list of missing implementation, missing evidence, and deployment dependencies.

1. Preserve all current Appsmith editor commits and the working Company Profile object. Record exact Git SHAs, deployed Appsmith version, current production app revision, database versions, and n8n/RootedOps revisions.
2. Build one acceptance ledger. Each row records issue, requirement, owning repository, implementation location, test evidence, environment, and status: **implemented and verified**, **implemented but unverified**, **missing**, or **explicitly out of scope**.
3. Review issue bodies and later comments together. In particular:
   - #17 owns cash custody; #18 owns cross-system accounting.
   - #19's canonical contributor identity supersedes older donor-as-member wording.
   - #20 includes both Spiritual Practitioner and Participant display changes.
4. Inventory every current page, incoming route parameter, selected-record store key, SQL/API action, capability check, hidden state, and integration credential.
5. Obtain read-only schema/function inventories from both **signaturegate_test** and **signaturegate**, plus upgrade/application records if available. Compare effective function bodies, signatures, views, constraints, triggers, and seed/configuration data with the canonical target.
6. Inspect the actual RootedOps ERP sync/bank-account workflows and deployed credentials. The successful #18 issue comments are valuable acceptance evidence, but do not identify the exact currently deployed version by themselves.

**Deliverables:** versioned acceptance ledger, page/action inventory, environment map, migration inventory with checksums and dependency evidence, and changelog/export baseline audit. A deployable ordered migration manifest requires actual database comparison; do not label a source-only candidate order production-ready.

**Exit gate:** every issue criterion has an owner and a disposition; production differences are known. Reconstruct any required upgrade missing from the current migration directory before planning deployment.

## Phase 2 — Complete functional consolidation and Agreement Type administration

**Purpose:** finish #19 and Appsmith #2 before final navigation and terminology cleanup.

- Verify the unified Directory's four actions: View Profile; Member/Participant Functions; Contributor Functions; Sacrament Release. Eligibility and authorization must both be enforced. Companies and contributor-only individuals cannot obtain sacrament-release eligibility.
- Verify Individual and Company Profile identity editing, canonical contacts, addresses, provider matching references, audited notes, archive/reactivation, and correct selected-record behavior.
- Finish Intake parity: two contact methods, stronger email validation, optional DOB, individual/company capacities, paper and digital agreement paths, practitioner assignment, independent mailing choices, and detailed accessible/inaccessible collision reporting.
- Test legacy member-note migration to people, preservation of existing identity notes and original member notes, safe reapplication, blank/changed/cleared notes, required reasons, and access/audit behavior. The current notes verification script checks object existence only; add meaningful behavior/backfill coverage.
- Verify membership can be added or ended without changing contributor IDs or historical donations, agreements, and audit records. Contributor status changes must not silently change membership.
- Verify all Givebutter resolution options: existing individual/company contributor, linked participant, new individual/company contributor, new participant with linked contributor, and ignore/reject as appropriate. Ambiguous provider matches must remain unresolved.
- Complete reporting categories required by #19: individual, organization, anonymous, unresolved, and currently linked/unlinked identities. Current Reports metrics retain member-linked/anonymous summaries and exclude unresolved records; they do not supply the complete requested breakdown.
- Review canonical actor authorization across Reports, Agreement Templates, cash entry, review, and deposits. Some queries still require a legacy active member/facilitator identity; test reviewers and practitioners whose canonical person account has no active membership.
- Restore/verify a scoped manual-cash entry path for practitioner-only users and read-only donation history for assigned participants. Current Contributor Functions entry guard requires a reviewer role, so this requirement needs a concrete permitted path without exposing organization-wide financials.
- Implement Appsmith #2 with an authoritative authorization check and atomic audit on creation. Verify duplicate type keys and empty Agreement Type setup.
- Remove Members – Intake only after all parity cases pass. Audit page links, selectors, SQL actions, JS registrations, and application page entries afterward. Retain email reads needed for agreement delivery; remove obsolete actions only after checking their consumers.

**Exit gate:** required participant/contributor/company workflows work on the test database; legacy Intake adds no essential capability; Appsmith #2 passes all six acceptance criteria.

## Phase 3 — Finish terminology and navigation together

**Purpose:** complete #20 and Appsmith #4 against the finalized page set.

- Audit visible text, headings, columns, messages, selectors, tooltips, generated emails, operator documentation, and new audit rendering. Consume centralized singular/plural labels for **Participant** and **Spiritual Practitioner**.
- Keep stable internal keys such as member_id and facilitator compatibility fields where still needed. Display labels must not determine permissions or rewrite historical records.
- Demonstrate at least two terminology configurations, including one displaying Facilitator, and prove labels change without source editing or relationship changes.
- Update the terminology and Documenso inventories to reflect the actual current pages. Inventory existing templates/recipient roles and the future approved Spiritual Practitioner Agreement handoff. Legal/board agreement approval remains outside this release; historical executed agreements retain their wording.
- Determine whether the deployed Appsmith version supports the requested grouping. If a custom component is required, define one source and a documented generation/synchronization process for page copies.
- Use the proposed workflow groups as a starting point: People & Organizations; Membership & Practice; Contributions; Reporting & Administration. Include Events or Agreements Queue only when their active workflows and permissions warrant exposure.
- Hide Individual Profile and Company Profile from direct navigation; preserve Directory entry and Back to Directory. Define behavior for a fresh direct link, missing/invalid ID, inaccessible party, and stale saved selection.
- Preserve Unauthorized as hidden. Exclude retired pages and prevent stale routes from reopening them.
- Test every menu/action for each relevant role and on narrow screens, including keyboard operation and active-page indication.

**Exit gate:** active user-facing terminology follows configuration; navigation is maintainable and correctly scoped; both profile pages initialize after a pull/reload without manual JS execution.

## Phase 4 — Validate the development release candidate

**Purpose:** establish code completion before any production switch.

Run the complete relevant database regression suite on an isolated target. Use both a **fresh canonical-schema database** and a **restored production copy upgraded through the release manifest**. The second case detects upgrade defects that a fresh bootstrap cannot reveal.

The repository's rollback-only verification scripts belong on test/disposable databases. Do not run the synthetic-data suite on production merely because it rolls back.

| Test group | Required cases |
| --- | --- |
| Identity and capacities | Participant-only; contributor-only individual; dual capacity; company; former participant; archived contributor; duplicate/ambiguous identity. |
| Permissions | Practitioner-only; document reviewer; donations reviewer; directory manager; combined roles; unauthorized user; canonical actor without active membership. |
| Contacts and notes | Add/archive/primary/verify; purpose reuse and reassignment; company contacts; historical-note backfill; blank/update/clear; audit and denied access. |
| Intake and mailing | Every supported pair of contact methods; malformed email; optional DOB; duplicate blocked/warned; restricted collision messaging; opt-in/out and dual-capacity subscription behavior. |
| Agreements and releases | Digital/paper creation; upload; approve/reject/cancel; reviewer on behalf; practitioner attribution; release eligibility, storage/product access and voiding; donations do not affect eligibility. |
| Contributions | Identified individual/company; anonymous; unresolved Givebutter; verify/reject/reassign; historical attribution after membership change; all reporting categories. |
| Deposits | Mixed donors; ineligible exclusion; add/remove/re-add; competing batch assignment; exact cents/snapshots; print/tally; prepared/actual dates; confirmation; audited exceptions/revival; confirmed composition protection. |
| ERP integration | Non-writing development route; canonical bank-account choices; succeeded/failed/processing states; repeat delivery/idempotency; retry; date-correction boundary; reconciliation status; missing ERP-document detection. |
| Navigation/runtime | Four Directory actions; direct/deep links; Back; refresh; role changes; no-selection states; fresh page load and record A → B switches. |

Appsmith checks must include all active pages, empty table results, and denied-access results:

1. Repair remaining linter errors and generated fallback references with contextual tests.
2. Check widget/query/JS references, registered methods, metadata/body consistency, route names, prepared parameters, and execution dependencies.
3. Pull in Appsmith, reload, exercise the workflows, commit editor-generated metadata, and re-pull. A fix that disappears after synchronization fails this gate.
4. Verify Company Profile's recreated object remains registered and runs on navigation; do not repeat earlier speculative metadata changes.
5. Re-run SignatureGate validation/release checks and add focused Appsmith source checks for recurring defects.
6. Verify #23's original failures no longer reproduce. Close its retired-directory portion as superseded and missing-Reports-source portion as fixed only with recorded runtime evidence.
7. Audit the master/development diff for production hotfixes, datasource differences, hidden states, integration URLs, dependencies, and test-only behavior. Preserve existing production fixes.

**Exit gate:** no unresolved active-page linter/runtime defects or unmet in-scope acceptance criteria; passing tests are tied to exact candidate SHAs. Mark issues code complete, with production verification still pending.

## Phase 5 — Prove and apply the production database upgrade

**Purpose:** ensure the database supports the final application before its operational datasource changes.

Build an explicit dependency-ordered manifest; do not blindly run every migration alphabetically. Earlier files use CREATE OR REPLACE FUNCTION and can overwrite later behavior when replayed out of order.

The current migration surface contains these **15 files**; inclusion here does not establish whether they are pending in production:

| Area | Candidate migration files |
| --- | --- |
| Deposit base/lifecycle/output | cash_deposit_management.sql; cash_deposit_batch_lifecycle.sql; cash_deposit_batch_tally.sql; cash_deposit_batch_print.sql |
| ERP and confirmed-date correction | cash_deposit_erp_sync.sql; cash_deposit_confirmation_correction.sql |
| Reconciliation exceptions and financial access | cash_donation_reconciliation_exceptions.sql; cash_donation_reconciliation_revive.sql; donation_financial_access.sql |
| Canonical identity/roles/contact administration | person_role_self_assignment.sql; organization_contact_reassignment.sql; member_agreement_reviewer_on_behalf.sql; party_identity_notes.sql |
| Mailing integration | listmonk_contributor_email_support.sql; listmonk_dual_capacity_contributor_email.sql |

**db/README.md lists only eight pending migrations and still contains pre-deployment language despite later production acceptance comments.** Update it from evidence. The historical #19/#20 migration chain has been removed from the active installation surface, so the fifteen files alone may not upgrade an older production schema to the target. Compare the actual database and reconstruct a forward upgrade for any missing canonical objects/backfills. Add new migrations for work completed in Phases 2–3 where required.

Each manifest entry records path, checksum, prerequisites, effective object/data preconditions, already-applied evidence, transactional strategy, verification, and recovery procedure. Verify function bodies and data invariants, not just names.

Execution order:

1. Back up production and verify a restore into an isolated database.
2. Rehearse the exact upgrade against that restored copy; compare row counts, IDs, donor classifications, contributor/member links, notes, contacts, signed-document references, confirmed batch snapshots, audit history, and ERP source/document identities.
3. Run relevant behavioral tests there and verify final effective definitions match the intended target.
4. Coordinate workflow workers with changed queue/schema contracts so they cannot execute half an upgrade.
5. Apply only the reviewed required upgrade steps to **signaturegate**, stopping on errors and recording each successful step.
6. Run production-safe read-only structural and data-integrity verification. Confirm deployed n8n credentials/versions, Listmonk list configuration, Documenso mappings, and RootedOps APIs are compatible.
7. Confirm the existing production application remains functional through the database-first transition.

Do not load **db/schema.sql** over existing production as an upgrade. It is the bootstrap definition. Do not copy test records, test queue events, or test configuration wholesale into production.

**Exit gate:** production has every required effective database change and preserved historical data; the upgrade record and dependency configuration are complete.

## Phase 6 — Switch the candidate to production configuration and promote to master

**Purpose:** release the tested code with an explicit environment delta.

Production migrations precede the datasource switch. Freeze the candidate while this occurs.

1. Create a release checkpoint of the validated development code and record the test-bound revision.
2. Produce the production-bound candidate from that checkpoint. The required delta includes:
   - All PostgreSQL actions bind to the production **signaturegate-postgres** datasource, whose actual database is **signaturegate**.
   - Cash deposit Confirm and Retry ERP Sync use **production** mode. Both currently pass **test** explicitly in development; the API metadata's production fallback does not override that explicit argument.
   - n8n, NocoDB, upload, Documenso, Listmonk, and external product routes/credentials resolve to their intended production services.
   - Test actor/record IDs, flags, synthetic events, and environment-specific seed assumptions are absent from the production candidate.
3. Keep datasource identity consistent with master's production datasource; changing a display name does not prove the connection changed. Verify the live connection using a read-only **SELECT current_database()** through Appsmith.
4. Pull and review the candidate's exported action bindings and runtime initialization after the environment delta. Initially exercise production only through read-only profile/history/report/navigation checks.
5. Merge the exact production-bound candidate into **master**, resolve conflicts while preserving production fixes, then pull master in Appsmith and publish.
6. Verify the published application's production bindings and ERP mode again. A Git merge by itself does not establish a published release.
7. Retain a test-bound development checkpoint or restore test bindings for subsequent development in a separate follow-up commit. The production delta must not turn future test work into production writes.

If Appsmith requires an intermediate branch for environment-specific configuration, use a release branch from the validated development SHA. It is only a packaging step: all functional development still completes on chatgpt_development, and master receives that verified implementation plus the documented production delta.

**Exit gate:** published master corresponds to the recorded candidate, uses production database/services, and includes no lost production fixes or test-mode ERP calls.

## Phase 7 — Production acceptance, documentation, and issue closure

- Confirm Directory loading and all eligible actions, Individual/Company page initialization, scoped access, Reports, Agreement Types, agreements/releases, contributor history, navigation, and terminology in published mode.
- Reuse the established #17/#18 production success evidence and check it against the new release. Perform the next legitimate operational transaction under the normal workflow; do not create synthetic live donations, signed agreements, or accounting entries solely for a smoke test.
- Check successful ERP event/document identity and reconciliation, failure visibility, and no duplicate accounting. Monitor the integration and mailing queues through their normal processing cycles.
- Record database-upgrade verification, final Git SHAs, Appsmith published revision, RootedOps/n8n compatibility, remaining external dependencies, and operator instructions.
- Complete the v1.2.0 changelog reconciliation since v1.1.0 and Appsmith-specific first-release notes. Run the pinned-source export action described above and verify its resulting JSON commit. Follow SignatureGate's version/release process: VERSION, README, CHANGELOG, release notes, packaged JSON, recorded source revisions, and release tag must agree.
- Close each issue against its own acceptance evidence. #20's legal/board template replacement remains a separately identified external follow-up, not unfinished software hidden by closure.
- Close #23 with a concise account of the repaired Reports source and the retired legacy Directory, including current runtime evidence.

**Exit gate:** every scoped issue has a requirement-to-evidence record and the production release is verified.

## Recovery and stop conditions

Before publication, retain the previous master/Appsmith revision and the tested backup/restore procedure.

- If production database verification fails, stop before rebinding/publishing.
- If published UI behavior fails, restore the prior application revision when compatible with the upgraded database. Keep additive migrations when safe; do not undo newly recorded production activity blindly.
- Physical deposit confirmation remains authoritative even when ERP posting fails. Retry the durable source event; do not recreate the deposit or accounting record.
- Preserve signed agreements and append-only audit history through recovery.
- Restore a whole production database only with a reconciled plan for activity since the backup; data loss is not an acceptable shortcut.

## Recommended execution order

**Acceptance inventory → functional gaps and Agreement Types → terminology and navigation → full development acceptance → production upgrade → production configuration and master publication → production verification and closure.**

This pass produced the initial source assessment and this plan. Implementation repairs, live database verification, migration execution, datasource changes, publishing, and issue closure remain work items in the phases above.

