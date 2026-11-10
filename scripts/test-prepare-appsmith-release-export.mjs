import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'signaturegate-pinned-export-'));
const source=path.join(temp,'source'), production=path.join(temp,'production');
const script=new URL('./prepare-appsmith-release-export.mjs',import.meta.url).pathname;
function write(root,file,value){const p=path.join(root,file);fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,JSON.stringify(value));}
function git(root,...args){const x=spawnSync('git',['-C',root,...args],{encoding:'utf8'});assert.equal(x.status,0,x.stderr);return x.stdout.trim();}
function commit(root){git(root,'add','.');git(root,'-c','user.name=Synthetic','-c','user.email=synthetic@example.invalid','commit','-qm','fixture');return git(root,'rev-parse','HEAD');}
try {
 const descriptor={name:'signaturegate-postgres',pluginId:'postgres-plugin',gitSyncId:'native-production-identity'};
 write(production,'datasources/signaturegate-postgres.json',descriptor);
 write(source,'application.json',{pages:[{id:'Test',isDefault:true}]});
 write(source,'metadata.json',{artifactJsonType:'APPLICATION'});
 write(source,'pages/Test/Test.json',{unpublishedPage:{name:'Test',layouts:[{dsl:{widgetName:'MainContainer',widgetId:'0'}}]}});
 write(source,'datasources/signaturegate-postgres-test.json',{name:'signaturegate-postgres-test',pluginId:'postgres-plugin'});
 write(source,'pages/Test/queries/q/metadata.json',{id:'Test_q',gitSyncId:'native-query',pluginType:'DB',unpublishedAction:{name:'q',datasource:{name:'signaturegate-postgres-test',id:'signaturegate-postgres-test',pluginId:'postgres-plugin'},actionConfiguration:{body:'SELECT 1'},runBehaviour:'MANUAL'}});
 git(source,'init','-q');git(production,'init','-q');const sha=commit(source), prodSHA=commit(production);
 const output=path.join(temp,'out.json'), provenance=path.join(temp,'provenance.json');
 const args=['--source',source,'--production-source',production,'--source-sha',sha,'--production-source-sha',prodSHA,'--output',output,'--provenance',provenance];
 const run=(a=args)=>spawnSync(process.execPath,[script,...a],{encoding:'utf8'});
 let result=run();assert.equal(result.status,0,result.stderr+result.stdout);
 const first=fs.readFileSync(output), record=fs.readFileSync(provenance);
 result=run();assert.equal(result.status,0,result.stderr);assert.deepEqual(fs.readFileSync(output),first);assert.deepEqual(fs.readFileSync(provenance),record);
 const x=JSON.parse(record);assert.equal(x.sourceCommit,sha);assert.equal(x.productionDescriptorCommit,prodSHA);assert.equal(x.runtimeVerified,false);
 assert.equal(git(source,'status','--porcelain'),'');assert.ok(fs.existsSync(path.join(source,'datasources/signaturegate-postgres-test.json')));
 for(const flag of ['--source-sha','--production-source-sha']) {
  const bad=[...args];bad[bad.indexOf(flag)+1]='master';assert.notEqual(run(bad).status,0);
  bad[bad.indexOf(flag)+1]='0'.repeat(40);assert.notEqual(run(bad).status,0);
 }
 fs.writeFileSync(path.join(source,'untracked.txt'),'uncaptured source');assert.match(run().stderr,/must be clean/);fs.unlinkSync(path.join(source,'untracked.txt'));
 write(production,'datasources/signaturegate-postgres.json',{...descriptor,gitSyncId:'drift'});assert.match(run().stderr,/must be clean/);
 console.log('PASS pinned export: deterministic dual-SHA provenance, descriptor preservation, source isolation, moving/mismatched refs and dirty inputs rejected');
} finally {fs.rmSync(temp,{recursive:true,force:true});}
