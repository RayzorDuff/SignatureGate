import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const source=fs.readFileSync(new URL('../releases/v1.2.0/rebuild_directory_startup.js',import.meta.url),'utf8');
const origin='https://synthetic-appsmith.example.invalid',pageId='a'.repeat(24),appId='b'.repeat(24);
const names=['navigationLabels.initialize','directoryFlows.load'];
function fixture(options={}) {
 const calls=[],logs=[];let schedule=[];
 const collections=names.map((name,i)=>({id:String(i+1).repeat(24),applicationId:appId,pageId,name:name.split('.')[0],pluginType:'JS',body:'fixture-private-body',actions:[{id:String(i+3).repeat(24),pageId,collectionId:String(i+1).repeat(24),name:name.split('.')[1],fullyQualifiedName:name,pluginType:'JS',runBehaviour:'ON_PAGE_LOAD',userSetOnLoad:true}]}));
 if(options.missing)collections[1].actions=[];
 if(options.duplicate)collections.push(structuredClone(collections[0]));
 if(options.foreign)collections[1].applicationId='c'.repeat(24);
 if(options.wrongPlugin)collections[1].actions[0].pluginType='DB';
 if(options.badId)collections[1].actions[0].id='not-a-resource-id';
 if(options.wrongFunction)collections[1].actions[0].fullyQualifiedName='unrelated.write';
 function page(){return {id:pageId,applicationId:appId,name:options.otherPage?'Reports':'Directory',layouts:[{dsl:{contact:'fixture-private-contact'},layoutOnLoadActions:[schedule],layoutOnLoadActionErrors:options.cycle?[{message:'fixture-private-cycle'}]:[]}]};}
 const c={URL,Date,location:{href:origin+(options.path||'/app/synthetic/directory')+'?branch='+(options.branch||'chatgpt_development')},console:{log:v=>logs.push(v)},fetch:async(url,config)=>{
  calls.push({url,config});const u=new URL(url);let data;
  if(options.http && u.pathname.startsWith('/api/v1/collections/'))return {ok:false,status:403};
  if(config.method==='PUT'){
   const target=collections.flatMap(c=>c.actions).find(a=>u.pathname.endsWith('/'+a.id));
   if(options.failSecond && calls.filter(c=>c.config.method==='PUT').length===2)throw Error('fixture-private-error');
   assert.ok(target,'only allowlisted existing functions can be updated');
   assert.equal(u.searchParams.get('behaviour'),'ON_PAGE_LOAD');
   if(!options.blocked)schedule=[...schedule,{name:target.fullyQualifiedName}];
   data={...target};if(options.savedMismatch)data.pageId='c'.repeat(24);
  } else if(u.pathname==='/api/v1/consolidated-api/view')data={pageWithMigratedDsl:{data:page()},userProfile:{contact:'fixture-private-contact'}};
  else if(u.pathname==='/api/v1/collections/actions')data=collections;
  else {assert.equal(u.pathname,'/api/v1/pages/'+pageId);assert.equal(u.searchParams.get('migrateDsl'),'false');data=page();}
  return {ok:true,status:200,json:async()=>({responseMeta:{success:true},data})};
 }};
 return {calls,logs,run:()=>vm.runInNewContext(source,c)};
}
function privateOutput(x){assert.doesNotMatch(x.logs.join(''),/fixture-private|example\.invalid|[abcd1234]{24}|dsl|applicationId|pageId|collectionId/);}
{const x=fixture();const r=await x.run();assert.equal(r.status,'editor_schedule_rebuilt');assert.equal(r.before.action_count,0);assert.equal(r.after.navigation_registered,true);assert.equal(r.after.directory_registered,true);assert.deepEqual([...r.updated_functions],names);const writes=x.calls.filter(c=>c.config.method==='PUT');assert.equal(writes.length,2);for(const call of x.calls){assert.equal(new URL(call.url).origin,origin);assert.equal(call.config.redirect,'error');assert.equal(call.config.headers.branchName,'chatgpt_development');assert.equal(call.config.headers['X-Requested-By'],'Appsmith');assert.equal(Object.hasOwn(call.config,'body'),false);assert.ok(['GET','PUT'].includes(call.config.method));}privateOutput(x);}
for(const option of ['missing','duplicate','foreign','wrongPlugin','badId','wrongFunction','otherPage','http']){const x=fixture({[option]:true});const r=await x.run();assert.equal(r.status,'stopped',option);assert.equal(x.calls.filter(c=>c.config.method==='PUT').length,0,option+' must stop before any writes');privateOutput(x);}
{const x=fixture({branch:'master'});const r=await x.run();assert.equal(r.reason,'development_branch_required');assert.equal(x.calls.length,0);}
{const x=fixture({failSecond:true});const r=await x.run();assert.equal(r.status,'stopped');assert.equal(r.updated_functions.length,1);assert.equal(r.attempted_functions.length,2);assert.equal(x.calls.filter(c=>c.config.method==='PUT').length,2);privateOutput(x);}
{const x=fixture({savedMismatch:true});const r=await x.run();assert.equal(r.reason,'saved_registration_mismatch');assert.equal(x.calls.filter(c=>c.config.method==='PUT').length,1);privateOutput(x);}
for(const option of ['blocked','cycle']){const x=fixture({[option]:true});assert.equal((await x.run()).status,'editor_schedule_still_blocked');privateOutput(x);}
for(const path of ['/app/synthetic/directory-'+pageId+'/edit','/applications/'+appId+'/pages/'+pageId+'/edit']){const x=fixture({path});assert.equal((await x.run()).status,'editor_schedule_rebuilt');assert.ok(!x.calls.some(c=>new URL(c.url).pathname.includes('consolidated-api')));privateOutput(x);}
console.log('PASS Directory startup rebuild: two allowlisted native settings, pre-write identity/missing/duplicate/plugin guards, branch restriction, server schedule verification, partial failure without retry, privacy and no execution/deploy/source-body request');
