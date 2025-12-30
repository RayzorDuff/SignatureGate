# Architecture & interoperability

## Goals

1. Keep Nonprofit membership/legal agreements **separate** from MushroomProcess inventory.
2. Maintain **traceability** from “sacrament release” → MushroomProcess `products.product_id`.
3. Allow growth: additional agreements (retreats, sweat lodge), additional sacraments, additional funding sources.

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

