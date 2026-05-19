# SignatureGate PGSQL n8n Workflow Duplicates

Generated for SignatureGate issue #5.

These workflows duplicate the Airtable-backed inventory bridge workflows with PostgreSQL-backed equivalents for the MushroomProcess cutover.

## Generated workflows

- `SignatureGate - PGSQL - List Available Sacrament Products.json`
- `SignatureGate - PGSQL - Mark Product Shipped.json`
- `SignatureGate - PGSQL - Mark Product UnShipped.json`

## Webhook paths

The PGSQL duplicates intentionally use new `/pgsql/` webhook paths so they can be imported next to the existing Airtable workflows without route conflicts:

- `/webhook/signaturegate/pgsql/products/available`
- `/webhook/signaturegate/pgsql/products/mark_shipped`
- `/webhook/signaturegate/pgsql/products/mark_unshipped`

After validation, update Appsmith from the old Airtable paths:

- `/webhook/signaturegate/airtable/products/available`
- `/webhook/signaturegate/airtable/products/mark_shipped`
- `/webhook/signaturegate/airtable/products/mark_unshipped`

## Credential notes

The product list/update nodes must use the PostgreSQL credential connected to the MushroomProcess Postgres database, because they read and update `public.products`, `public.locations`, and `public.strains`.

The audit nodes write to SignatureGate `public.audit_log`. If your n8n instance uses separate credentials/databases for MushroomProcess and SignatureGate, set the audit nodes to the SignatureGate Postgres credential and set the product inventory nodes to the MushroomProcess Postgres credential.

## Behavior preserved from the Airtable workflows

### List Available Sacrament Products

Returns the same response envelope shape:

```json
{
  "ok": true,
  "data": [],
  "filter": {
    "storage_locations": []
  }
}
```

Each product includes:

- `airtable_record_id` for legacy Appsmith compatibility, populated from `products.airtable_id` when available or `products.nocopk` as a fallback.
- `mushroomprocess_product_id`
- `item_name`
- `strain`
- `net_weight_g`
- `unit`
- `storage_location`
- `storage_locations`

The list filters to regulated freeze-dried mushroom products that are not in Shipped, Consumed, or Expired. It continues to support the existing query parameters:

- `storage_location=Location Name`
- `storage_locations=Location A,Location B`
- `storage_locations_json=["Location A","Location B"]`

### Mark Product Shipped

Accepts either:

- `airtable_record_id` for legacy Appsmith callers, or
- `mushroomprocess_product_id` / `product_id` for Postgres-era callers.

Updates `products.storage_location_id` to the `locations` row named `Shipped`.

### Mark Product UnShipped

Accepts:

- `mushroomprocess_product_id` / `product_id`
- `storage_location_name` / `storage_location`

Updates `products.storage_location_id` to the named target location.

## Import/validation checklist

1. Import the three JSON workflows into n8n.
2. Assign the MushroomProcess Postgres credential to the `PGSQL - ...` inventory nodes.
3. Assign the SignatureGate Postgres credential to the `PG - Audit ...` nodes, or disable/remove those audit nodes if you do not want cross-project audit writes.
4. Keep the workflows inactive until Appsmith webhook paths are updated.
5. Test the `/webhook-test/signaturegate/pgsql/products/available` endpoint first.
6. Test mark shipped against a non-production or reversible product row.
7. Test mark unshipped with the original storage location.
8. Update Appsmith webhook URLs from `/airtable/` to `/pgsql/` once validated.

## Known assumptions

These workflows assume the MushroomProcess database has these public objects from the current Postgres migration:

- `products.product_id`
- `products.airtable_id`
- `products.name_mat`
- `products.item_category_mat`
- `products.net_weight_g`
- `products.storage_location_id`
- `products.strain_id`
- `locations.nocopk`
- `locations.name`
- `strains.nocopk`
- `strains.species_strain`
- `strains.regulated`

