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
