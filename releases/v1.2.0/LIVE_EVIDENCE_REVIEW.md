# v1.2.0 deployment evidence review

Reviewed October 11, 2026. **Phase 1 remains open; independent Phase 2 work continues against test.** No production migration or publication is authorized by a catalog comparison alone.

## Privacy boundary

Raw operational evidence stays outside both Git repositories. Public release records contain software versions, source revisions, technical database object identifiers, aggregate structural findings and validation status only. Technical software names, database/schema/API identifiers, workflow names, filenames, environment-variable names, source revisions and acceptance criteria may be documented. Rooted Psyche and Dank Mushrooms may be named. Do not commit actual first-name/last-name combinations of individuals, other company names captured in operational records, contact details, financial values, account identifiers, product names/types, operational notes, secret values or live template/list/account mappings. Do not paste raw definitions or command logs into issues: definitions may contain operational literals. Synthetic regression fixtures are explicitly artificial and contain no captured records.

## Evidence received

All 19 manifest checksums in the submitted archive verified. The canonical and deployed inventories were captured using SignatureGate `18be29cd916f99215c1cc3794c5cdd8f10ac567b`. The deployed captures preceded the operator's subsequent Agreement Type migration.

| Observation | Result / boundary |
| --- | --- |
| PostgreSQL | 16.13 across canonical, test and production; fresh canonical bootstrap persisted on this server |
| Appsmith | Community v2.4.2, confirmed by UI and image metadata |
| n8n | 2.16.1, confirmed by UI and deployed evidence |
| Services | All seven captured service containers running; running status does not establish route compatibility |
| Deployed custom application fingerprint | 89 tracked files compared; one differs. Effective deployed revision remains subject to private review |
| n8n publication | 83 draft workflows, 19 active; published export supported and 19 published active workflows captured. Credential destinations and dynamic route targets remain subject to private review |
| Agreement Type backend | Operator reports migration and rollback-only behavioral SQL test passed on `signaturegate_test` |
| Agreement Type frontend | Operator reports pulling `chatgpt_development` and successfully creating a type through the new form on `signaturegate_test`. Complete permission/layout/import/Git round-trip acceptance is still pending |
| Operator evidence form | Submitted form retains PENDING fields; it does not establish production publication SHA, production datasource proof, credential target/mode or live mapping compatibility |

No created type key/name, actor identity or operational values have been recorded here.

## Structural disposition

The original comparison has **82 differences**, not 82 required migrations. Reference counts: canonical 43 relations / 578 columns / 145 functions; test 43 / 578 / 143; production 43 / 576 / 141. All three share eight views, 179 constraints, 51 triggers and 144 indexes at capture time.

| Environment | Differences | Disposition / next action |
| --- | --- | --- |
| Test | One missing `create_agreement_type(text,text,text,integer,boolean,text)` | Subsequent migration/behavior passed; definition capture confirms intended API and refreshed test catalog received |
| Test | One missing `revive_cash_donation_from_deposit(uuid,uuid)` | Release work remains: existing two-argument API does not require a new revival reason. Implement the final behavior before choosing its forward migration |
| Test and production | Four changed function hashes per environment | Effective definitions received. Exclusion and role bodies match intended source; test agreement body also matches. Production needs reviewer-on-behalf agreement update. Deployed correction trigger matches its retained migration and must be preserved |
| Production | 63 column-position-only changes | Layout differences; types/defaults/other captured column attributes match. Retain positions; verify dependent views/actions behavior rather than reordering columns |
| Production | Missing `people.notes` and `organizations.notes`; two missing note APIs | Hardened `party_identity_notes.sql` is the candidate forward change. Rehearse against restored production before production execution |
| Production | Missing Agreement Type creation API | `agreement_type_administration.sql` candidate, already tested live on test; production rehearsal/approval still pending |
| Production | Missing `issue19_reassign_organization_contact(text,uuid,text,uuid,uuid,text)` | Review retained contact migration against effective contact views; rehearse and verify ownership behavior |
| Production | Three changed contact views | Same relational expressions after schema qualification/deparser alias normalization; no view replacement justified by these differences |

