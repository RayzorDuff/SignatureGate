# Architecture & interoperability

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




