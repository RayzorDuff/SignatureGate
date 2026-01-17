# Changelog

All notable changes to this project will be documented in this file.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [v0.1.2-beta] — 2026-01-17

### Added
- **Comprehensive audit logging system** across Appsmith, n8n, and Postgres.
- New `audit_log` entries now record all legally and operationally significant events, including:
  - Authentication outcomes (`auth.granted`, `auth.denied`, `auth.failed`)
  - Member creation and lifecycle changes
  - Agreement creation, signing, and evidence attachment
  - Sacrament release issuance
  - Product shipment (final release completion step)
- **Documenso integration auditing**
  - When Documenso completes a signing event, n8n now records `member_agreement.signed` in `audit_log`.
- **Release completion auditing**
  - When a product is marked as shipped via n8n, `product.shipped` is recorded in `audit_log`.

### Changed
- **Audit responsibility clarified and consolidated**
  - Appsmith is now the primary source of audit writes for user-initiated actions.
  - n8n writes audit records only for external system callbacks and irreversible workflow steps.
- **Audit schema usage aligned**
  - Audit writes now conform to the existing `audit_log` schema:
    - `actor`, `action`, `entity_type`, `entity_id`, `details`
- **Improved correctness for JSON audit payloads**
  - n8n Postgres nodes now correctly quote JSON payloads before casting to `jsonb`.

### Fixed
- Fixed missing audit coverage for:
  - Agreement signing via Documenso
  - Product shipment marking
- Fixed JSON casting errors in n8n audit inserts.
- Fixed cyclic dependency issues in Appsmith audit helpers.

### Notes
- This release introduces **non-optional audit logging** for core workflows.
- Audit logging is append-only and is not intended for debugging or analytics.
- Downstream changes must preserve audit behavior when modifying agreement, release, or shipment flows.

## [v0.1.1-beta] — 2026-01-15

### Added
- **Role-based authentication and access control** using Appsmith authentication mapped to `public.members.email`.
  - App access is now gated at page load based on database roles.
  - Unauthorized users are redirected to an Unauthorized page in published mode.
- **Facilitator role support** via `members.is_facilitator`.
  - Facilitators may access the app and perform member, agreement, and release workflows.
- **Document reviewer role support** via `members.is_document_reviewer`.
  - Reviewers have global visibility of members and available products.
  - Facilitators who are also reviewers effectively act as admins.
- **Creator tracking for members** via `members.created_by_facilitator_id`.
  - Used to scope member visibility for non-reviewer facilitators.
- **Facilitator-scoped member directory**
  - Non-reviewer facilitators only see:
    - members they created
    - members they are a facilitator for on an agreement
    - members with sacrament releases issued by them
  - Reviewers see all members.
- **Facilitator-aware product availability filtering**
  - In *Release → Issue*, non-reviewer facilitators only see products located in a storage location matching their `"FirstName LastName"`.
  - Reviewers continue to see all available products.
- **Improved n8n upload handling**
  - The “SignatureGate – Upload Evidence via n8n (Base64 → NocoDB)” workflow now correctly preserves multiple uploaded files instead of dropping all but one.

---

### Changed
- **Authentication flow hardened**
  - Appsmith user context (`appsmith.user.email`) is now awaited before authorization checks.
  - Queries pass email as a parameter (`this.params.email`) instead of inlining Appsmith globals in SQL.
- **Authorization semantics clarified**
  - “Access denied” is now correctly distinguished from “Access check failed” (true errors vs. no role).
- **Member directory query consolidated**
  - Reviewer override logic moved into SQL, eliminating the need for UI-level conditional table bindings.
- **n8n product listing workflow**
  - Accepts an optional `storage_location` filter from Appsmith.
  - Filters available products by facilitator location when provided.

---

### Database
- Added migrations:
  - `migrations_facilitator_review.sql`
    - Facilitator and reviewer role flags
    - Agreement review support
  - `migrations_facilitator_authentication.sql`
    - `created_by_facilitator_id`
  - `migrations_sacrament_release.sql`
    - Facilitator linkage to sacrament releases
