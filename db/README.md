1) Initialize the signaturegate-postgres database with db/schema.sql

From the server where your docker compose runs (in the SignatureGate repo folder where your .env lives):

Confirm containers are up:

```bash
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

2) Load the schema + migrations into Postgres (recommended: execute inside the container):

```bash
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/schema.sql

# Core role + review workflow fields/indexes
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_facilitator_review.sql

# Facilitator auth support (created_by_facilitator_id, etc.)
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_facilitator_authentication.sql

# Sacrament release enhancements (facilitator linkage, etc.)
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_sacrament_release.sql

# Optional: Documenso integration (only if using Documenso + n8n workflow)
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_documenso_integration.sql
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_documenso_integration_1.sql
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_documenso_cancel_agreement.sql
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_documenso_template_discovery.sql

# Audit Log - See below for details
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_audit_log.sql

# Document Reviewer actions
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_agreement_review_actions.sql

# Donations and Donations Reviewer actions
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_donations_review.sql
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_is_donation_reviewer.sql

# Allow voiding releases
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_release_void.sql

# Rename sacrament_releases table to releases for use by other areas of the organization
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_rename_sacrament_releases_to_releases.sql

# Store valid agreement types in DB
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_agreement_types.sql

# Store facilitator assignments in a separate table
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_member_facilitators.sql

# Allow facilitators to pull releases from multiple storage locations
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_facilitator_storage_location_access.sql

# Allow members to have multiple email, phone or address
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_member_contact_methods.sql

# Support setting primary email for members
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_member_email_primary_selection.sql

# Add support for Listmonk mailing list subscription management.
# n8n can add a SignatureGate opt-in to both LISTMONK_NEWSLETTER_LIST_ID and
# LISTMONK_MEMBER_COMMUNICATIONS_LIST_ID. The DB queue keeps one primary list ID
# for compatibility; n8n expands it to both Listmonk lists at sync time.
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_listmonk_mailing_list.sql

# Optional one-time backfill: enqueue existing active member emails for Listmonk sync.
# The n8n workflow will subscribe each queued email to both configured lists.
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_listmonk_mailing_list_upsert_existing.sql

# Reporting indexes
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_reporting_indexes.sql

# db: harden member identity contact handling
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_v1_0_4_member_identity_hardening.sql

# Add the stronger physical-address identity key and centralized address upsert.
# Apply this after the v1.0.4 identity migration and before importing the
# matching Appsmith workflow or activating the matching Givebutter n8n workflow.
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_v1_1_0_member_address_identity_hardening.sql

# Add explicit member/anonymous/unresolved donor identity and the controlled
# anonymous-cash creation and donation-review functions for Issue #17.
# Apply before importing the matching Appsmith and Givebutter workflow exports.
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_issue_17_anonymous_cash_donations.sql

# Decouple identified contributors from membership for Issue #19. This adds
# individual/organization contributors, auditable contributor-member links,
# contributor contact/provider identities, donation backfill, and compatibility
# functions for a staged Appsmith/n8n rollout.
# Apply after the Issue #17 migration and before importing the matching
# Appsmith export or activating the matching Givebutter workflow.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_contributor_identity.sql

# Install contributor-first matching and the idempotent provider-ingestion API.
# Apply after the Issue #19 identity migration and before activating the
# matching Givebutter n8n workflow.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_contributor_ingestion.sql

# Issue #19: shared person and organization identities under the existing
# member/contributor APIs. Apply after BOTH preceding Issue #19 migrations.
# This is a one-time migration: back up the DB and do not rerun it.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_shared_identity.sql

# Optional smoke test for the transitional shared-identity schema. Run BEFORE
# the canonical-people migration below; it exercises the old name projections.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_shared_identity.sql

# Review previously differing names; contact values are shown through the
# v_person_emails / v_person_phones / v_person_addresses read views.
sudo docker exec signaturegate-postgres psql -U signaturegate -d signaturegate -c "SELECT person_id, member_id, contributor_id, member_name, contributor_name FROM public.person_identity_review WHERE resolved_at IS NULL ORDER BY created_at;"

# Install the serialized Member Intake creation helper and active-email guard.
# Apply this before importing the matching Appsmith export.
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_v1_0_4_member_intake_duplicate_scope.sql

# Block Member Intake when an exact normalized phone belongs to an active member.
# Apply this after migrations_v1_0_4_member_intake_duplicate_scope.sql and before
# importing the matching Appsmith export.
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_member_intake_exact_phone_block.sql

# Issue #19: move person names and birth dates, and organization names, out of
# role tables. Run ONCE after backing up the database, during a brief write
# pause; import the matching Appsmith export next. Existing role IDs remain.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_canonical_people.sql

