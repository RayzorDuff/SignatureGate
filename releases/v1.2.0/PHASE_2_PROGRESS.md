# Phase 2 progress — Agreement Types and packaging prerequisites

Status: **in progress; unreleased**. Development is authorized while the [Phase 1 live evidence gate](PHASE_1_VALIDATION.md) is gathered. No production migration, datasource switch, publication or release tag has been performed.

## Candidate provenance

SignatureGate-Appsmith `chatgpt_development`: `f08296a84ea30b20dbf948f0260426e832890c9c` (first Phase 2 increment, based on `2746b2712f2bd91b508c1d58f7025ce444abef78`). Backend changes are the SignatureGate commit containing this document, based on `71c08610013322d1bacfe9ac294ff4b2a1996e49`. These source revisions have not been observed as deployed.

New migration SHA-256: `574a862369297919a3d0b062acd9341ce6aaecc95edd01e139808939c6524abd`.

## Implemented

- Agreement Templates has a document-reviewer-only Agreement Type form with key, display name, description, integer sort order and active state. It rejects blank/invalid fields and duplicate active or inactive keys; successful creation resets the form and refreshes type selectors. Failed creation preserves input. A refresh failure reports that creation succeeded so operators do not repeat the write.
- `public.create_agreement_type(...)` checks the canonical document-reviewer account, independently of membership, normalizes key/name, rejects duplicates and atomically records creation and `agreement_type.created` audit details. An audit failure rolls back creation. The Appsmith action passes the signed-in email directly, rather than a form parameter or stored actor.
- Agreement Templates uses the canonical actor lookup and accepts authorized people without membership. Other pages' legacy actor lookups remain separate Phase 2 work.
- The Appsmith exporter retains flat/nested datasource descriptors, `jslibs`/legacy library descriptors and widgets nested beneath embedded canvases. Conflicting dependency descriptors and unattached widgets fail generation. The export workflow now runs preservation fixtures, exact-source semantic checks and release asset checks before committing generated JSON.
- Fresh-bootstrap validation found malformed dollar quotes in two existing donation-financial permission helpers in `db/schema.sql`; their delimiters are repaired without changing their logic.
- Terminology validation keeps the two current Individual Profile role controls mandatory. Five retired practitioner-assignment controls are validated when present in an older export. Four of the earlier fourteen findings were caused by the exporter dropping the two existing role controls; ten were obsolete checks for the five removed controls.

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
| Phase 1 catalog collector SQL | Executes successfully on isolated canonical PostgreSQL; actual test/production captures remain pending |
| Repository checks | `make release-check`, all 722 Appsmith JSON parses, all 14 JS syntax checks and `git diff --check` pass |

This is isolated behavior and source evidence. It does not certify deployment on PostgreSQL 16, actual Appsmith form layout/permissions, prepared-query execution, import compatibility, Git synchronization or publication. Live acceptance remains required before Appsmith #2 closes.

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
6. Import the freshly generated candidate into a disposable Appsmith application and verify dependencies and nested role widgets. Retest Company Profile initialization after the pull.

Record deployed backend/frontend SHAs, Appsmith/PostgreSQL versions, actor roles and evidence in the acceptance ledger. Add this migration, with checksum and verified prerequisites, to the production manifest only after Phase 1's actual comparison and restored-copy rehearsal.

## Remaining Phase 2 work

Complete reporting categories, practitioner-scoped cash/history access, remaining canonical actor paths, company contact-person representation, behavioral notes/backfill coverage, Intake parity and membership/provider-resolution regressions. Legacy Members – Intake remains until parity is proven. The 175 source fallback findings and obsolete upload reference remain tracked for contextual repair and runtime acceptance.

## Linode validation follow-up

The fresh bootstrap now closes the transaction opened by the appended ERP synchronization section. Without that closing COMMIT, psql disconnect would discard that section and later additions. Bootstrap persistence and Agreement Type behavior without a prerequisite migration pass on isolated PostgreSQL. The Linode helper verifies both release APIs through a separate psql connection before collecting the canonical catalog. See [LINODE_VALIDATION_COMMANDS.md](LINODE_VALIDATION_COMMANDS.md) for commands and deployment evidence tools; no current database has been changed by these tools here.
