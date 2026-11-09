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

// Exercise the saved workflow Code, including direct SELECT rows and eligibility.
const workflow = JSON.parse(fs.readFileSync(new URL('../n8n/workflows/SignatureGate - PGSQL - List Available Sacrament Products.json', import.meta.url)));
const saved = workflow.nodes.find(node => node.name === 'Code - Filter & Normalize').parameters.jsCode;
assert.ok(saved.startsWith(code), 'workflow must embed the reviewed helper exactly');
const products = [
 {mushroomprocess_product_id:'synthetic-a',storage_locations:['Synthetic A'],package_class:'retail'},
 {mushroomprocess_product_id:'synthetic-b',storage_locations:['Synthetic B'],package_class:'retail'},
 {mushroomprocess_product_id:'synthetic-sample',storage_locations:['Synthetic A'],package_class:'sample'},
 {mushroomprocess_product_id:'synthetic-expired',storage_locations:['Synthetic A','Expired'],package_class:'retail'}
];
function execute(query, direct = false) {
 const $ = name => name === 'Webhook - List Products'
   ? {first:()=>({json:{query}})}
   : {first:()=>({json:direct ? products[0] : {records:JSON.stringify(products)}}),all:()=>products.map(json=>({json}))};
 return vm.runInNewContext('(function(){'+saved+'})()', {$})[0].json;
}
for (const direct of [false,true]) {
 for (const q of [{storage_locations_json:'[]'},{storage_locations_json:'bad',storage_location:'Synthetic A'},{storage_locations_json:'null'},{storage_location:''},{require_location_scope:'true'}]) assert.equal(execute(q,direct).count,0);
 assert.equal(execute({storage_locations_json:'["Synthetic A"]'},direct).data[0].mushroomprocess_product_id,'synthetic-a');
 assert.equal(execute({storage_locations_json:'["Synthetic A"]'},direct).count,1);
 assert.equal(execute({},direct).count,2,'legacy omission retains eligibility filters');
}
console.log('PASS saved workflow: empty/malformed scope, legacy precedence, one grant, omitted scope, sample/expired exclusions, aggregate and direct rows');
