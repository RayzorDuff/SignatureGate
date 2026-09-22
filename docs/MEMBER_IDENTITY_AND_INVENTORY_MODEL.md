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

`migrations_issue_19_existing_person_membership.sql` adds a member-specific
record to an existing person after a directory manager who is also a document
reviewer confirms first and last names. Missing structured name fields can be
completed on the central person record; existing structured names cannot be
changed through enrollment. If that person already has an active individual
contributor, a same-person link records both capacities. Prior donations keep
their existing `member_id` and remain contributor-owned. No member-purpose
email, agreement, practitioner appointment, or release authorization is
created as part of enrollment. Archived memberships need separate review.

`migrations_issue_19_end_membership.sql` allows a directory manager who is
also a document reviewer to end an active membership after an active
individual contributor exists. The member row remains with status `inactive`,
end timestamp, reviewer, reason, and its agreement/release history; active
contributor/member links become ended. Existing donations retain their
original member IDs, while later donations can be associated with the active
contributor alone. Pending agreements, roles, legacy reviewer flags, and
facilitator assignments must be resolved first. Re-enrollment is deliberately
blocked for a person with an ended membership until a reviewed reactivation
workflow is designed; a second member ID must not be created.
The release table rejects new releases for inactive members, including when
an old browser session retains a previously selected member ID.

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

# Facilitator Architecture

## Multi-facilitator model

Members may now be assigned to multiple facilitators simultaneously.

Assignments are stored in:

```text
member_facilitators
```

This replaces the earlier single-facilitator architecture.

---

## Facilitator permissions

Facilitators may:

- manage member profiles
- upload agreements
- send digital agreements
- issue releases
- manage member donations
- access storage locations

depending on assigned roles.

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

Releases may now be issued:

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
