// Execute the actual n8n Code bodies with synthetic files. No network or real storage.
import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const root=new URL('../',import.meta.url),read=p=>fs.readFileSync(new URL(p,root),'utf8');
const workflow=JSON.parse(read('n8n/workflows/SignatureGate - Paper Agreement Upload.json'));
const node=name=>workflow.nodes.find(n=>n.name===name);
const validate=read('n8n/code/paper_upload_request.js'),evidence=read('n8n/code/paper_upload_evidence.js');
assert.equal(node('Code - Validate Paper Request').parameters.jsCode,validate);assert.equal(node('Code - Stored Paper Evidence').parameters.jsCode,evidence);
assert.equal(node('Webhook - Paper Agreement').parameters.authentication,'headerAuth');
assert.equal(workflow.active,false);assert.equal(workflow.settings.saveDataSuccessExecution,'none');assert.equal(workflow.settings.saveDataErrorExecution,'none');assert.deepEqual(workflow.pinData,{});
for(const n of workflow.nodes)assert.notEqual(n.retryOnFail,true,'storage/commit calls must not replay blindly');
assert.equal(node('PG - Begin Paper Upload').parameters.query,'SELECT public.application_begin_paper_upload($1::text,$2::uuid,$3::jsonb) AS receipt;');
assert.equal(node('PG - Complete Paper Upload').parameters.query,'SELECT public.application_complete_paper_upload($1::text,$2::uuid,$3::jsonb) AS receipt;');
const next=(name,index=0)=>workflow.connections[name].main[index].map(x=>x.node);
assert.deepEqual(next('Webhook - Paper Agreement'),['Code - Validate Paper Request']);assert.deepEqual(next('Code - Validate Paper Request'),['PG - Begin Paper Upload']);assert.deepEqual(next('PG - Begin Paper Upload'),['IF - New Paper Request']);
assert.deepEqual(next('IF - New Paper Request',0),['Code - Paper Binary']);assert.deepEqual(next('IF - New Paper Request',1),['Respond - Paper Receipt']);
const id='10000000-0000-4000-8000-000000000001';
const body={actor_email:'synthetic-paper@example.invalid',request_id:id,member_id:id,practitioner_person_id:id,files:[{name:'synthetic.pdf',type:'application/pdf',data:Buffer.from('%PDF-1.4 synthetic document').toString('base64')}]};
function request(b=body,env={NOCODB_BASE_URL:'https://storage.example.invalid'}){return vm.runInNewContext('(function(){'+validate+'})()',{Buffer,$json:{body:b},$env:env});}
const source=request()[0].json;assert.equal(source.payload.files.length,1);
for(const [mime,bytes] of [['image/png',Buffer.from('89504e470d0a1a0a00000000','hex')],['image/jpeg',Buffer.from('ffd8ff000000000000000000','hex')]]){
 const f={name:'synthetic-image',type:mime,data:bytes.toString('base64')};assert.equal(request({...body,files:[f]})[0].json.payload.files[0].mimeType,mime);
}
const dataUrl={...body.files[0],data:'data:application/pdf;base64,'+body.files[0].data};assert.equal(request({...body,files:[dataUrl]})[0].json.payload.files[0].data,body.files[0].data);
for(const mutation of [{files:[]},{files:[...body.files,...body.files]},{request_id:'bad'},{files:[{...body.files[0],name:'../bad.pdf'}]},{files:[{...body.files[0],type:'text/html'}]},{files:[{...body.files[0],data:'not-base64'}]},{files:[{...body.files[0],data:'A'.repeat(6990512)}]},{files:[{...body.files[0],type:'image/png'}]}])assert.throws(()=>request({...body,...mutation}));
assert.throws(()=>request(body,{}));assert.throws(()=>request(body,{NOCODB_BASE_URL:'https://user:secret@storage.example.invalid'}));
function stored(raw){return vm.runInNewContext('(function(){'+evidence+'})()',{Buffer,$input:{all:()=>[{json:raw}]},$:()=>({first:()=>({json:source})})});}
assert.equal(stored([{path:'nc/uploads/synthetic.pdf'}])[0].json.evidence[0].title,'synthetic.pdf');
for(const raw of [[],[{signedPath:'https://outside.example.invalid/document'}],[{path:'../private'}],[{path:'nc//private'}],[{path:'https://outside.example.invalid/file.pdf'}],[{path:'nc/a.pdf'},{path:'nc/b.pdf'}]])assert.throws(()=>stored(raw));
let prepared=0;
const binary=await vm.runInNewContext('(async function(){'+node('Code - Paper Binary').parameters.jsCode+'}).call(this)',{Buffer,$:()=>({first:()=>({json:source})}),helpers:{prepareBinaryData:async(buffer,name,mime)=>{prepared++;assert.equal(buffer.toString(),'%PDF-1.4 synthetic document');return {data:'synthetic-binary-reference',fileName:name,mimeType:mime};}}});
assert.equal(prepared,1);assert.equal(binary[0].binary.data.fileName,'synthetic.pdf');
console.log('PASS actual n8n paper workflow: header authentication, validation-before-claim/storage, pending/replay branch, prepared binary helper, MIME/magic/base64/size/path rejection, storage-only evidence and disabled execution payload retention; live credentials/storage remain unverified');