# Optional end-to-end smoke test. Synthetic rows are rolled back even when
# checks pass. Run after the canonical migration, before importing Appsmith.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_canonical_people.sql

# Issue #19 contact foundation: backfill person/organization-owned email, phone,
# and address records, and synchronize the existing member/contributor contact
# writes. Apply ONCE after canonical_people.sql, before the Directory UI phase.
# Keep the legacy contact tables: agreement and mailing-list rows still point
# at member_email_id and the current Appsmith/n8n workflows write those tables.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_party_contacts.sql

# Rollback-only integration check for shared, separate, archived, edited, and
# reassigned contact owners; run after the contact foundation migration.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_party_contacts.sql

# Issue #19 read-only Directory query helpers. Apply after party contacts,
# before importing the matching Appsmith export. Current account/reviewer
# flags still determine which people, organizations and contacts are visible.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_directory_read.sql

# Rollback-only access check for the Directory helpers.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_directory_read.sql

# Issue #19 person roles and account ownership; apply after the Directory
# migration and before importing its profile-editing Appsmith export.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_person_roles.sql

# Rollback-only permission, nonmember-account, assignment and audit checks.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_person_roles.sql

# Review the exact account owner first. Bootstrap one directory manager via
# the database operator (there is intentionally no automatic promotion).
sudo docker exec signaturegate-postgres psql -U signaturegate -d signaturegate -c \
  "SELECT p.person_id, p.display_name, a.email FROM public.person_app_accounts a JOIN public.people p USING (person_id) ORDER BY a.email;"
# Substitute the intended person's actual Appsmith sign-in email below:
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -v admin_email='ACTUAL_SIGN_IN_EMAIL' -U signaturegate -d signaturegate < db/bootstrap_issue_19_directory_manager.sql

# Issue #19 contributor intake from Directory and enrollment of an existing
# person as a contributor. Apply after person_roles.sql, before importing the
# associated Appsmith export. No membership is created by these functions.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_contributor_directory_intake.sql

# Rollback-only integration checks: permissions, duplicate contacts, person
# and company creation, contact synchronization, enrollment, and auditing.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_contributor_directory_intake.sql

# Issue #19 contributor-purpose contact maintenance on Individual and Company
# Profile. Apply after directory intake, before importing the matching export.
# Member-purpose contacts retain their existing edit path.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_contributor_contacts.sql

# Rollback-only checks for permissions, contact ownership, primary selection,
# legacy-to-party synchronization, archiving, and audit entries.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_contributor_contacts.sql

# If contributor_contacts.sql committed but the initial verification failed
# at the cross-party contact check, apply this forward function replacement;
# do not rerun the CREATE FUNCTION migration. Then rerun verification.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_contributor_contact_guard_fix.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_contributor_contacts.sql

# Issue #19: create membership for a selected existing person without a second
# person record, an automatic agreement, or a rewrite of prior donations.
# Apply AFTER the contact guard repair and its passing verification.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_existing_person_membership.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_existing_person_membership.sql

# End an active membership while keeping the person and any independently
# existing contributor. Apply AFTER existing-person membership; run the
# rollback-only verification before importing the updated Appsmith JSON.
# Contributor capacity is not required and is never created by this action.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_end_membership.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_end_membership.sql

# Contributor-purpose mailing addresses on Individual and Company Profile.
# Apply AFTER the membership-closure migration, then run the rollback-only test.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_contributor_addresses.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_contributor_addresses.sql

# Allow reviewed assignment of one person's member/contributor email, phone,
# or address to the other capacity without replacing its original source.
# Apply AFTER contributor addresses, then run the rollback-only checks.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_contact_role_assignment.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_contact_role_assignment.sql

# Keep active contact sources on former memberships visible to authorized
# reviewers, list member-only contacts before contributor enrollment, and allow
# reuse into an active contributor. Apply AFTER contact-role assignment.
# If the first version failed on contact_detail before COMMIT, its transaction
# rolled back; rerun the corrected migration below, then its verification.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_contact_role_visibility.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_contact_role_visibility.sql

# Show contributor-attributed donation history and provider identities on
# Individual Profile and Company Profile. Apply AFTER contact-role visibility.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_contributor_profile_history.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_contributor_profile_history.sql

# Add reviewed contributor archive/reactivation for people and organizations.
# Apply AFTER contributor profile history, then run the rollback-only checks.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_contributor_status.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_contributor_status.sql

# Add audited canonical name/date-of-birth maintenance for people and names for
# organizations. Apply AFTER contributor status, then run rollback-only checks.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_party_identity_editing.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_party_identity_editing.sql

# Define a release as a tangible sacrament transfer, reject new membership or
# event values in releases.release_type, and retain legacy exceptions for
# explicit review. Apply AFTER canonical identity editing.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_sacrament_release_scope.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_sacrament_release_scope.sql

