# Member Identity and Inventory Architecture

## Overview

SignatureGate and MushroomProcess support a hybrid operational model involving:

- Rooted Psyche
- Dank Mushrooms
- future regulated entities
- facilitator-managed inventory release workflows

The architecture separates:

1. Identity
2. Inventory ownership
3. Physical custody
4. Facilitator operational access

This separation allows future regulatory adaptation without redesigning the system.

---

# Member Identity Model

## Members are people, not email addresses

A member may possess:

- multiple email addresses
- multiple phone numbers
- multiple physical addresses

The system therefore no longer treats:

- `members.email`
- `members.phone`

as authoritative identity fields.

Instead, authoritative identity records are stored in:

- `member_emails`
- `member_phones`
- `member_addresses`

The original columns remain only for:

- compatibility
- reporting
- legacy integrations
- convenience display

---

# Contact Method Lifecycle

## Email addresses

Email addresses may be:

- active
- archived
- verified

Emails are used for:

- Documenso agreement delivery
- facilitator communication
- Givebutter identity matching

### Verification

An email becomes verified when:

1. A document reviewer manually verifies it
2. A Documenso agreement sent to that address is signed successfully

Verification metadata includes:

- `verified_at`
- `verified_by`
- `verification_source`
- `verification_notes`

---

## Phone numbers

Phone numbers are normalized using:

```sql
normalize_us_phone()
```

Examples:

- `(303) 555-1212`
- `3035551212`
- `+13035551212`

all normalize to:

```text
3035551212
```

Duplicate active normalized phone numbers are prevented through a partial unique index.

---

## Addresses

Addresses are informational and may originate from:

- intake
- Givebutter
- manual reviewer entry

Addresses are not currently treated as authoritative identity proof.

Active addresses are de-duplicated within a member by a physical-address
identity key. The key uses normalized street, unit, postal code, and country.
City, state, and address type are intentionally excluded because provider data
may abbreviate or truncate them. Unit information remains part of the key, so
different apartments or suites are not merged.

All Appsmith and Givebutter address writes use
`public.upsert_member_address(...)`. Manual address text is preserved when a
provider submits an equivalent address. Provider-managed rows may be enriched
when a later provider payload contains a more complete component, such as
`Fort Collins` after an earlier `Fort` value.

---

# Contact Reassignment and Archival

Incorrectly assigned contact methods should generally be:

- archived
- or reassigned

rather than deleted.

This preserves operational history and audit integrity.

Tables therefore include:

- `status`
- `archived_at`
- `archived_by`
- `archive_reason`

---

# Donation Identity Resolution

Every donation has an explicit donor identity state:

- `identified`: linked to an active individual or organization contributor;
  `contributor_id` is required
- `anonymous`: deliberately anonymous cash; `contributor_id` and `member_id`
  remain null
- `unresolved`: provider import awaiting identity review; `contributor_id` and
  `member_id` remain null

Anonymous cash does not create an “Anonymous” member and does not participate
in membership or sacrament-release eligibility. The identity state is separate
from donation review status and from the future deposit-custody lifecycle.

Changing an unresolved provider donation to `identified` occurs through the
audited reviewer workflow. Anonymous cash is not silently converted to an
identified contribution.

## Contributors and members

Issue #19 shared identity migration adds `people` and `organizations`. Every
member is linked to exactly one person through `members.person_id`, and every
individual contributor is linked through `contributors.person_id`. Organization
contributors use `contributors.organization_id`. An individual can be a member,
donor, ceremony participant, practitioner, or minister without another person
identity. Anonymous gifts have neither a person nor an organization identity.

`members` remains the membership-specific record (agreements and releases retain
their existing member IDs). `contributors` remains the donor-party record for
Givebutter and Appsmith. After `migrations_issue_19_canonical_people.sql`,
individual names and birth dates are stored only on `people`, and organization
names only on `organizations`. `member_profiles` and `contributor_profiles` are
read views for existing UI fields, not additional copies. New records write
their identity first, followed by the domain record with its person or
organization ID. When an existing contributor becomes a member, the existing
person ID is retained; when a member first gives, the member's person ID is
retained.
The shared-identity migration stores conflicting pre-existing names in `person_identity_review`
before choosing the member name for a linked person. Contact methods continue
in legacy member/contributor tables; the `v_person_emails`, `v_person_phones`,
and `v_person_addresses` views provide a deduplicated read surface for the
future UI, but contact edits still need a unified write API. Contact values
alone never merge two people.

