// Synthetic scopes only; no operational identifiers or product values.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const code = fs.readFileSync(new URL('../n8n/code/inventory_location_scope.js', import.meta.url), 'utf8');
const filter = vm.runInNewContext(code + '; inventoryLocationScope;');
const locations = ['Synthetic A', 'Synthetic B'];
const select = query => locations.filter(location => filter(query, [location]));
assert.equal(select({storage_locations_json:'[]'}).length, 0);
assert.equal(select({storage_locations_json:'invalid-json'}).length, 0);
assert.equal(select({storage_locations_json:'invalid-json', storage_location:'Synthetic A'}).length, 0);
assert.equal(select({storage_locations_json:'null'}).length, 0);
assert.equal(select({require_location_scope:'true'}).length, 0);
assert.equal(select({storage_locations_json:'["Synthetic A"]'}).length, 1);
assert.equal(select({storage_locations:'Synthetic B'}).length, 1);
assert.equal(select({storage_location:'synthetic a'}).length, 1);
assert.equal(select({}).length, 2, 'retain explicitly unscoped legacy/admin consumer behavior');
console.log('PASS requested empty/malformed storage scope denies all; explicit grants filter; unscoped compatibility retained');
