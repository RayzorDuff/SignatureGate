# SignatureGate – System Specification

## Overview

**SignatureGate** is an open-source compliance, agreement, and controlled-distribution system designed for nonprofit, membership-based organizations that distribute regulated or sensitive items, activities, or experiences.

SignatureGate is used by **Rooted Psyche** to ensure that:
- All members have executed required legal and doctrinal agreements
- Agreements are versioned, auditable, and provable (paper or digital)
- Regulated items received from a third-party producer (Dank Mushrooms) are only released to eligible members
- Traceability is maintained without coupling production inventory systems to membership data

SignatureGate is intentionally **separate but interoperable** with upstream inventory systems.

---

## Design Principles

1. **Separation of Concerns**
   - Production & inventory workflows live upstream (e.g., MushroomProcess)
   - Membership, agreements, and releases live in SignatureGate

2. **Clear Ownership Boundary**
   - Dank Mushrooms inventory responsibility ends at `products.product_id`
   - Rooted Psyche responsibility begins at `products.product_id`

3. **Agreement-First Enforcement**
   - No sacrament or regulated release may occur unless required agreements are signed
   - Enforcement occurs at both UI and workflow layers

4. **Auditability Over Automation**
   - Every agreement, release, and verification action is recorded
   - Paper workflows are first-class citizens

5. **Growth-Safe Modeling**
   - Multiple agreement types
   - Multiple activities (ceremonies, retreats, sweat lodge, land use)
   - Multiple enforcement contexts

---

## System Architecture

### Core Components

- **PostgreSQL**
  - `signaturegate_db` (Rooted Psyche data)
  - Optional: separate Postgres instance for MushroomProcess

- **NocoDB**
  - Admin/UI layer for tables
  - One base per database

- **n8n**
  - Workflow orchestration
  - Webhooks (Documenso, GiveButter, internal enforcement)

- **Appsmith**
  - Operator & facilitator UI
  - Hard-gated workflows for releases and check-ins

---

## Interoperability with MushroomProcess

### Authoritative Boundary

**Traceability anchor:**  
`products.product_id` (from MushroomProcess)

Rationale:
- Represents the packaged, transferable unit
- Marks the point where Dank Mushrooms inventory management ceases
- May aggregate multiple upstream lots
- Already documented and implemented in SignatureGate

### Data Stored in SignatureGate (Interop Fields)

SignatureGate **does not** replicate MushroomProcess inventory logic.

It stores only:
- `mushroomprocess_product_id` (string, required)
- Optional human-readable label or QR payload

No foreign keys or direct joins are required across databases.

---

## Core Data Model (SignatureGate)

### Members

Tracks individuals eligible for participation.

**members**
- `member_id` (UUID, PK)
- legal_name
- preferred_name
- email, phone
- status (prospective | active | suspended | archived)
- created_at, updated_at

---

### Agreement Templates

Defines required legal or doctrinal documents.

**agreements**
- `agreement_id` (UUID, PK)
- `agreement_type`
  - Examples:
    - `sacrament`
    - `retreat_liability`
    - `sweat_lodge`
    - `land_use`
    - `photo_release`
- `version`
- requires_signature (bool)
- effective_date
- retired_date
- template_reference (URL / storage pointer)
- notes

---

### Member Agreement Signatures

Execution evidence for agreements.

**member_agreements**
- `member_agreement_id` (UUID, PK)
- `member_id` (FK → members)
- `agreement_id` (FK → agreements)
- signature_status
  - required | sent | signed | declined | expired
- signature_method
  - paper | documenso | other
- signed_at
- document_url
- verified_by
- verified_at
- document_hash (optional, audit integrity)

---

### Activities (Optional but First-Class)

Represents ceremonies, retreats, or events.

**activities**
- `activity_id` (UUID)
- activity_type
- name
- start_datetime, end_datetime
- location
- notes

**activity_required_agreements**
- activity_type
- agreement_type
- minimum_version

---

### Sacrament / Regulated Releases

Represents the act of release to a member.

**releases**
- `release_id` (UUID)
- `member_id` (FK)
- release_datetime
- facilitator
- context (ceremony, integration, private)
- notes

**release_items**
- `release_item_id`
- `release_id` (FK)
- `mushroomprocess_product_id` (string, REQUIRED)
- quantity
- unit
- label_qr_payload (optional)
- required_agreement_type (default: `sacrament`)

This table is the **enforcement boundary**.

---

### Contributions (Non-Transactional)

Tracked separately from releases.

**contributions**
- `contribution_id`
- member_id (nullable)
- amount
- method (cash | givebutter | other)
- transaction_reference
- contributed_at
- notes

**Important:**  
No logic may ever link a contribution as a prerequisite for a release.

---

## Enforcement Model

### Rule: No Agreement → No Release

A release **MUST NOT** be recorded unless:
- The member has a signed, non-expired agreement of the required type
- The agreement version meets or exceeds the minimum required

### Enforcement Layers

1. **Appsmith UI**
   - Eligibility indicator on member selection
   - Submit button disabled if not eligible
   - Visual confirmation of agreement version

2. **n8n Workflow**
   - Server-side validation on release creation
   - Rejects invalid attempts
   - Logs enforcement failures

3. **Audit Visibility**
   - Queries showing:
     - releases without signed agreement (should be zero)
     - members missing required agreements

---

## n8n Event Specifications

### Documenso → Agreement Signed
- Trigger: Documenso webhook
- Actions:
  - Match member by email
  - Update `member_agreements`
  - Store document reference
  - Notify operators (optional)

### Paper Agreement Verified
- Trigger: Manual Appsmith action
- Actions:
  - Mark verified_by / verified_at
  - Lock agreement row

### Release Attempt
- Trigger: Appsmith webhook
- Actions:
  - Validate required agreements
  - If valid → create release + release_items
  - If invalid → reject + log

### GiveButter Contribution
- Trigger: GiveButter webhook
- Actions:
  - Create contribution record
  - Never modify release eligibility

---

## Appsmith Screen Set (v0)

1. Dashboard
2. Members
   - Profile
   - Agreement status
   - Release history
3. Agreements
   - Templates
   - Version management
4. Activities
   - Events
   - Required agreements
5. Release Workflow
   - Member select
   - Eligibility gate
   - Product ID entry / scan
6. Contributions
7. Audit / Compliance Views

---

## Licensing

**License:** GNU General Public License v3 (GPLv3)

Rationale:
- Matches MushroomProcess license
- Allows shared code and schema reuse
- Ensures improvements remain open
- Suitable for server-side and operational software

Rooted Psyche and Dank Mushrooms may each author or contribute files under GPLv3 while remaining distinct organizations.

---

## Non-Goals (Explicit)

- SignatureGate does NOT manage production inventory
- SignatureGate does NOT calculate costs or payments
- SignatureGate does NOT replace MushroomProcess
- SignatureGate does NOT infer consent from donations

---

## Future Extensions (Out of Scope for v0)

- Multi-org tenancy
- Automated renewal reminders
- Role-based facilitator permissions
- Mobile-first release scanning
- Cryptographic document notarization

---

## Summary

SignatureGate provides:
- Clear legal and operational boundaries
- Strong compliance guarantees
- Clean interoperability with production systems
- A reusable, open-source foundation for regulated membership organizations

