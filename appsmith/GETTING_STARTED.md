# Set up SignatureGate with Appsmith and PostgreSQL

A fresh deployment needs a new PostgreSQL database, the canonical schema, explicit deployment seeds, authenticated Appsmith users, and reviewed integration connections. Existing databases use a reviewed forward upgrade. Never run the schema bootstrap over operational data or replay a retired historical migration chain.

The packaged `appsmith/Rooted Psyche Membership Ops.json` is the last shipped application. During v1.2.0 preparation, the newer split source is in SignatureGate-Appsmith `chatgpt_development`, bound to test. The production-bound source/export will be accepted and packaged at the release gate. See [the release plan](../releases/v1.2.0/RELEASE_PLAN.md).

## Database prerequisites

Follow [db/README.md](../db/README.md) to bootstrap a **new empty database** from `db/schema.sql`, initialize `db/seeds/organization_terminology.sql`, select the initial directory manager, and configure agreement types/templates. The current terminology seed displays the stable `practitioner` concept as **Spiritual Practitioner**; Phase 3 will update Member → Participant defaults together with the accepted UI changes.

Canonical definitions include:

- `people`, `organizations`, `members`, `contributors` and their profile projections;
- shared party contacts and retained participant/contributor contact sources;
- explicit `person_app_accounts` and `person_roles`;
- agreement/signing, practitioner assignment and release APIs;
- donation review, deposit, audit and integration queue objects.

For an existing database, establish effective definitions before selecting files from `db/migrations/`. Use the private operator review and [current migration candidates](../releases/v1.2.0/CURRENT_MIGRATION_CANDIDATES.md). Catalog differences do not establish that every retained migration should run.

Focused rollback-only checks are in `db/tests/`, including canonical people, party contacts, directory reads, person roles, contact maintenance/reassignment, membership closure, practitioner assignments, agreement/release attribution, terminology and identity notes. Run them on test/disposable databases. The release acceptance ledger records remaining live checks; an object-existence check alone is not functional acceptance.

## Import or synchronize the application

For a shipped release, import the full packaged JSON into an authenticated Appsmith application. Page-only imports can fail or omit dependencies. Review datasource descriptors, jsPDF library and embedded widgets after import.

For v1.2.0 development, use the existing test application and `SignatureGate-Appsmith/chatgpt_development`. Preserve unsynchronized editor changes before pulling. Apply each required backend increment to test before pulling the matching frontend. Do not bind this development source to production or regenerate the shipped JSON from it.

The final export action must be pinned to the accepted production-bound Appsmith master SHA, validate exact source preservation, and commit the resulting JSON to SignatureGate before release tags are created.

## Verify actual datasources

Configure PostgreSQL and integration credentials through Appsmith. Git datasource names/descriptors do not prove the actual connection. Through the actual PostgreSQL datasource, run:

```sql
SELECT current_database() AS database_name,
       current_setting('server_version') AS postgres_version;
```

Development must return `signaturegate_test`; production must return `signaturegate`. Keep connection credentials and operational target details outside Git. Use internal Docker service routing where appropriate; confirm file upload/retrieval works through the deployed NocoDB route.

Appsmith Community v2.4.2 and n8n 2.16.1 are confirmed for the currently reviewed deployment. These are product versions, distinct from export schema metadata.

## Authentication and permissions

Require Appsmith login. Link the signed-in email to exactly one active canonical `person_app_accounts` owner; do not infer ownership from a shared contact value. The initial directory-manager bootstrap is an explicit operator procedure documented in `db/README.md`.

Canonical `person_roles` are stable contracts. Their configured labels do not grant access or rename stored roles:

- `directory_manager`: identity/account/role and terminology administration;
- `document_reviewer`: document and membership operations;
- `donations_reviewer`: contribution review and organization-wide financial operations;
- `practitioner`: assigned participant operations within permitted scope.

Canonical pages can authorize people without membership. Reports and Agreement Templates now use canonical actors without requiring Participant capacity. Retained compatibility IDs do not establish actor authority. Unified Intake duplicate lookup also uses canonical roles without requiring reviewer Participant capacity. Do not grant a broad reviewer role just to bypass a legacy access check.

