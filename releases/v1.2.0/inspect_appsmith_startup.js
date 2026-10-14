// Paste into Chrome DevTools Console on the SignatureGate development app after a reload.
// Two same-origin GETs read page configuration only. No action/query is executed.
// The output projects startup names/counts/flags and omits DSL, bodies and record data.
(async function inspectSignatureGateStartup() {
  const current=new URL(location.href);
  const branch=current.searchParams.get('branch') || current.searchParams.get('branchName');
  if(branch!=='chatgpt_development') throw new Error('Open the chatgpt_development app before running this diagnostic.');
  const entries=performance.getEntriesByType('resource');
  const pages=entries.map(entry=>({entry,url:new URL(entry.name,current.origin)}))
    .filter(item=>item.url.origin===current.origin && /^\/api\/v1\/pages\/([a-f0-9]{24}|[a-f0-9-]{36})(\/view)?$/i.test(item.url.pathname))
    .sort((a,b)=>b.entry.startTime-a.entry.startTime);
  if(!pages.length) throw new Error('No page metadata request was found. Reload Directory, then run this diagnostic before clicking Refresh.');
  const observed=pages[0];
  const base=observed.url.pathname.replace(/\/view$/,'');
  const names=new Set(['Directory','Individual Profile','Company Profile','Member Functions','Facilitator Functions','Sacrament Release','Contributor Functions','Cash Deposits','Reports','Agreement Templates','Audit Log','Terminology Administration','Intake','Members – Intake','Agreements - Queue','Events - Create','Events - Check In','Unauthorized']);
  const controllers=/^(navigationLabels|directoryFlows|IndividualProfileFlows|CompanyProfileFlows|memberProfile|facilitatorFlows|releaseFlows|cashDonationFlows|cashDepositFlows|reports|agreementTemplateFlows|auditLogFlows|terminologyAdminFlows|intakeFlows|memberFlows)\.[A-Za-z_$][\w$]*$/;
  async function read(kind,path) {
    const url=new URL(path,current.origin);
    url.searchParams.set('v',String(Date.now()));
    if(kind==='editor')url.searchParams.set('migrateDsl','false');
    try {
      const response=await fetch(url.href,{method:'GET',credentials:'same-origin',headers:{branchName:branch},cache:'no-store'});
      if(!response.ok)return {kind,http_status:response.status,available:false};
      const envelope=await response.json(),page=envelope.data;
      if(!page || !names.has(page.name))return {kind,http_status:response.status,available:false,reason:'unrecognized_page_metadata'};
      const layouts=Array.isArray(page.layouts)?page.layouts:[page];
      const schedule=layouts.flatMap(layout=>Array.isArray(layout.layoutOnLoadActions)?layout.layoutOnLoadActions.flat():[]);
      const errors=[...(Array.isArray(page.layoutOnLoadActionErrors)?page.layoutOnLoadActionErrors:[]),...layouts.flatMap(layout=>Array.isArray(layout.layoutOnLoadActionErrors)?layout.layoutOnLoadActionErrors:[])];
      const registered=schedule.map(action=>action.name).filter(name=>typeof name==='string'&&controllers.test(name)).sort();
      return {kind,http_status:response.status,available:true,page:page.name,
        on_load_action_count:schedule.length,on_load_controller_names:registered,
        has_navigation_initializer:registered.includes('navigationLabels.initialize'),
        on_load_error_count:errors.length,cyclic_dependency_reported:/cyclic|cycle/i.test(JSON.stringify(errors))};
    } catch(error) {return {kind,available:false,reason:'metadata_read_failed'};}
  }
  const [editor,published]=await Promise.all([read('editor',base),read('published_view',base+'/view')]);
  const report={inspection:'signaturegate_startup_schedule',branch,
    observed_mode:observed.url.pathname.endsWith('/view')?'published_view':'editor',
    action_execution_requests_since_page_fetch:entries.filter(entry=>{
      const url=new URL(entry.name,current.origin);
      return url.origin===current.origin&&url.pathname==='/api/v1/actions/execute'&&entry.startTime>=observed.entry.startTime;
    }).length,
    editor,published_view:published,
    schedules_match:editor.available&&published.available?JSON.stringify([editor.on_load_action_count,editor.on_load_controller_names,editor.on_load_error_count,editor.cyclic_dependency_reported])===JSON.stringify([published.on_load_action_count,published.on_load_controller_names,published.on_load_error_count,published.cyclic_dependency_reported]):null};
  console.log(JSON.stringify(report,null,2));
  return report;
})()
