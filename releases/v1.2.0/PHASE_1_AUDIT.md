# v1.2.0 Phase 1 acceptance and deployment audit

Audit date: October 11, 2026. **The source/issue inventory is complete; the Phase 1 live deployment exit gate remains open.** No database connection, migration, datasource change, Appsmith publication, issue closure or release tag was performed during this audit.

The committed release plan is [`RELEASE_PLAN.md`](RELEASE_PLAN.md). All seven scoped issues were fetched with their current bodies and comments. Exact requirement text, source references, owners, implementation locations, verification, status and next phase are in [`ACCEPTANCE_LEDGER.csv`](ACCEPTANCE_LEDGER.csv). Source hashes and comment references are in `evidence/issue_sources.json`.

## Pinned source baseline

| Repository/ref | SHA |
| --- | --- |
| SignatureGate implementation before release-plan documentation | `9fb5aa53b60baa670fe86fabe63e6b5752be0109` |
| SignatureGate v1.1.0 tag | `654b02c00dd39165a65a6ab3aebd28455264b70a` |
| SignatureGate release-plan commit | `f6372147cb247f6fc62410643e4bdc456d278ac6` |
| SignatureGate-Appsmith `chatgpt_development` | `2746b2712f2bd91b508c1d58f7025ce444abef78` |
| SignatureGate-Appsmith `master` | `0b7739f2a4a20ef89808d2c76658682b3a1c39c4` |
| SignatureGate-Appsmith `production_development` | `7c0a7e7cc48e5b522744bb0b934b636b9eb4857f` |

There are 176 SignatureGate implementation commits since v1.1.0. Appsmith has no prior release tag. Development differs from master across 818 paths with Git's rename detection, or 1,118 added/modified/deleted paths without rename detection. The latter explicit inventory is in `evidence/appsmith_master_changes.csv`; it captures removals that a rename summary can obscure.

## Requirement dispositions

The 97 rows include each acceptance clause from issue bodies, #17's extended anonymous-cash criteria, #23's original defects, later scope/user decisions, and coordinated release dependencies.

| Status | Rows | Meaning |
| --- | ---: | --- |
| `implemented_unverified` | 46 | Code exists; source/test files do not prove current runtime acceptance |
| `reported_verified` | 7 | Prior issue/user evidence reports working behavior; final candidate still needs regression |
| `missing` | 14 | No complete implementation identified |
| `partial` | 17 | Part of requirement exists; completion or coverage remains |
| `pending_environment` | 6 | Requires actual deployed-version/database evidence |
| `scope_preserved` | 5 | Explicit boundary retained; does not substitute for functional testing |
| `superseded` | 2 | Legacy requirement replaced by later approved model/page retirement |

Code files and tests in the ledger are navigation aids, not claims that those tests ran. #17 and #18's production deposit/reconciliation reports are retained. Their accounting details are not copied into release documentation. #23's missing Reports source is restored, and its Members Directory portion is superseded; current runtime Reports execution remains unverified.

## Concrete work queue