# Expose agreement and practitioner-assignment history on Individual Profile
# under the existing document-reviewer/assigned-practitioner access rule.
# Apply AFTER the sacrament-release scope migration, then import Appsmith.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_member_operations_read.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_member_operations_read.sql

# Remove the accidental contributor prerequisite from membership closure.
# A member-only person may end membership without creating a contributor;
# an existing contributor and its donations remain unchanged.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_membership_contributor_independence.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_membership_contributor_independence.sql

# Add membership-purpose email/phone maintenance to Individual Profile.
# Apply AFTER the membership/contributor independence repair. The functions
# write only member contact rows; contributor contacts remain independent.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_member_contact_profiles.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_member_contact_profiles.sql

# Make sacrament-release eligibility independent of template version/active
# status. Apply AFTER member contact profiles, then import Appsmith. Template
# required_for scope and signed agreement status remain mandatory.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_sacrament_agreement_gate.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_sacrament_agreement_gate.sql

# Add membership-purpose mailing addresses and merge both address capacities
# into the role-aware Individual Profile contact editor. Apply AFTER member
# contact profiles; contributor and membership address rows remain separate.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_member_address_profiles.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_member_address_profiles.sql

# Replace member-ID-only facilitator assignment with canonical person-based
# practitioner assignment. Existing rows are backfilled and legacy writes stay
# synchronized; a practitioner does not need membership. Apply AFTER member
# address profiles, then import the matching Appsmith export.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_19_person_practitioner_assignments.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_19_person_practitioner_assignments.sql

# Add stable terminology concepts and Rooted Psyche's deployment labels.
# This does not rename role keys or grant appointments. The operational
# practitioner and a future regulated facilitator remain distinct concepts.
# Apply AFTER person-based practitioner assignments, then import Appsmith.
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/migrations_issue_20_organization_terminology.sql
sudo docker exec -i signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate < db/verify_issue_20_organization_terminology.sql

# This should return no rows. If it returns historical records, review what
# each record represents before correcting it and validating the constraint.
sudo docker exec signaturegate-postgres psql -U signaturegate -d signaturegate -c "SELECT release_id, released_at, member_id, release_type, item_name, notes FROM public.releases WHERE release_type IS DISTINCT FROM 'sacrament_release' ORDER BY released_at, release_id;"

# After resolving every historical exception:
sudo docker exec signaturegate-postgres psql -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate -c "ALTER TABLE public.releases VALIDATE CONSTRAINT releases_sacrament_release_type_check;"

# documenso: handle expirations and audit actors
sudo docker exec -i signaturegate-postgres psql -U signaturegate -d signaturegate < db/migrations_v1_0_4_documenso_expiration.sql
```

3) Verify tables exist:

```bash
sudo docker exec -it signaturegate-postgres psql -U signaturegate -d signaturegate -c "\dt"
```

4) Seed at least one agreement template (As long as base schema doesn't already include one)

```bash
sudo docker exec -it signaturegate-postgres psql -U signaturegate -d signaturegate -c " \
INSERT INTO agreement_templates (name, version, required_for, doc_url, active) \
VALUES ('Member Acknowledgment & Liability Release', '2025-12-01', ARRAY['membership','sacrament_release'], \
'DOCUMENSO_TEMPLATE_OR_PDF_URL', true) ON CONFLICT DO NOTHING;"
```

5) Create the NocoDB base connected to signaturegate-postgres

In NocoDB UI:

Create Base → name it SignatureGate.

Open that base → Connect External Data 
NocoDB

Choose PostgreSQL and enter connection info:

If NocoDB is running in the same docker compose network, use:

```bash
Host: signaturegate-postgres
Port: 5432
DB: ${SIG_DB_NAME}
User: ${SIG_DB_USER}
Password: ${SIG_DB_PASSWORD}
```

6) Create a Postgres datasource in Appsmith

Appsmith UI → Datasources → New Datasource → PostgreSQL

If Appsmith is in docker with Postgres:

```bash
Host: signaturegate-postgres
Port: 5432
DB: ${SIG_DB_NAME}
User: ${SIG_DB_USER}
Password: ${SIG_DB_PASSWORD}
```

Test & Save.


## Migration order
After schema.sql run migrations in the order specified above.

## audit_log table

The `audit_log` table is used for permanent, append-only recording of significant system events.

Columns:
- `actor` – email or system identifier (`n8n`, `documenso`)
- `action` – machine-readable event name (e.g. `member_agreement.signed`)
- `entity_type` – logical entity affected
- `entity_id` – identifier of the affected entity
- `details` – JSON payload with contextual metadata
- `created_at` – server timestamp

This table is not intended for debugging or analytics and should not be truncated or modified.
