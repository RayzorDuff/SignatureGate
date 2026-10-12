# Inventory location filter candidate

The isolated [Code-node helper](code/inventory_location_scope.js) contains no credentials, instance identifiers, deployment targets or operational inventory values. It denies an explicitly requested empty or malformed storage-location scope. Consumers that omit scope entirely retain their existing behavior; this helper does not authorize direct HTTP callers.

To validate in an independently reviewed test workflow:

1. Copy the helper function above the existing Code node logic.
2. Replace the existing `allowedLocationSet.size > 0` location-filter condition with:

   ```javascript
   if (!inventoryLocationScope(req?.query || {}, locNames)) continue;
   ```

3. Keep the existing eligibility checks and response shape. Test an empty array, malformed JSON, one synthetic grant and an omitted scope. Empty/malformed requests must return no rows; one grant must return only that location.
4. Verify authenticated caller scope and the test datasource/route before publication. Production publication requires Phase 5 acceptance. Do not import or overwrite the shared production workflow for development validation.

Run the synthetic helper checks with `node scripts/test_inventory_location_scope.mjs`.

The workflow export was excluded from this increment because automatic approval review rejected its operational credential references, instance metadata and product/location configuration. The Appsmith frontend independently prevents requests and display when no authorized location is assigned, including with the currently published workflow. The isolated helper still requires test integration and deployment acceptance.