| Priority / next phase | Work | Acceptance/evidence |
| --- | --- | --- |
| Phase 2 | Add audited, authorized Agreement Type creation with key/name/order/active fields | Appsmith #2: all six clauses, including empty-table setup, selector refresh and duplicate keys |
| Phase 2 | Complete Reports individual/company/anonymous/unresolved and current linked/unlinked categories | SG19-AC10; current SQL excludes unresolved and uses compatibility donation.member_id for member summaries |
| Phase 2 | Restore practitioner-only scoped/anonymous cash entry and assigned-participant read-only donation history | SG17-EXT01 / SG19-S07; Member Functions no longer has donation actions, while Contributor Functions requires a reviewer |
| Phase 2 | Reconcile canonical person-based authorization with remaining legacy member/facilitator actor queries | SG19-S06; Reports, Agreement Templates and Cash Deposits still use legacy actor lookup; financial helpers require active member/facilitator reviewer flags |
| Phase 2 | Verify company contact-person association, distinct from organization contact methods | SG19-S02; no explicit association workflow identified; confirm intended representation |
| Phase 2 | Strengthen notes migration/behavior verification, then validate Intake parity and retire legacy Intake | SG19-S03/S04/S05; notes test currently checks objects only; migration lacks explicit transaction and changed-source rerun needs protection |
| Phase 3 | Finish configured Participant/Spiritual Practitioner display text and external terminology inventory | #20 including October 10 Participant extension; demonstrate alternate configuration without code edits |
| Phase 3 | Establish installed Appsmith navigation capability, implement maintainable groups and hide profiles | Appsmith #4; preserve role checks, Directory selection, fresh/deep-link behavior and Git sync |
| Phase 4 | Repair source linter defects and validate fresh exported candidate | REL02/REL04; exact current-source findings below |
| Phase 4 / packaging prerequisite | Fix datasource/library export collection and add semantic preservation checks | REL03; final export must retain four datasource descriptors and the jsPDF library |
| Phase 1 then Phase 5 | Compare actual test/production catalogs and reconstruct only necessary forward upgrades | REL01/REL07; retained migration directory alone is not a production upgrade manifest |
| Phase 6 | Switch exact candidate to production DB/services and ERP mode, publish master, generate pinned JSON and finalize changelogs | REL05/REL06 / SG18-S01; do not export/release test-bound development as production |

## Application and action inventory

The current source contains 18 pages, 335 actions (202 DB, 19 API, 114 JS function actions), 14 JS objects, four datasource descriptors and one jsPDF descriptor. Page inventory includes visibility, initialization flags, route/store references and role terms; action inventory includes binding, execution flags, explicit parameters and public function references.

The lexical role-term inventory is not a proof of permission enforcement. Literal route extraction does not resolve conditional/external URLs; the Directory's conditional profile route is reviewed separately below. Appsmith-generated execution metadata records current exported settings and must be preserved where verified in the editor. In particular, do not normalize Company Profile metadata speculatively.

| Directory action | Destination | Selection passed | Eligibility checked in current JS |
| --- | --- | --- | --- |
| View Profile | Individual Profile / Company Profile | `person_id` / `organization_id`; corresponding saved profile ID | Valid party ID/type; downstream accessible-directory query |
| Member Functions | Member Functions | `member_id` in URL and store | Active individual membership |
| Contributor Functions | Contributor Functions | `contributor_id` in URL; `donation_donor_selection=contributor:<uuid>` | Active contributor, individual or organization |
| Sacrament Release | Sacrament Release | `member_id` in URL | Active individual membership; downstream agreement/storage authorization |

The profile pages remain visible in navigation. Members – Intake is present and visible; Members - Directory is absent. Agreements - Queue, both Events pages and Unauthorized are hidden. New grouped menus should not expose dormant pages simply to complete a group.

The user has verified Company Profile initialization after recreating its JS object. Individual Profile also worked in that testing. Test their current registrations after any further editor pull/reload rather than overwriting their metadata based on older guesses.

## Static checks actually performed

- Existing SignatureGate `make release-check` passes against the currently bundled JSON and 1.1.0 release metadata.
- All 708 Appsmith JSON files parse; all 14 JS objects pass Node syntax checks.
- Read-only datasource verification scans all 335 action metadata files and confirms all 202 PostgreSQL references use `signaturegate-postgres-test`.
- The inventory finds 175 generated table-column fallback expressions ending in bare identifiers across ten pages. These are concrete candidate linter repairs, not a measured runtime error count.
- `Individual Profile/apiUploadIndividualEvidence` still refers to nonexistent `FilePickerIndividualAgreement.files`, in both query text and JSON body. Investigate consumers before repairing/removing the obsolete action.
- No query-body/metadata drift was detected by the inventory's separate-body comparison.
- A fresh export was generated into scratch for analysis, not committed over the product JSON.

