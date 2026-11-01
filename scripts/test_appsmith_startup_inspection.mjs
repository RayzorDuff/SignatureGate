import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source=fs.readFileSync(new URL('../releases/v1.2.0/inspect_appsmith_startup.js',import.meta.url),'utf8');
const origin='https://synthetic-appsmith.example.invalid',id='a'.repeat(24),otherId='b'.repeat(24);
const uuid='12345678-1234-1234-1234-123456789abc';
function fixture({branch='chatgpt_development',editor=true,published=false,cycle=false,http=200,observed=true,staticUrl=false,path,pageId=id,malformed=false,networkError=false}={}) {
 const calls=[],logs=[];
 const route=path || (staticUrl?'/app/synthetic/directory':'/app/synthetic/directory-'+pageId);
 const startup=staticUrl?'/api/v1/consolidated-api/view?applicationId=synthetic&defaultPageId=directory&branchName=chatgpt_development':'/api/v1/pages/'+pageId+'/view';
 const c={URL,Date,location:{href:origin+route+'?branch='+branch},performance:{getEntriesByType:()=>observed?[
  {name:origin+'/api/v1/pages/'+otherId+'/view',startTime:40},
  {name:origin+startup,startTime:10},
  {name:origin+'/api/v1/actions/execute',startTime:20},
  {name:'https://other.example.invalid/api/v1/pages/'+id+'/view',startTime:50}
 ]:[]},console:{log:s=>logs.push(s)},fetch:async(url,options)=>{
  calls.push({url,options});if(networkError)throw Error('fixture-private-network-error');
  const u=new URL(url),combined=u.pathname==='/api/v1/consolidated-api/view';
  const enabled=(combined || u.pathname.endsWith('/view'))?published:editor;
  const page={id:pageId,name:malformed?'fixture-private-page':'Directory',private_contact:'fixture-private-contact',layouts:[{dsl:{private_record:'fixture-private-record'},layoutOnLoadActions:enabled?[[{name:'navigationLabels.initialize',collectionId:'software-collection-id'},{name:'directoryFlows.load'},{name:'fixture-private-function'}]]:[],layoutOnLoadActionErrors:cycle?[{message:'Cyclic dependency; fixture-private-error-text'}]:[]}],query_results:[{amount:'fixture-private-amount'}]};
  return {ok:http===200,status:http,json:async()=>({data:combined?{pageWithMigratedDsl:{data:page},userProfile:{data:{name:'fixture-private-person'}},publishedActions:{data:[{body:'fixture-private-body'}]},pages:{data:{pages:[page]}}}:page})};
 }};
 return {c,calls,logs,run:()=>vm.runInNewContext(source,c)};
}
function safeReads(x){
 assert.equal(x.calls.length,2);
 for(const {url,options} of x.calls){
  assert.equal(options.method,'GET');assert.equal(options.headers.branchName,'chatgpt_development');
  assert.equal(options.credentials,'same-origin');assert.equal(options.redirect,'error');
  assert.equal(new URL(url).origin,origin);assert.equal(Object.hasOwn(options,'body'),false);
  if(new URL(url).pathname.startsWith('/api/v1/pages/'))assert.equal(new URL(url).searchParams.get('migrateDsl'),'false');
 }
 assert.doesNotMatch(x.logs.join(''),/fixture-private|software-collection-id|query_results|dsl|userProfile|publishedActions|example\.invalid|[ab]{24}/);
}
{const x=fixture();const r=await x.run();assert.equal(r.schedules_match,false);assert.equal(r.editor.has_navigation_initializer,true);assert.equal(r.published_view.has_navigation_initializer,false);assert.equal(r.action_execution_requests_since_page_fetch,1);assert.equal(r.metadata_source,'page_id_route');safeReads(x);}
{const x=fixture({published:true});assert.equal((await x.run()).schedules_match,true);safeReads(x);}
{const x=fixture({cycle:true});assert.equal((await x.run()).editor.cyclic_dependency_reported,true);safeReads(x);}
{const x=fixture({http:403});const r=await x.run();assert.equal(r.editor.available,false);assert.equal(r.schedules_match,null);assert.equal(r.editor.http_status,403);safeReads(x);}
{const x=fixture({staticUrl:true});const r=await x.run();assert.equal(r.metadata_source,'static_route_bootstrap');assert.equal(r.schedules_match,false);assert.equal(r.startup_request_observed,true);assert.equal(r.action_execution_requests_since_page_fetch,1);safeReads(x);const u=new URL(x.calls[0].url);assert.equal(u.searchParams.get('applicationId'),'synthetic');assert.equal(u.searchParams.get('defaultPageId'),'directory');assert.equal(u.searchParams.get('branchName'),'chatgpt_development');}
for(const staticUrl of [false,true]){const x=fixture({observed:false,staticUrl});const r=await x.run();assert.equal(r.editor.available,true);assert.equal(r.startup_request_observed,false);assert.equal(r.action_execution_requests_since_page_fetch,null);safeReads(x);}
for(const path of ['/app/synthetic/directory-'+uuid+'/edit','/app/custom-'+uuid,'/applications/'+id+'/pages/'+uuid+'/edit']){const x=fixture({observed:false,path,pageId:uuid});const r=await x.run();assert.equal(r.editor.available,true);assert.equal(r.metadata_source,'page_id_route');assert.equal(r.observed_mode,path.endsWith('/edit')?'editor':'published_view');safeReads(x);}
for(const options of [{http:403},{malformed:true},{networkError:true},{pageId:'invalid'}]){const x=fixture({...options,staticUrl:true,observed:false});const r=await x.run();assert.equal(r.editor.available,false);assert.equal(x.calls.length,1);assert.doesNotMatch(x.logs.join(''),/fixture-private|invalid/);}
{const x=fixture({observed:false,networkError:true});const r=await x.run();assert.equal(r.editor.reason,'metadata_read_failed');assert.doesNotMatch(x.logs.join(''),/fixture-private/);}
{const x=fixture({path:'/unrecognized',observed:false});const r=await x.run();assert.equal(r.metadata_source,'unresolved');assert.equal(r.editor.reason,'page_identity_unavailable');assert.equal(x.calls.length,0);}
{const x=fixture({branch:'master'});await assert.rejects(x.run(),/chatgpt_development/);assert.equal(x.calls.length,0);}
console.log('PASS startup inspector v2: static bootstrap, ID/UUID/legacy routes, absent timing history, stale/foreign requests, branch/GET/redirect restrictions, drift/cycle/HTTP/network failures and private-field omission');
