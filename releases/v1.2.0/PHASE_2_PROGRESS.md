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

Complete reporting categories, practitioner-scoped cash/history access, remaining canonical actor paths, company contact-person representation, live notes/`Intake` acceptance, `Intake` parity and membership/provider-resolution regressions. Legacy `Members – Intake` remains until parity is proven. The 175 source fallback findings and obsolete upload reference remain tracked for contextual repair and runtime acceptance.

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