The next Issue #19 migration, `migrations_issue_19_party_contacts.sql`,
backfills `party_contacts` and `party_contact_sources` and keeps them current
when the existing member/contributor contact workflows write, archive, or
reassign a row. Each contact belongs to exactly one person or organization;
identical values owned by different parties remain separate. Identical
member/contributor contacts for the *same* person share a canonical contact
with distinct source preferences. The new `v_party_contacts` view is the
directory/profile read surface. Member/contributor contact tables remain
temporarily writable with copied contact values because agreement and
Listmonk foreign keys depend on member email IDs and current Appsmith/n8n
workflows still use those IDs. Moving all consumers and editing directly
through a controlled party-contact API is a later phase; the existing
`v_person_emails`/`v_person_phones`/`v_person_addresses` views still reflect
the legacy source rows in this phase.

`migrations_issue_19_directory_read.sql` exposes an Appsmith-scoped Directory
and contact lookup. Directory displays one row per accessible person or
organization, with contacts restricted to the member or contributor source
that the current reviewer/facilitator may see. The new Individual Profile and
Company Profile are initially read-only. The existing Members - Profile keeps
the agreement, release, and member-contact actions. The subsequent person-role
migration makes Individual Profile roles and account ownership editable by an
explicit directory manager. These query helpers apply the application's email-based
scope; they are not a replacement for database-authenticated row policies.

`migrations_issue_19_person_roles.sql` seeds person roles from the legacy
facilitator and reviewer flags and links existing reviewer/facilitator sign-in
emails to people. A database operator selects the first directory manager;
there is no automatic admin promotion. On Individual Profile, that manager
may grant/revoke practitioner, document-reviewer, and donations-reviewer
roles, or link an Appsmith sign-in email to an individual. Account emails
are unique across people. Changes require a reason and are audited. Active
member flags are mirrored for current member-based workflows; new Directory
read access can also belong to a nonmember account. No older release or
donation write function is yet authorized solely by a nonmember role. The
Appsmith PostgreSQL connection is shared, and actor email comes from the
trusted application; these helpers do not provide DB-level user isolation.

`migrations_issue_19_contributor_directory_intake.sql` allows a donations
reviewer to create a new individual person or organization with an active
contributor record from the Directory, and allows a directory manager who is
also a donations reviewer to enable the contributor role for an existing
person. The database does not match names or merge identities automatically.
An email or phone already used by another active party blocks creation until
the reviewer investigates; shared contacts can be added through a later
explicit contact workflow. Both actions require a reason, write to audit_log,
and do not create a member or agreement.

`migrations_issue_19_contributor_contacts.sql` adds contributor-purpose email
and phone maintenance to Individual and Company Profile. The functions write
the contributor contact source rows, whose triggers project contact changes
into `party_contacts` for the owning person or organization. Donor reviewers
may add or archive these contacts with an audit reason. Newly added contacts
become primary; archiving a primary promotes the oldest remaining active
contact of its kind. Existing member-purpose contacts retain their separate
agreement and mailing-list path. An active contact owned by another party
requires explicit review before it can be shared.

`migrations_issue_19_contributor_addresses.sql` adds reviewed contributor
mailing-address add/archive actions to Individual and Company Profile.
Contributor address rows continue to synchronize with `party_contacts`, owned
by the existing person or organization. Street, unit, postal code and country
form the physical identity; different apartments stay distinct and city/state
abbreviations do not duplicate an address for a contributor. Two separate
people or organizations may legitimately use the same building. Membership
addresses remain on the member history and are not copied automatically.

