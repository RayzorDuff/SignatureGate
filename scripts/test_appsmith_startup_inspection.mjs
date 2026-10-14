import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const source=fs.readFileSync(new URL('../releases/v1.2.0/inspect_appsmith_startup.js',import.meta.url),'utf8');
const origin='https://synthetic-appsmith.example.invalid',id='a'.repeat(24);
function fixture({branch='chatgpt_development',editor=true,published=false,cycle=false,http=200,observed=true}={}) {
 const calls=[],logs=[];
 const c={URL,Date,location:{href:origin+'/app/synthetic/directory?branch='+branch},performance:{getEntriesByType:()=>observed?[{name:origin+'/api/v1/pages/'+id+'/view',startTime:10},{name:origin+'/api/v1/actions/execute',startTime:20},{name:'https://other.example.invalid/api/v1/pages/'+id+'/view',startTime:30}]:[]},console:{log:s=>logs.push(s)},fetch:async(url,options)=>{
  calls.push({url,options});const publishedRoute=new URL(url).pathname.endsWith('/view');
  const enabled=publishedRoute?published:editor;
  return {ok:http===200,status:http,json:async()=>({data:{name:'Directory',private_contact:'fixture-private-contact',layouts:[{dsl:{private_record:'fixture-private-record'},layoutOnLoadActions:enabled?[[{name:'navigationLabels.initialize',collectionId:'software-collection-id'},{name:'directoryFlows.load'}]]:[],layoutOnLoadActionErrors:cycle?[{message:'Cyclic dependency; fixture-private-error-text'}]:[]}],query_results:[{amount:'fixture-private-amount'}]}})};
 }};
 return {c,calls,logs,run:()=>vm.runInNewContext(source,c)};
}
{const x=fixture();const result=await x.run();assert.equal(result.schedules_match,false);assert.equal(result.editor.has_navigation_initializer,true);assert.equal(result.published_view.has_navigation_initializer,false);assert.equal(result.action_execution_requests_since_page_fetch,1);assert.equal(x.calls.length,2);for(const call of x.calls){assert.equal(call.options.method,'GET');assert.equal(call.options.headers.branchName,'chatgpt_development');assert.equal(call.options.credentials,'same-origin');assert.equal(new URL(call.url).origin,origin);assert.equal(Object.hasOwn(call.options,'body'),false);}assert.doesNotMatch(x.logs.join(''),/fixture-private|software-collection-id|query_results|dsl/);}
{const x=fixture({published:true});assert.equal((await x.run()).schedules_match,true);}
{const x=fixture({cycle:true});const r=await x.run();assert.equal(r.editor.cyclic_dependency_reported,true);assert.doesNotMatch(x.logs.join(''),/fixture-private-error-text/);}
{const x=fixture({http:403});const r=await x.run();assert.equal(r.editor.available,false);assert.equal(r.schedules_match,null);assert.equal(r.editor.http_status,403);}
for(const options of [{branch:'master'},{observed:false}]){const x=fixture(options);await assert.rejects(x.run());assert.equal(x.calls.length,0);}
console.log('PASS startup metadata inspector: branch/same-origin GET restrictions, editor/view drift, cycle flag, HTTP failure, request count and private-field omission');