Changed functions: `exclude_cash_donation_from_deposit(uuid,uuid,text,text)`, `issue19_create_member_agreement(text,uuid,uuid,uuid,text,text,jsonb,uuid)`, `issue19_set_person_role(text,uuid,text,boolean,text)`, `prevent_confirmed_cash_deposit_mutation()`. Changed views: `v_person_addresses`, `v_person_emails`, `v_person_phones`.

This is a preliminary dependency inventory, not an executable production manifest. No evidence supports replaying the entire retained migration directory. Final migration checksums/order, effective-definition dispositions, configuration target review and historical-data invariants must be recorded before Phase 1 closes; restored-copy acceptance remains a later release gate.

## Immediate sequence

Follow [NOTES_VALIDATION_COMMANDS.md](NOTES_VALIDATION_COMMANDS.md). Capture effective definitions privately before applying the notes increment; migrate and verify only test; then validate existing Individual/`Company Profile` and `Intake` flows. Complete the remaining Appsmith and integration observations in the private operator evidence form. Share that evidence privately for review, keeping it out of Git. The final release still requires the production-bound Appsmith export committed to SignatureGate and changelog reconciliation since v1.1.0.


## Notes follow-up and actual Appsmith datasource proof

The second private archive contains the notes follow-up from SignatureGate `f45bd0ab6ef6d4b74083d2946b8563eb05b64b6c`. Its original 19 manifest entries still verify; the new follow-up logs were not covered by that original manifest. Both notes migration runs reached COMMIT, the repeat processed zero historical sources, and behavioral checks reported success followed by ROLLBACK. All follow-up JSON captures parse and catalog/error logs are empty. No operational note or identity values are copied here.

The operator ran the diagnostic SQL through the actual Appsmith datasource and returned `signaturegate_test` and PostgreSQL `16.13 (Debian 16.13-1.pgdg13+1)`. This closes the development datasource-target observation; it does not prove the production target or publication revision. Profile/Intake notes UI acceptance remains pending.

The post-notes test catalog has 44 relations, 582 columns, 145 functions, eight views, 183 constraints, 51 triggers and 145 indexes. The provenance relation/helper are present. Test's remaining missing legacy revival API requires the final reason-aware implementation rather than installing the older reasonless definition.

Effective SQL dispositions:

- `exclude_cash_donation_from_deposit` and `issue19_set_person_role` bodies match intended source in test and production; no replacement is justified by their earlier hash differences.
- Test's `issue19_create_member_agreement` has reviewer-on-behalf behavior. Production retains the earlier practitioner-only body; the retained reviewer-on-behalf forward file is a candidate production step.
- Both deployed `prevent_confirmed_cash_deposit_mutation` bodies match `cash_deposit_confirmation_correction.sql`. A later bootstrap section was incorrectly replacing that correction with unconditional immutability. The canonical schema now preserves the accepted correction guard; the fresh-bootstrap correction regression passes without applying a follow-up migration. The deployed trigger does not need this repair.
- All three contact views retain the same relational expression. Schema qualification and unused second-UNION output aliases account for their captured textual differences; no view rebuild is proposed on that evidence.
- Production still needs the notes columns/provenance/APIs, Agreement Type API and organization-contact reassignment API, subject to dependency review and restored-copy rehearsal. Production owner/grant configuration must be preserved.

Remaining Phase 1 gates: production datasource/publication proof, published integration destinations/modes/mappings, RootedOps released/deployed dependency, final candidate checksums/order/preconditions and protected restored-production rehearsal. The version-source fingerprint difference remains limited to one tracked application file; it is not proof of deployed-revision parity. Raw definitions, configuration and application evidence remain private.