| Page | Bare table fallback properties |
| --- | ---: |
| Member Functions | 46 |
| Cash Deposits | 41 |
| Facilitator Functions | 21 |
| Agreements - Queue | 12 |
| Audit Log | 11 |
| Agreement Templates | 10 |
| Company Profile | 10 |
| Directory | 10 |
| Sacrament Release | 8 |
| Reports | 6 |

The fresh export has 18 pages, 335 actions and 14 collections but **zero datasource entries and zero custom libraries**. `appsmith-export.mjs` enumerates directories inside `datasources/`, while the actual descriptors are flat files; it looks under `customJSLibs/`, while the current jsPDF descriptor is under `jslibs/`. This would omit required packaging dependencies even when JSON shape checks pass.

The same fresh export produces 14 release-validator findings: seven removed Individual Profile widgets are still required by the terminology checks, once each for published and unpublished pages. Their names are `txtIndividualPractitionerManagementNote`, `selIndividualPractitionerToAssign`, `btnAssignIndividualPractitioner`, `txtPersonAccessCurrent`, `tblIndividualPractitionerAssignments`, `txtIndividualPractitionersHeading` and `selPersonAccessRole`. Reconcile the checks with approved final page ownership and retain meaningful configuration coverage. Do not simply delete terminology validation to make packaging pass.

Existing release checks therefore do **not** validate the current split Appsmith tree. The exporter and validator need repair before first-release JSON generation, followed by Appsmith import/pull and actual runtime tests. No synthetic data or external operations were executed by this source audit.

## Deployment and changelog evidence

[`ENVIRONMENT_AND_MIGRATIONS.md`](ENVIRONMENT_AND_MIGRATIONS.md) includes the environment map, migration dependency inventory, safe read-only capture commands and the unresolved upgrade gate. Every migration has a SHA-256 checksum in `evidence/migrations.csv`. Overlapping function definitions make alphabetical replay unsafe.

[`CHANGELOG_AUDIT.md`](CHANGELOG_AUDIT.md) maps substantive changes since the real v1.1.0 tag to existing/missing changelog coverage. Current Unreleased entries are substantial but omit a complete description of cash deposit lifecycle/printing, exclusions/revival, contributor Listmonk behavior, identity notes and the recent split-tree page consolidation. Final coverage must include subsequent implementation and the first Appsmith release.

## Evidence and reproducibility

| File | Contents |
| --- | --- |
| `ACCEPTANCE_LEDGER.csv` | 97 requirement rows and remaining verification |
| `evidence/source_summary.json` | Exact revisions and source counts |
| `evidence/pages.csv` | All pages, visibility, routes/state references and current initialization |
| `evidence/actions.csv` | Every action's datasource, execution, params, API path and function references |
| `evidence/routes.csv` | Literal internal route targets and their presence |
| `evidence/source_findings.csv` | Exact JSON/property locations for fallback/missing-widget findings |
| `evidence/migrations.csv` | 15 migration checksums, defined objects and transaction markers; applied state unknown |
| `evidence/js_syntax.csv` | All 14 syntax-check results |
| `evidence/issue_sources.json` | Current issue/comment references and content hashes |
| `evidence/commits_since_v1.1.0.csv` | 176 exact SignatureGate history entries |
| `evidence/appsmith_master_changes.csv` | Explicit development/master path changes |

Regenerate the source inventories with both checkouts at the intended candidate revisions:

```bash
python3 releases/v1.2.0/audit_source.py \
  --appsmith ../SignatureGate-Appsmith \
  --output releases/v1.2.0/evidence
```

The ledger/history files are the reviewed baseline; re-review them against subsequent commits rather than silently treating them as current forever. The source script deliberately records the initial implementation/tag baseline separately from the current Appsmith revision.

## Phase 1 exit gate

All issue criteria now have an owner and a recorded disposition. Source-level inventories and release dependencies are checked in. **Production differences remain unknown**: obtaining test/production inventories and deployed version evidence is still required before Phase 1 is marked complete or any ordered manifest is approved. Functional gap work can proceed on the test-bound development branch while that read-only evidence is gathered.
