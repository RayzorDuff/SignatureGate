// A repeatedly evaluated obsolete download must never repeat the failed writes.
import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const source=fs.readFileSync(new URL('../releases/v1.2.0/rebuild_directory_startup.js',import.meta.url),'utf8');
let requests=0;const logs=[];
const context=vm.createContext({fetch:()=>{requests++;throw Error('Obsolete helper must not make requests');},console:{log:value=>logs.push(value)}});
for(let i=0;i<100;i++){
 const report=vm.runInContext(source,context);
 assert.equal(report.status,'retired');assert.equal(report.configuration_requests,0);
}
assert.equal(requests,0);
assert.equal(logs.length,100);
assert.ok(!Object.hasOwn(context,'location'));
assert.ok(logs.every(s=>JSON.parse(s).reason==='use_native_editor_settings'));
console.log('PASS obsolete startup repair: 100 evaluations, zero requests and no browser/application-state access');