`migrations_issue_19_contact_role_assignment.sql` lets a directory manager
who also has both reviewer permissions use an existing individual contact for
the person's other active capacity. The database inserts a new role-specific
source row so membership agreements and donor integrations can continue using
their own IDs, while both source rows map to the same `party_contacts` record.
The original role record is preserved, the assignment is audited, and
membership mailing-list subscription and verification are never inferred
from the contributor source. Address identity uses street, unit, postal code
and country. Organizations cannot be assigned membership contact sources.

`migrations_issue_19_contact_role_visibility.sql` lists member-only contacts
even before contributor enrollment and shows active contacts retained by an
ended membership as `former membership` for directory managers who are also
document reviewers. Assignment requires the *destination* capacity to be
active: an ended member's contact can be assigned to an active individual
contributor, while a contributor contact cannot be assigned to an ended
membership. The original source and canonical person contact are preserved.

`migrations_issue_19_contributor_profile_history.sql` adds read-only,
permission-scoped contribution history and external/provider identity
projections for both people and organizations. Appsmith displays these on
Individual Profile and Company Profile. Donation attribution continues to use
`contributor_id`; profile display does not recreate a member relationship or
change any donation, contact, or provider identity.

`migrations_issue_19_contributor_status.sql` lets a directory manager who is
also a donations reviewer archive or reactivate an individual or organization
contributor. The status change requires a reason and writes an audit record.
Archiving removes the contributor from active intake and identity matching;
the person or organization, contributor contacts, external identities,
donations, and contributor/member identity links are retained. An individual's
membership status is independent and is not changed. Archived contributors
remain visible only to authorized contributor managers so the profile history
can be reviewed and the contributor can be reactivated. Merged contributors
remain immutable through this lifecycle action.

`migrations_issue_19_party_identity_editing.sql` makes the canonical identity
fields maintainable from Individual Profile and Company Profile by a directory
manager. Person edits cover display name, structured first/last names, and an
optional birth date; organization edits cover the canonical organization name.
Every change requires a reason and records previous and current values in the
audit log. A version derived from the loaded canonical fields provides
optimistic concurrency, so a stale browser cannot overwrite a more recent
correction. Domain IDs and
records in `members`, `contributors`, donations, agreements, releases,
contacts, appointments, and permissions are not rewritten by an identity edit.

`migrations_issue_19_existing_person_membership.sql` adds a member-specific
record to an existing person after a directory manager who is also a document
reviewer confirms first and last names. Missing structured name fields can be
completed on the central person record; existing structured names cannot be
changed through enrollment. If that person already has an active individual
contributor, a same-person link records both capacities. Prior donations keep
their existing `member_id` and remain contributor-owned. No member-purpose
email, agreement, practitioner appointment, or release authorization is
created as part of enrollment. Archived memberships need separate review.

`migrations_issue_19_end_membership.sql`, as corrected by
`migrations_issue_19_membership_contributor_independence.sql`, allows a
directory manager who is also a document reviewer to end an active membership
without requiring contributor capacity. The member row remains with status
`inactive`, end timestamp, reviewer, reason, and its agreement/release history.
If an independent contributor and active member/contributor link exist, the
link becomes ended while the contributor remains active. No contributor is
created, archived, or otherwise changed merely because membership ends, and
existing donation attribution is not rewritten. Pending agreements, roles,
legacy reviewer flags, and facilitator assignments must be resolved first.
Re-enrollment is deliberately blocked for a person with an ended membership
until a reviewed reactivation workflow is designed; a second member ID must
not be created.
The release table rejects new releases for inactive members, including when
an old browser session retains a previously selected member ID.

`migrations_issue_19_member_operations_read.sql` begins the controlled move of
membership-specific operations to Individual Profile. It exposes agreement
history and practitioner-assignment history through person-based,
permission-scoped functions. Document reviewers retain full read access;
otherwise, a practitioner assignment is required. General directory-manager
or donations-reviewer access is insufficient. The later person-practitioner
migration makes that assignment person-based and moves assignment writes onto
Individual Profile. The profile still links to Members - Profile for agreement
writes and links active members to the separate Sacrament Release page. This
keeps the canonical person profile as the entry point without merging member
and contributor operations.

