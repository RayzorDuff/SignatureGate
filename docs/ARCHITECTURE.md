# Architecture & interoperability

## Repository boundaries

This repository contains the SignatureGate application definition:
- database schema and migrations
- Appsmith assets
- integration and workflow documentation

Shared infrastructure and deployment architecture are maintained in the separate RootedOps repository.
That includes host provisioning, reverse proxy, container orchestration, ERPNext deployment, Grav deployment, and backup operations.

## Goals

1. Keep Nonprofit membership/legal agreements **separate** from MushroomProcess inventory.
2. Maintain **traceability** from “sacrament release” → MushroomProcess `products.product_id`.
3. Allow growth: additional agreements (retreats, sweat lodge), additional sacraments, additional funding sources.

## Mental Model

                   ┌────────────┐
                   │ Appsmith   │
                   │ (UI Layer) │
                   └─────┬──────┘
                         │
                         ▼
                 SignatureGate API
                  (Postgres DB)
                         │
      ┌──────────────────┼──────────────────┐
      │                  │                  │
      ▼                  ▼                  ▼
 Documenso            n8n Engine           NocoDB
 (Signing)           (Orchestration)       (File store)
                        │
                        ▼
                    Airtable
                (Inventory of sacrament SKUs)

## System Responsibility

| System                       | Responsibility                                                                      |
| ---------------------------- | ----------------------------------------------------------------------------------- |
| **Appsmith**                 | Operator UI. Never talks to Documenso or Airtable directly.                         |
| **SignatureGate (Postgres)** | Legal truth: members, agreements, evidence, issuance.                               |
| **Documenso**                | Signing engine. Knows nothing about inventory or members.                           |
| **n8n**                      | Orchestrator and glue. Converts between Documenso, Airtable, NocoDB, SignatureGate. |
| **NocoDB**                   | Object store for PDFs and uploads.                                                  |
| **Airtable**                 | Live product inventory from MushroomProcess.                                        |

## Interop patterns (recommended)

### Pattern A (simplest): ID-only link + on-demand lookup
- SignatureGate stores:
  - `mushroomprocess_product_id` (string)
- UI/operator verifies lot exists by calling MushroomProcess API (n8n can cache).
- Pros: simplest; minimal coupling.
- Cons: requires MushroomProcess reachable at runtime.

### Pattern B (recommended): “bridge cache” in Postgres #2
- n8n periodically syncs selected fields from MushroomProcess into `mushroomprocess_bridge` schema:
  - `product_id`, strain/species, regulated flag, produced_at, etc.
- SignatureGate uses FK **within its own DB** to the cached lot table (or just joins by product_id string).
- Pros: robust; allows offline-ish operation and faster UI.
- Cons: slightly more plumbing (sync).

### Pattern C (advanced): Postgres FDW
- Use `postgres_fdw` to expose MushroomProcess tables inside SignatureGate DB.
- Pros: “real” joins without ETL.
- Cons: more ops complexity, permissions, failure modes. Do this later if needed.

## NocoDB layout

- Base: **SignatureGate**
  - Primary data source: `signaturegate_db`
  - Optional 2nd data source: `mushroomprocess_bridge_db`

NocoDB supports connecting external databases as data sources inside a base. citeturn0search6

Note: relationships across different data sources may be limited; plan on joining in Appsmith / n8n rather than expecting cross-source relational UI to “just work.”

## Document signing integration

SignatureGate uses Documenso for two-party signing (Member + Facilitator).
The UI triggers signing via an n8n webhook, and Documenso webhooks update agreement status back into Postgres.
See `n8n/DOCUMENSO_INTEGRATION.md`.

### Agreement Types

Agreement types (e.g. `sacrament_release`, `membership`, `retreat`) are stored as
first-class records in the database and act as the canonical source of truth for:

- Which agreements apply to which workflows
- Which templates may be selected by facilitators
- Validation of agreement templates

Agreement templates may reference one or more agreement types and may exist in
multiple variants (e.g. language versions).

## End-to-End Flows

### Digital Agreement Flow

Appsmith → Postgres
  INSERT member_agreements (pending_email_send)

Appsmith → n8n → Documenso
  externalId = "ma:<member_agreement_id>"

Documenso → n8n Webhook
  event: DOCUMENT_SENT → pending_signature
  event: DOCUMENT_OPENED → pending_signature
  event: DOCUMENT_COMPLETED → signed

n8n → Documenso
  GET PDF

n8n → NocoDB
  Upload Base64 PDF

n8n → Postgres
  UPDATE member_agreements
    status = signed
    evidence = [ { path, title, mimetype, size, signedPath } ]

### Sacrament Release Gate

member has member_agreements.status = 'signed'
AND
agreement_templates.required_for contains 'sacrament_release'

### Inventory Flow

Appsmith → n8n → Airtable
  List products WHERE:
    item_category = freezedriedmushrooms
    origin_strain_regulated = true
    storage_location NOT IN (Shipped, Consumed, Expired)

User selects product

Appsmith → n8n → Airtable
  Update product.storage_location = Shipped

n8n → SignatureGate
  Insert sacrament_release record

## Audit Logging Model

Audit logging in SignatureGate is designed to be:
- authoritative
- durable
- legally defensible

Audit logging is split by responsibility:
- **Appsmith** records user intent and operator actions
- **n8n** records completion of external or irreversible workflows

Future changes must preserve this split.

All audit records are append-only and retained indefinitely.

## Donations Architecture

Donations are tracked as first-class records within SignatureGate and are intentionally separated from sacrament release logic.

### Donation Sources
- **Cash**: entered manually by facilitators
- **Givebutter**: ingested automatically via webhook

### Processing Model
- Cash donations require reviewer verification
- Givebutter donations are verified automatically on receipt
- Donations are never used as gating criteria for sacrament release

### Webhook Flow (Givebutter)

Givebutter → n8n webhook → SignatureGate Postgres

n8n responsibilities:
- Validate webhook
- Normalize donor identity
- Match or create member
- Insert donation (verified)
- Write audit log entry

## Donations & External Funding Sources

Donations are modeled as first-class records in SignatureGate but are intentionally
decoupled from sacrament release logic.

### Sources
- Manual cash entry (facilitator → reviewer workflow)
- Automated Givebutter ingestion via n8n webhook

### Givebutter Webhook Flow

Givebutter → n8n → SignatureGate (Postgres)

n8n responsibilities:
- Validate webhook (optional shared secret)
- Normalize donor identity
- Match or create member by email
- Insert donation as verified
- Write audit log entry

Donations do not participate in release gating logic.
