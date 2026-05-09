# SignatureGate

SignatureGate is an open-source, self-hosted membership, agreement, sacrament-release **and donation tracking** system for **Rooted Psyche**.

It is designed to stay **separate but interoperable** with the MushroomProcess inventory/workflow system, while preserving legal, spiritual, and operational boundaries.

## v1.0.0 Scope

SignatureGate v1.0.0 provides stable support for:

- Member intake and profile management
- Agreement templates and multi-template agreement types
- Digital and manual agreement workflows
- Sacrament release tracking
- Donations (manual and Givebutter)
- Centralized audit logging

Event-day functionality is planned but not fully implemented in this release.

## What this solves

- Track **members** and contact information
- Track **agreements** (paper, Documenso, etc.) and enforce signing before sacrament release
- Track **sacrament releases** with traceability to MushroomProcess `product_id`
- Track **events** (ceremonies, retreats)
- Track **voluntary donations** (cash and Givebutter) without treating them as payment for sacrament
- Maintain a **centralized, append-only audit log** of all significant actions

> Donations are voluntary and not payment for sacrament. See `docs/POLICY-NOTES.md`.

## Architecture (high level)

- **Postgres**: SignatureGate core data (members, agreements, releases, donations, audit_log)
- **Appsmith**: Operator-facing UI (facilitators, reviewers)
- **n8n**: Orchestration and external integrations (Documenso, Givebutter, Airtable)
- **NocoDB**: Attachment and document storage
- **MushroomProcess**: External inventory source (linked by ID only)
- **Shared deployment architecture**: maintained separately in the RootedOps repository

See `docs/ARCHITECTURE.md` for details.

## Deployment

SignatureGate no longer carries the full production deployment stack in this repository.

Production infrastructure, reverse proxy, ERPNext, Grav, backups, and host-level deployment are maintained in the separate **RootedOps** repository.

This repository focuses on:
- database schema and migrations
- Appsmith application assets
- integration documentation
- workflow specifications

## License

This repository is licensed under **GNU GPL v3.0** (see `LICENSE`).

Rationale: MushroomProcess is GPL; choosing GPLv3 here keeps license compatibility to allow for shared code or common modules between projects.

## Development notes

- Database schema (baseline): `db/schema.sql`
- Seed data: `db/seed.sql` (optional)
- n8n workflow stubs: `n8n/workflows/`
- Appsmith screen specs: `appsmith/SCREENS.md`

## Security / privacy note

This system will store personal contact info and signed agreement references. Use:
- TLS (Caddy/Traefik), strong passwords, least-privilege DB users
- Encrypted storage for documents (S3 compatible / object storage recommended)
- Regular backups (Postgres + object storage)

## Audit Logging

SignatureGate maintains a centralized, append-only audit trail in `public.audit_log`.

The audit log records all legally, spiritually, and operationally significant events, including:

- Authentication failures
- Member creation and status changes
- Agreement approval / rejection
- Sacrament release issuance
- Donation creation and verification
- External webhook-driven state changes

Audit logging is legally and spiritually significant and must never be bypassed.

### Design principles

- Audit records are **append-only** and must never be modified or deleted.
- Audit logging is **not** a debugging or analytics system.
- If an action would ever need to be explained, reviewed, or defended later, it must be audited.

### Where audits are written

- **Appsmith**
  - User-initiated actions (auth, member creation, agreement issuance, release issuance)
- **n8n**
  - External system callbacks (Documenso)
  - Final irreversible workflow steps (product shipment)

Audit writes are intentionally split this way to ensure:
- correct actor attribution
- durability even when external systems are involved

## Member contact methods architecture

SignatureGate no longer treats email or phone number as a single-field identity attribute.

Members may now have:

- Multiple email addresses
- Multiple phone numbers
- Multiple physical addresses

These are stored in:

- `member_emails`
- `member_phones`
- `member_addresses`

The legacy `members.email` and `members.phone` fields remain for compatibility and display purposes only and should not be treated as authoritative identity sources.

### Active vs archived contact methods

Contact methods are append-only operational records.

