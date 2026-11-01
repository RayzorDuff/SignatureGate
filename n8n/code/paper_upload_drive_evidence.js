// Only the authenticated Drive upload node supplies this reference; no sharing operation is performed.
const input=$input.all(),source=$('Code - Validate Paper Request').first().json;
if(source.storage_provider!=='google_drive' || input.length!==1)throw Error('Drive response does not match the reserved upload');
const stored=input[0].json,folder=String($env.SIGNATUREGATE_PAPER_DRIVE_FOLDER_ID || '').trim();
if(typeof stored.id!=='string'||!/^[A-Za-z0-9_-]{10,200}$/.test(stored.id)||stored.trashed===true || !Array.isArray(stored.parents)||!stored.parents.includes(folder))throw Error('Drive did not confirm the configured parent folder');
const file=source.payload.files[0];
if(stored.mimeType!==file.mimeType || Number(stored.size)!==Buffer.from(file.data,'base64').length)throw Error('Stored Drive file metadata differs from the uploaded document');
return [{json:{actor_email:source.actor_email,request_id:source.request_id,evidence:[{storage_provider:'google_drive',drive_file_id:stored.id,web_url:'https://drive.google.com/file/d/'+stored.id+'/view',title:file.name,mimetype:file.mimeType,size:Number(stored.size)}]}}];