- Documented and clarified **migration order**.
- Documented **optional Documenso integration migrations**:
  - `migrations_documenso_integration.sql`
  - `migrations_documenso_integration_1.sql`

---

### Documentation
- Expanded `README.md` with:
  - Appsmith authentication model
  - Role definitions and behavior
  - Documenso database migration notes
- Expanded `db/README.md` with:
  - Explicit migration order
  - Verification steps
- Expanded `appsmith/GETTING_STARTED.md` with:
  - Required Appsmith configuration (non-public app)
  - User creation and role mapping
  - Runtime auth behavior
  - Troubleshooting checklist

---

### Fixed
- Fixed n8n Code node output normalization that caused multi-file uploads to collapse to a single file.
- Fixed inconsistent behavior between editor and published modes during authentication.
- Fixed edge cases where zero-row SQL results were incorrectly treated as runtime failures.

---

### Notes
- This release introduces **breaking behavior** for existing installations that do not apply the new facilitator/reviewer migrations.
- Appsmith apps **must not be public** for authentication to function correctly.
- Product storage locations must exactly match facilitator `"FirstName LastName"` for location-based filtering to work as intended.

## [v0.1.0-beta] – 2026-01-13

End-to-end Digital Agreement + Sacrament Release Pipeline

### Major Features
- Added full Documenso → n8n → Postgres → Appsmith signing lifecycle
- Agreements now transition automatically from:
  - pending_email_send
  - pending_signature
  - signed / rejected / cancelled
- Completed signed PDFs are now fetched from Documenso, Base64 encoded in n8n, and stored into NocoDB storage
- Signed documents are written back into SignatureGate as structured JSON evidence

### New Integrations
- Documenso webhooks normalized and correlated using:
  externalId = "ma:<member_agreement_id>"
- n8n now acts as the system of record bridge between:
  - Documenso
  - SignatureGate (Postgres)
  - NocoDB (file storage)
  - Airtable (inventory source)

### New Sacrament Gate
- A member must have a signed agreement for the active “sacrament_release” agreement template
- SignatureGate enforces agreement-template matching before sacrament issuance
- Supports multiple agreement types (e.g., sweat lodge, sacrament, facilitation)

### New Sacrament Release Workflow
- Appsmith “Release – Issue” page
- n8n workflows:
  - List available sacrament products from Airtable
  - Mark products as Shipped after issuance

### Inventory Enforcement
- Airtable products are filtered by:
  - item_category = freezedriedmushrooms
  - origin_strain_regulated = true
  - storage_location NOT IN (Shipped, Consumed, Expired)
- When issued, Airtable storage_location is updated to Shipped

### File Upload Reliability
- Switched NocoDB upload pipeline from multipart to Base64 JSON
- Eliminated Appsmith large-file upload instability
- n8n now handles all PDF ingestion for signed agreements

### Database Enhancements
- member_agreements now stores:
  - documenso_document_id
  - structured evidence JSON
- Agreement templates support multiple “required_for” types

### Operational Stability
- Correlation via externalId ensures all webhook events update the correct agreement
- Fully idempotent Documenso webhook processing

---

## [v0.0.1-alpha] – 2026-01-08

### Summary
Initial alpha release of **SignatureGate**, a member agreement and compliance tracking system designed to integrate with NocoDB, Appsmith, n8n, and Documenso.  
This release establishes a working deployment on Linode, a functional data model, importable Appsmith UI screens, and importable (but not yet fully exercised) n8n automation workflows.

This version is suitable for early adopters, developers, and system integrators, but **not yet recommended for production compliance use**.

---

### Added

#### Core Architecture
- PostgreSQL-backed data model for:
  - Members
  - Agreements
  - Agreement templates
  - Facilitators
  - Evidence (file attachments)
