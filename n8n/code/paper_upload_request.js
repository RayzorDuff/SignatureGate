// Authenticated webhook only. Normalize a single bounded document before any database/storage write.
const storage=String($env.NOCODB_BASE_URL || '').trim();
if(!/^https?:\/\/[^/?#@\s]+(?:\/[^?#]*)?$/.test(storage))throw Error('A reviewed NOCODB_BASE_URL is required');
const body=$json.body ?? $json;
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const actor=String(body.actor_email || '').trim().toLowerCase();
if(!actor || actor.length>320 || !uuid.test(body.request_id || '') || !uuid.test(body.member_id || '') || !uuid.test(body.practitioner_person_id || ''))throw Error('Account, request and assigned Participant/practitioner identifiers required');
if(body.agreement_template_id && !uuid.test(body.agreement_template_id))throw Error('Invalid template identifier');
if(!Array.isArray(body.files)||body.files.length!==1)throw Error('Select exactly one PDF, PNG or JPEG document');
const file=body.files[0],name=String(file.name || ''),mimeType=String(file.type || file.mimeType || '');
let data=file.data || file.base64 || file.content;
if(!name || name.length>160 || /[\x00-\x1f\x7f/\\]/.test(name) || typeof data!=='string')throw Error('Document filename and base64 content required');
if(data.startsWith('data:')){
 const match=/^data:([^;,]+);base64,([A-Za-z0-9+/]*={0,2})$/.exec(data);
 if(!match || match[1]!==mimeType)throw Error('Document data URL type mismatch');data=match[2];
}
if(data.length<12 || data.length>6990508 || data.length%4 || !/^[A-Za-z0-9+/]+={0,2}$/.test(data))throw Error('Invalid or oversized document content');
const bytes=Buffer.from(data,'base64');
if(bytes.length>5242880 || bytes.toString('base64')!==data)throw Error('Invalid or oversized document content');
const hex=bytes.subarray(0,8).toString('hex');
if(!((mimeType==='application/pdf' && hex.startsWith('255044462d')) || (mimeType==='image/png' && hex==='89504e470d0a1a0a') || (mimeType==='image/jpeg' && hex.startsWith('ffd8ff'))))throw Error('PDF, PNG or JPEG content must match its type');
return [{json:{actor_email:actor,request_id:body.request_id,payload:{member_id:body.member_id,practitioner_person_id:body.practitioner_person_id,agreement_template_id:body.agreement_template_id || '',files:[{name,mimeType,data}]}}}];