Wait for `appsmith.user.email` before querying an actor. Pass the authenticated email directly or as `this.params.email`, rather than a form-controlled value. Distinguish a denied actor from a query failure. Verify positive and negative roles on each active page after Git pull/reload.

## `Directory`, profiles and operations

`Directory` selects a canonical individual or company and passes its identity ID to `Individual Profile` or `Company Profile`. Profiles operate on that selected identity. Grouped navigation is operator-accepted; [SCREENS.md](SCREENS.md) describes the current development page set.

Profiles administer identity, contacts, capacity, roles and reasoned notes according to permissions. Contributor capacity is independent of membership; a company does not gain Participant capacity. Contact values alone do not merge identities. Shared contacts, archival, primary promotion and cross-capacity reassignment use reviewed APIs.

`Member Functions` and `Contributor Functions` remain operational entry points for their corresponding capacities. Practitioner Functions owns practitioner-specific administration. The duplicate legacy Intake page is retired from development after unified controller/SQL parity checks. Apply the updated atomic API before pulling the frontend; follow [UNIFIED_INTAKE_VALIDATION.md](../releases/v1.2.0/UNIFIED_INTAKE_VALIDATION.md).

`Intake` requires the accepted contact-method validation and records notes at the individual/company identity level. Follow [the notes validation sequence](../releases/v1.2.0/NOTES_VALIDATION_COMMANDS.md) to verify historical migration, edits, clears and reruns on test.

## Agreements and releases

`Agreement Templates` manages template configuration and, in the development candidate, document-reviewer Agreement Type creation. Existing type/template selection must remain usable. Apply and verify `db/migrations/agreement_type_administration.sql` on test before using the new form.

Review the deployment's actual Documenso envelope/recipient mappings privately. A recipient slot ID is a template mapping, not a person ID. Stable compatibility fields include `documenso_member_recipient_id` and `documenso_facilitator_recipient_id`; label changes do not rewrite them or previously executed agreements. See [the Documenso guide](../n8n/DOCUMENSO_INTEGRATION.md).

New agreement/release paths attribute the assigned practitioner by canonical person ID without requiring that practitioner to have membership. Retained participant IDs and legacy projections preserve historical references. `Sacrament Release` requires an eligible active membership and signed agreement for the release scope, including valid older template versions. It records the transfer through the guarded release API.

MushroomProcess inventory actions use the deployed PGSQL n8n routes. Verify scope, storage grants, inventory compatibility and non-writing test behavior before production acceptance. Do not copy operational inventory or product values into release documentation.

## Donations and cash deposits

Contributions belong to an individual or organization contributor independently of membership. Givebutter matching uses provider identity or unique contact evidence; ambiguity remains in review rather than merging people by name. Anonymous cash has no synthetic participant identity.

Donation reviewers control review and organization-wide cash deposits. The remaining assigned-practitioner entry/history work must provide scoped access without granting global financial visibility. Release eligibility does not depend on donation amounts.

Verify deposit composition, exclusions/revival reasons, confirmation, printing, immutable confirmed state and ERP synchronization in the later acceptance phases. Development ERP calls must remain non-writing/test-bound. See [Phase 2 progress](../releases/v1.2.0/PHASE_2_PROGRESS.md).

## Audit and private validation evidence

Sensitive state changes require an atomic audit entry; audit failure must roll the associated write back. Do not bypass audit failure to make a workflow appear successful. No-op updates must follow the API's documented audit behavior.

Keep raw database captures, notes, names, contacts, financial values, product information, account identifiers, screenshots and workflow/configuration details outside Git. Public release records contain only sanitized structural findings, software versions, technical object identifiers, source revisions and pass/fail status.

## Contribution naming

Use functional/descriptive filenames, directories and make targets. Do not put issue names/numbers in those names. Issues may be cited in code, comments, commit messages and documentation prose. Stable existing SQL function/API identifiers are compatibility contracts and need not be renamed for this rule.

This guide documents technical contracts and synthetic checks. Actual individual names, other company names from operational records, contact values, financial amounts, product details, account numbers and secrets remain private.