`migrations_issue_19_member_contact_profiles.sql` moves membership-purpose
email and phone maintenance onto Individual Profile. Document reviewers may add
or archive contacts only while the membership is active; assigned practitioners
may see the current member contacts but cannot change them. New member emails
start as not subscribed to Listmonk, archiving a primary contact promotes the
oldest remaining active record, and all changes require a reason and audit
entry. The functions write only `member_emails` and `member_phones`, whose
existing triggers project them into the shared person-contact read model. They
never create or modify `contributor_emails` or `contributor_phones`. Reusing a
contributor contact for membership remains a separate, reviewed cross-role
assignment so shared identity does not collapse the two capacities.

Individual Profile presents those email/phone operations through one role-aware
editor rather than parallel membership and contributor forms. Its selector is
limited to capacities the person has and the current reviewer may access. The
shared presentation does not merge storage or authorization: each action still
calls the member- or contributor-specific function, refreshes both projections,
and preserves separate audit semantics. Membership closure and contributor
archival remain separate lifecycle operations because their permissions,
blockers, and historical effects differ.

`migrations_issue_19_member_address_profiles.sql` extends the same editor with
mailing addresses. Document reviewers may add or archive addresses on an active
membership; assigned practitioners retain read-only visibility. Physical
identity uses normalized street, unit, postal code, and country, so city/state
spelling changes do not create duplicates and different units remain distinct.
Membership writes use `member_addresses`; contribution writes continue to use
`contributor_addresses`. A same-person address already present in the other
capacity must use the explicit reviewed assignment workflow. The shared UI and
canonical `party_contacts` projection do not merge the two capacity records.

`migrations_issue_19_person_practitioner_assignments.sql` makes the assignment
between a practitioner and a member's active membership person-based. The
practitioner is identified by `people.person_id` and must hold the
`practitioner` appointment in `person_roles`; the practitioner does not need a
member record or contributor record. `member_practitioner_assignments` is the
canonical current/history table. It grants only assigned-member visibility and
does not confer document-review, donation-review, membership, contributor, or
sacrament-release eligibility.

Existing `member_facilitators` rows are backfilled. While legacy agreement and
release pages still store facilitator member IDs, their writes are mirrored to
the canonical assignment table, and a canonical assignment creates a legacy
projection only when that practitioner has an active member ID. Individual
Profile owns the new audited assign/end workflow. Migrating agreement signer,
release actor, and storage-location ownership from member IDs to person IDs is
a later phase; until then, **Open agreement operations** remains available for
those legacy write paths. An active assignment must be ended before the
practitioner appointment can be removed from that person.

`migrations_issue_19_sacrament_agreement_gate.sql` centralizes release-agreement
eligibility. A signed agreement qualifies when its template scope includes
`sacrament_release`, regardless of template version or whether that version is
still active for new issuance. An inactive template therefore cannot be used
for a new agreement but does not invalidate an existing signature. Reviewed
template-free paper/manual agreements remain supported. Membership-only,
pending, rejected, expired, and canceled agreements do not pass the gate.

Membership is not a permission to operate Appsmith. Person-owned reviewer
roles and Appsmith account ownership are now separate from membership; older
operational pages and APIs still need to adopt those permissions. Ceremony
participation belongs to a particular ceremony, while future practitioner and
minister scheduling may need effective dates and status. No new
permission or release entitlement is conferred by a person or organization row.

Starting a contributor/member link does not retag earlier gifts with a member
ID. Historical `donations.member_id` values remain as previously recorded;
ending the link does not automatically end membership or rewrite gift history.

`contributors` is the donation-party domain. A contributor may be:

- an individual who is not a member
- an individual linked to a member
- an organization, which is never itself a member

Contributor email, phone, mailing-address, and provider identity records are
stored independently from member contact records. `contributor_member_links`
records the current and historical relationship between an individual
contributor and a member. Starting or ending that relationship does not delete
or merge either identity and does not rewrite donation history.

For compatibility during migration, `donations.member_id` is populated when an
identified contributor has an active member link. New donation logic treats
`donations.contributor_id` as authoritative. Membership agreements, facilitator
assignment, and sacrament-release eligibility continue to use `member_id` and
are not granted merely because a contributor exists.

