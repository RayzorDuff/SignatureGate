// Run once in Chrome Console on Directory, branch chatgpt_development.
// CHANGES TWO DEVELOPMENT FUNCTION SETTINGS through Appsmith's native API.
// No SQL/action execution, deployment, application source body or role change.
(async function rebuildSignatureGateDirectoryStartup() {
  const branch='chatgpt_development',current=new URL(location.href);
  const report={operation:'signaturegate_directory_startup_rebuild',branch,status:'stopped',stage:'preflight',attempted_functions:[],updated_functions:[]};
  const expected=[['navigationLabels','initialize'],['directoryFlows','load']];
  const validId=/^(?:[a-f0-9]{24}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$/i;
  function fail(reason){throw new Error(reason);}
  async function request(path,params={},method='GET') {
    const url=new URL(path,current.origin);
    for(const [key,value] of Object.entries(params))url.searchParams.set(key,value);
    url.searchParams.set('v',String(Date.now()));
    const response=await fetch(url.href,{method,credentials:'same-origin',headers:{branchName:branch,'X-Requested-By':'Appsmith'},cache:'no-store',redirect:'error'});
    if(!response.ok)fail('appsmith_http_'+response.status);
    const envelope=await response.json();
    if(envelope.responseMeta?.success===false || !envelope.data)fail('appsmith_response_unavailable');
    return envelope.data;
  }
  function summarize(page) {
    const layouts=Array.isArray(page.layouts)?page.layouts:[];
    const schedule=layouts.flatMap(l=>Array.isArray(l.layoutOnLoadActions)?l.layoutOnLoadActions.flat():[]);
    const errors=[...(page.layoutOnLoadActionErrors||[]),...layouts.flatMap(l=>l.layoutOnLoadActionErrors||[])];
    return {action_count:schedule.length,navigation_registered:schedule.some(a=>a.name==='navigationLabels.initialize'),directory_registered:schedule.some(a=>a.name==='directoryFlows.load'),error_count:errors.length};
  }
  try {
    if((current.searchParams.get('branch')||current.searchParams.get('branchName'))!==branch)fail('development_branch_required');
    const parts=current.pathname.split('/').filter(Boolean);
    let pageId;
    if(parts[0]==='app' && parts.length>=2) {
      // Static routes have no ID; ID routes use a trailing Mongo ID or UUID.
      const segment=parts.length===2?parts[1]:parts[2];
      const id=segment.match(/-([a-f0-9]{24}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$/i)?.[1];
      if(id)pageId=id;
      else if(parts.length===3 || (parts[3]==='edit' && parts.length===4)) {
        const bundle=await request('/api/v1/consolidated-api/view',{applicationId:parts[1],defaultPageId:parts[2],branchName:branch});
        const page=bundle.pageWithMigratedDsl?.data;
        if(page?.name!=='Directory')fail('directory_page_required');
        pageId=page.id;
      }
    } else if(parts[0]==='applications' && parts[2]==='pages')pageId=parts[3];
    if(!validId.test(pageId||''))fail('page_identity_unavailable');
    report.stage='page_read';
    const page=await request('/api/v1/pages/'+pageId,{migrateDsl:'false'});
    if(page.name!=='Directory' || page.id!==pageId || !validId.test(page.applicationId||''))fail('directory_identity_mismatch');
    report.before=summarize(page);
    report.stage='function_read';
    const collections=await request('/api/v1/collections/actions',{pageId});
    if(!Array.isArray(collections))fail('collections_unavailable');
    // Validate the entire allowlist before the first write. Never create functions.
    const targets=expected.map(([owner,name])=>{
      const matches=collections.filter(c=>c.name===owner && c.pageId===pageId && c.applicationId===page.applicationId && c.pluginType==='JS');
      if(matches.length!==1)fail('expected_collection_missing_or_ambiguous');
      const collection=matches[0];
      if(!validId.test(collection.id||'') || !Array.isArray(collection.actions))fail('collection_identity_unavailable');
      const functions=collection.actions.filter(a=>a.name===name && a.collectionId===collection.id && a.pageId===pageId && a.pluginType==='JS');
      if(functions.length!==1 || !validId.test(functions[0].id||''))fail('expected_function_missing_or_ambiguous');
      const action=functions[0];
      if(action.fullyQualifiedName && action.fullyQualifiedName!==owner+'.'+name)fail('function_identity_mismatch');
      return {id:action.id,name:owner+'.'+name,before_mode:['MANUAL','ON_PAGE_LOAD','AUTOMATIC'].includes(action.runBehaviour)?action.runBehaviour:'unrecognized_or_absent',before_user_set_on_load:action.userSetOnLoad===true};
    });
    if(new Set(targets.map(a=>a.id)).size!==expected.length)fail('duplicate_function_identity');
    report.declarations=targets.map(({id,...safe})=>safe);
    report.stage='registration';
    for(const target of targets) {
      report.attempted_functions.push(target.name);
      // Even an unchanged mode rebuilds the layout in Appsmith 2.4.2.
      const saved=await request('/api/v1/actions/runBehaviour/'+target.id,{behaviour:'ON_PAGE_LOAD'},'PUT');
      if(saved.id!==target.id || saved.pageId!==pageId || saved.runBehaviour!=='ON_PAGE_LOAD' || saved.userSetOnLoad!==true)fail('saved_registration_mismatch');
      report.updated_functions.push(target.name);
    }
    report.stage='verification';
    const after=await request('/api/v1/pages/'+pageId,{migrateDsl:'false'});
    if(after.name!=='Directory' || after.id!==pageId)fail('verification_identity_mismatch');
    report.after=summarize(after);
    report.status=report.after.navigation_registered && report.after.directory_registered && report.after.error_count===0?'editor_schedule_rebuilt':'editor_schedule_still_blocked';
  } catch(error) {
    // Only fixed software reasons; never log raw platform errors/responses.
    const allowed=/^(development_branch_required|directory_page_required|page_identity_unavailable|directory_identity_mismatch|collections_unavailable|expected_collection_missing_or_ambiguous|collection_identity_unavailable|expected_function_missing_or_ambiguous|function_identity_mismatch|duplicate_function_identity|saved_registration_mismatch|verification_identity_mismatch|appsmith_response_unavailable|appsmith_http_\d{3})$/;
    report.reason=allowed.test(error?.message||'')?error.message:'request_or_metadata_failed';
  }
  console.log(JSON.stringify(report,null,2));
  return report;
})()
