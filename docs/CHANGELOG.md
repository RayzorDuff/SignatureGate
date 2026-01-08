# Changelog

All notable changes to this project will be documented in this file.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

---

## [0.0.1-alpha] – 2026-01-08

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
