# Inventory location scope correction

The exported **SignatureGate - PGSQL - List Available Sacrament Products** workflow now embeds [the helper](code/inventory_location_scope.js) exactly and uses it in `Code - Filter & Normalize`. Explicit empty, malformed or non-array JSON scope denies all rows, including when a legacy fallback parameter is supplied. Entirely omitted scope preserves the existing unscoped consumer contract. This filter does not authenticate or authorize a direct caller.

Only Code logic changed. Native workflow/node identities, authentication, credentials, query and response shape remain intact. Sample and shipped/consumed/expired exclusions remain enforced. No live workflow was changed.

Run `node scripts/test_inventory_location_scope.mjs`. The regression executes the actual saved Code for aggregated and direct SELECT rows, malformed/empty/one-grant/omitted scopes and product exclusions.

Before deployment, review the Code-only diff and install that Code in an isolated test copy with its database and authenticated route verified. Check one assigned scope and an empty scope there. Promote the reviewed Code into the existing production workflow only during the approved release window; do not overwrite credentials or import another environment's workflow wholesale. Keep the existing frontend scope guard.
