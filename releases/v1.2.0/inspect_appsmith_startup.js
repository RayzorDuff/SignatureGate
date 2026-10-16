// Paste once into Chrome DevTools Console on the development app after a reload.
// GETs only: Appsmith configuration/bootstrap reads; no action/query is executed.
// Only known software names, counts and flags are printed, never raw responses.
(async function inspectSignatureGateStartup() {
  const current=new URL(location.href);
  const branch=current.searchParams.get('branch') || current.searchParams.get('branchName');
  if(branch!=='chatgpt_development') throw new Error('Open the chatgpt_development app before running this diagnostic.');
  const entries=performance.getEntriesByType('resource');
  const idPattern='(?:[a-f0-9]{24}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})';
  const validId=new RegExp('^'+idPattern+'$','i');
  const legacy=current.pathname.match(new RegExp('^/applications/'+idPattern+'/pages/('+idPattern+')(?:/|$)','i'));
  const slug=current.pathname.match(new RegExp('^/app/(?:[^/]+/)?[^/]+-('+idPattern+')(?:/|$)','i'));
  const routeId=(legacy || slug || [])[1];
  const staticRoute=current.pathname.match(/^\/app\/([^/]+)\/([^/]+)(?:\/edit(?:\/.*)?)?\/?$/);
  const requests=entries.map(entry=>({entry,url:new URL(entry.name,current.origin)}))
    .filter(item=>item.url.origin===current.origin);
  const pageRequests=requests.filter(item=>new RegExp('^/api/v1/pages/('+idPattern+')(/view)?/?$','i').test(item.url.pathname))
    .filter(item=>!routeId || item.url.pathname.split('/')[4].toLowerCase()===routeId.toLowerCase())
    .sort((a,b)=>b.entry.startTime-a.entry.startTime);
  const combinedRequests=requests.filter(item=>/^\/api\/v1\/consolidated-api\/(view|edit)$/.test(item.url.pathname))
    .filter(item=>routeId ? item.url.searchParams.get('defaultPageId')===routeId : staticRoute && item.url.searchParams.get('applicationId')===staticRoute[1] && item.url.searchParams.get('defaultPageId')===staticRoute[2])
    .sort((a,b)=>b.entry.startTime-a.entry.startTime);
  const observed=(!routeId && staticRoute ? combinedRequests : [pageRequests[0],combinedRequests[0]].filter(Boolean).sort((a,b)=>b.entry.startTime-a.entry.startTime))[0];
  const names=new Set(['Directory','Individual Profile','Company Profile','Member Functions','Facilitator Functions','Sacrament Release','Contributor Functions','Cash Deposits','Reports','Agreement Templates','Audit Log','Terminology Administration','Intake','Members – Intake','Agreements - Queue','Events - Create','Events - Check In','Unauthorized']);
  const controllers=/^(navigationLabels|directoryFlows|IndividualProfileFlows|CompanyProfileFlows|memberProfile|facilitatorFlows|releaseFlows|cashDonationFlows|cashDepositFlows|reports|agreementTemplateFlows|auditLogFlows|terminologyAdminFlows|intakeFlows|memberFlows)\.[A-Za-z_$][\w$]*$/;
  async function get(path,params={}) {
    const url=new URL(path,current.origin);
    for(const [key,value] of Object.entries(params))url.searchParams.set(key,value);
    url.searchParams.set('v',String(Date.now()));
    try {
      const response=await fetch(url.href,{method:'GET',credentials:'same-origin',headers:{branchName:branch},cache:'no-store',redirect:'error'});
      if(!response.ok)return {http_status:response.status,available:false};
      return {http_status:response.status,available:true,data:(await response.json()).data};
    } catch(error) {return {available:false,reason:'metadata_read_failed'};}
  }
  function project(kind,result,page=result.data) {
    if(!result.available)return {kind,...result};
    if(!page || !names.has(page.name))return {kind,http_status:result.http_status,available:false,reason:'unrecognized_page_metadata'};
    const layouts=Array.isArray(page.layouts)?page.layouts:[page];
    const schedule=layouts.flatMap(layout=>Array.isArray(layout.layoutOnLoadActions)?layout.layoutOnLoadActions.flat():[]);
    const errors=[...(Array.isArray(page.layoutOnLoadActionErrors)?page.layoutOnLoadActionErrors:[]),...layouts.flatMap(layout=>Array.isArray(layout.layoutOnLoadActionErrors)?layout.layoutOnLoadActionErrors:[])];
    const registered=schedule.map(action=>action.name).filter(name=>typeof name==='string'&&controllers.test(name)).sort();
    return {kind,http_status:result.http_status,available:true,page:page.name,
      on_load_action_count:schedule.length,on_load_controller_names:registered,
      has_navigation_initializer:registered.includes('navigationLabels.initialize'),
      on_load_error_count:errors.length,cyclic_dependency_reported:/cyclic|cycle/i.test(JSON.stringify(errors))};
  }
  let editor,published,source;
  if(!routeId && staticRoute) {
    // Appsmith 2.4.2 resolves static URLs through its normal view bootstrap.
    // Its broader response stays private; only the page schedule is projected.
    source='static_route_bootstrap';
    const result=await get('/api/v1/consolidated-api/view',{applicationId:staticRoute[1],defaultPageId:staticRoute[2],branchName:branch});
    const page=result.data?.pageWithMigratedDsl?.data;
    published=project('published_view',result,page);
    const pageId=page?.id;
    editor=published.available && typeof pageId==='string' && validId.test(pageId)
      ? project('editor',await get('/api/v1/pages/'+pageId,{migrateDsl:'false'}))
      : {kind:'editor',available:false,reason:'page_identity_unavailable'};
  } else {
    source=routeId?'page_id_route':'observed_page_request';
    const base=routeId?'/api/v1/pages/'+routeId:pageRequests[0]?.url.pathname.replace(/\/view\/?$/,'');
    if(base) {
      const results=await Promise.all([get(base,{migrateDsl:'false'}),get(base+'/view',{migrateDsl:'false'})]);
      editor=project('editor',results[0]);published=project('published_view',results[1]);
    } else {
      source='unresolved';
      editor={kind:'editor',available:false,reason:'page_identity_unavailable'};
      published={kind:'published_view',available:false,reason:'page_identity_unavailable'};
    }
  }
  const report={inspection:'signaturegate_startup_schedule',diagnostic_version:2,branch,metadata_source:source,
    observed_mode:/\/edit(?:\/|$)/.test(current.pathname)?'editor':'published_view',
    startup_request_observed:Boolean(observed),
    action_execution_requests_since_page_fetch:observed?requests.filter(item=>item.url.pathname==='/api/v1/actions/execute'&&item.entry.startTime>=observed.entry.startTime).length:null,
    editor,published_view:published,
    schedules_match:editor.available&&published.available?JSON.stringify([editor.page,editor.on_load_action_count,editor.on_load_controller_names,editor.on_load_error_count,editor.cyclic_dependency_reported])===JSON.stringify([published.page,published.on_load_action_count,published.on_load_controller_names,published.on_load_error_count,published.cyclic_dependency_reported]):null};
  console.log(JSON.stringify(report,null,2));
  return report;
})()