Incorrect assignments should generally be:

- archived
- or reassigned

rather than deleted.

Tables include:

- `status`
- `archived_at`
- `archived_by`
- `archive_reason`

### Email verification

`member_emails.is_verified` indicates that the organization has evidence the member controls the address.

Verification occurs when:

1. A document reviewer manually verifies the address
2. A Documenso agreement sent to that address is signed successfully

Verification metadata:

- `verified_at`
- `verified_by`
- `verification_source`
- `verification_notes`

### Phone normalization

Phone numbers are normalized using `normalize_us_phone()`.

US numbers:

- `(303) 555-1212`
- `3035551212`
- `+13035551212`

normalize to the same canonical value.

Duplicate active normalized phone numbers are prevented by a partial unique index.

## Authentication and role-based access (Appsmith)

SignatureGate is intended to be deployed as a **private Appsmith app** (login required). The app reads the authenticated user identity from:

- `appsmith.user.email`

…and maps that email to a row in `public.members` to determine permissions.

### Roles

- **Facilitator**: `members.is_facilitator = TRUE`
  - Can use the app.
  - Member directory results are scoped to: members they created, members where they are the facilitator on an agreement, or members where a sacrament release exists with them as facilitator.

- **Document Reviewer**: `members.is_document_reviewer = TRUE`
  - Sees the full member directory (for review/QA workflows).

### Deployment requirements

- Do **not** make the app public.
- Create Appsmith users (invite) using the **same email** you store in `members.email`.
- Ensure the member row is `status='active'` and has the appropriate role flag(s).

Implementation details and troubleshooting are in `appsmith/GETTING_STARTED.md`.

## Multi-facilitator architecture

Members may now be assigned to multiple facilitators simultaneously.

Assignments are stored in:

- `member_facilitators`

This replaces the earlier single-facilitator relationship model.

### Facilitator access

Facilitators may:

- manage member profile information
- upload agreements
- request digital agreements
- issue releases
- review donations (if reviewer)
- manage storage location access (if reviewer)

### Storage location access

Storage locations are no longer implicitly tied to facilitator names.

Access is controlled through:

- `facilitator_storage_location_access`

Multiple facilitators may access the same storage location.

This architecture supports future separation between:

- inventory ownership
- physical custody
- facilitator operational access

## Documenso signing

### Documenso database migrations

If you enable Documenso integration, apply the Documenso migration(s) in addition to the core schema/migrations:

- `db/migrations_documenso_integration.sql`
- `db/migrations_documenso_integration_1.sql`

See `n8n/DOCUMENSO_INTEGRATION.md` for the Documenso workflow wiring and tokens.

Two-party signing (Member + Facilitator) is implemented via n8n + Documenso.

- Setup & workflows: `n8n/DOCUMENSO_INTEGRATION.md`
- Certificate troubleshooting: `deploy/DOCUMENSO_CERT_TROUBLESHOOTING.md`

## Donations (Cash & Givebutter)

SignatureGate supports tracking **voluntary donations** independently of sacrament release.

- **Cash donations** are entered manually by facilitators and require reviewer verification.
- **Givebutter donations** are ingested automatically via webhook and marked verified on receipt.
- Donations are **never** used as a prerequisite or gate for sacrament release.

All donation lifecycle events are recorded in the audit log.

## Givebutter donation review workflow

Givebutter donations are no longer allowed to automatically create new members solely by email address matching.

Incoming Givebutter donations now follow this flow:

1. Attempt identity resolution using:
   - member_emails
   - member_phones
   - legacy members.email
   - legacy members.phone

2. If no confident match exists:
   - donation is inserted with:
     - `status = 'pending_review'`
     - `member_id = NULL`

3. Donations reviewers may:
   - assign donation to existing member
   - ignore/delete donation
   - create a new member from donation data

### Donation-created members

When a reviewer creates a member from a pending donation:

- member record is created
- emails are inserted into member_emails
- phones are inserted into member_phones
- addresses are inserted into member_addresses
- donation is linked automatically

All actions are audit logged.