## Givebutter workflow

Givebutter donations may arrive before:

- member intake
- agreement execution
- facilitator assignment

The system therefore uses staged identity resolution.

Matching attempts may use:

- provider contact identity
- contributor email
- a unique normalized contributor phone
- member contact identity as a compatibility fallback
- reviewer intervention

Provider ingestion is idempotent on `(provider, provider_reference)`. Matching
is performed by database functions rather than duplicated in the webhook:

1. exact provider contact identity
2. exactly one active contributor email
3. exactly one active member email (with lazy contributor creation)
4. exactly one active contributor phone
5. exactly one active member phone (with lazy contributor creation)

Ambiguous shared email or phone values do not auto-match and remain in review.

---

## Pending-review donations

If a donation cannot be confidently matched:

- donation is inserted with:
  - `status = 'pending_review'`
  - `contributor_id = NULL`
  - `member_id = NULL`

A donations reviewer may then:

- assign the donation to an existing contributor or member
- create an individual or organization contributor from the provider payload
- ignore/delete donation
- create new member from donation

---

## Donation-created members

When creating a member from a donation:

The system may automatically create:

- individual contributor record
- member record
- contributor-member link
- contributor contact and provider-identity records
- member_emails records
- member_phones records
- member_addresses records

All actions are audit logged.

---

# Practitioner assignment architecture

## Multiple-practitioner model

An active membership may be assigned to multiple practitioners
simultaneously. Practitioner appointment belongs to a person and is independent
of that person's membership and contributor capacities.

Assignments are stored in:

```text
member_practitioner_assignments
```

`member_facilitators` remains a transitional compatibility projection for
legacy operations that still require a practitioner member ID.

The internal `practitioner` key is intentionally independent of its display
label. Rooted Psyche currently labels it **Spiritual Practitioner** through
`organization_terminology`. A future DORA `facilitator` is a separate reserved
concept, not a synonym or automatic replacement. Updating terminology changes
presentation only and does not alter appointments, assignments, access, or
historical records.

---

## Practitioner access

An assigned practitioner may view the assigned member's profile and membership
operation history. Separate permission roles continue to control review and
administrative writes. Current legacy pages may additionally require an active
member-based compatibility row to:

- upload agreements
- send digital agreements
- record sacrament releases
- access storage locations

Contribution review remains controlled by contributor identity and donation
permissions, not by the practitioner-to-member assignment.

---

# Storage Location Access Model

Storage locations are no longer implicitly tied to facilitator names.

Access is controlled through:

```text
facilitator_storage_location_access
```

Multiple facilitators may share access to the same location.

This supports:

- shift operations
- shared custody
- future regulated inventory models

---

# Inventory Ownership vs Custody

Current Rooted Psyche operations involve:

- Dank Mushrooms producing inventory
- Rooted Psyche facilitating releases
- facilitators issuing releases from approved locations

Future regulated operations may separate:

- inventory owner
- physical custodian
- facilitator
- regulated operator

The current architecture intentionally separates:

- ownership
- custody
- access

to support future Colorado Natural Medicine compliance workflows.

---

# Release Authorization Model

A release is a tangible transfer of sacrament from organizational inventory or
storage into a recipient's custody. Membership activation, sweat-lodge
participation, and retreat participation are not releases. Those concepts use
membership and event lifecycles even when an agreement authorizes them.

The `release_type` column remains as a compatibility discriminator, but new
rows are constrained to `sacrament_release`. Agreement templates may still be
tagged with `membership`, `sweat_lodge`, or `retreat`; those values describe
what the agreement authorizes and do not create release transactions.

Sacrament releases may be recorded:

- against signed agreements
- or by document-reviewer override

Overrides require:

- reviewer authority
- mandatory notes

All override actions are audit logged.

---

# Audit Logging

SignatureGate uses append-only audit logging for:

- agreement lifecycle actions
- donation assignments
- facilitator assignments
- release issuance
- release voiding
- contact reassignment
- verification actions

Audit logs are intended for:

- compliance
- operational traceability
- historical reconstruction

and should not be truncated or edited.