- Separation of concerns between:
  - Inventory systems (external / future integration)
  - Member agreement lifecycle
  - Signature and compliance workflows

#### Deployment & Infrastructure
- Linode deployment documentation and scripts
- Docker-based stack including:
  - NocoDB
  - Appsmith
  - n8n
  - PostgreSQL (multiple logical databases)
  - Documenso (self-hosted, glibc-based build)
- Nginx reverse-proxy configuration with:
  - HTTPS (Certbot)
  - Correct WebSocket handling for n8n
  - Separate virtual hosts per service
- Environment variable templates (`.env.example`) for reproducible installs

#### Appsmith Interface (Importable JSON)
Three functional UI screens:
1. **Members – Directory**
   - Browse and select existing members
   - View high-level agreement status
2. **Members – Intake**
   - Create new members
   - Assign facilitator
   - Choose agreement delivery method (digital or paper)
   - Upload paper agreement evidence
3. **Members – Profile**
   - View member details
   - View agreement history
   - Upload additional evidence
   - Trigger digital agreement workflows

Validation logic includes:
- Duplicate member detection (name, email, phone)
- Conditional facilitator requirements
- Conditional evidence upload requirements

#### Agreement Evidence Handling
- Support for multiple file uploads per agreement
- Evidence stored using NocoDB Attachment fields
- Downloadable evidence links rendered in Appsmith tables
- Manual review workflow support for paper agreements

#### Documenso Integration
- Self-hosted Documenso deployment
- Two-signer agreement model:
  - Member
  - Facilitator
- Agreement template configuration using Documenso envelope recipients
- PKCS#12 local signing certificate support

#### n8n Automations (Importable JSON)
- **Send Agreement Workflow**
  - Accepts `member_agreement_id`
  - Generates document from Documenso template
  - Sends to both signers
  - Updates agreement status in PostgreSQL
- **Documenso Webhook Workflow**
  - Receives document lifecycle events
  - Updates agreement status on completion, rejection, or cancellation

> Note: n8n workflows are importable and configured but **have not yet been fully end-to-end tested in production**.

#### Documentation
- Deployment guides
- Architecture overview
- n8n integration guide
- Documenso integration guide
- Troubleshooting documentation for:
  - Alpine vs glibc issues
  - Playwright / Chromium dependencies
  - WebSocket proxying
  - PKCS#12 certificate compatibility

---

### Fixed

#### Documenso Signing Failures
- Resolved documents stuck in “Processing” state after all signers completed
- Root cause identified as PKCS#12 incompatibility
- Fixed by exporting signing certificate using **legacy algorithms**:
  - `openssl pkcs12 -export -legacy`
- Documented exact failure mode and resolution

#### Chromium / Playwright Issues
- Resolved missing Chromium binary and musl/glibc incompatibility
- Migrated Documenso to Debian-based build
- Ensured Playwright-managed Chromium runs reliably for PDF generation

#### n8n WebSocket Stability
- Fixed repeated `Connection lost (1006)` errors
- Root causes:
  - Incorrect nginx virtual host
  - IPv6 loopback proxying
  - Missing WebSocket upgrade headers
- Added correct nginx configuration for stable long-lived WebSocket connections

---

### Known Limitations / Alpha Notes
- n8n workflows have not yet been exercised under real signing traffic
- Inventory integration (Airtable or NocoDB-based) is not yet implemented
- No role-based access control (RBAC) in Appsmith
- No audit log UI beyond database records
- No automated reminder or escalation workflows
- No production hardening or security review yet

---

### Next Planned Work
- End-to-end testing of Documenso → n8n → PostgreSQL workflows
- Agreement Templates management UI
- Manual agreement reviewer workflow
- Inventory linkage for sacrament release eligibility
- RBAC and facilitator/reviewer role separation
- Exportable compliance and audit reports

---

**This release represents a solid technical foundation and learning milestone, not a finished compliance system.**
