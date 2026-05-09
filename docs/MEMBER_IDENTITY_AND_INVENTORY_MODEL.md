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

## Givebutter workflow

Givebutter donations may arrive before:

- member intake
- agreement execution
- facilitator assignment

The system therefore uses staged identity resolution.

Matching attempts may use:

- verified email
- normalized phone
- legacy member fields
- reviewer intervention

---

## Pending-review donations

If a donation cannot be confidently matched:

- donation is inserted with:
  - `status = 'pending_review'`
  - `member_id = NULL`

A donations reviewer may then:

- assign donation to existing member
- ignore/delete donation
- create new member from donation

---

## Donation-created members

When creating a member from a donation:

The system may automatically create:

- member record
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
