// Accept only a real storage response. No caller-provided attachment URL is accepted.
const input=$input.all(),source=$('Code - Validate Paper Request').first().json;
const files=input.flatMap(item=>{const raw=item.json?.body ?? item.json;return Array.isArray(raw)?raw:Array.isArray(raw?.files)?raw.files:[raw];});
if(files.length!==1)throw Error('Storage did not return exactly one attachment; inspect this request before retrying');
const path=files[0]?.path;
if(typeof path!=='string'||!/^[A-Za-z0-9_-][A-Za-z0-9_./-]{1,1023}$/.test(path)||path.includes('..')||path.includes('//'))throw Error('Storage did not return a safe relative attachment path');
const file=source.payload.files[0];
return [{json:{actor_email:source.actor_email,request_id:source.request_id,evidence:[{path,title:file.name,mimetype:file.mimeType,size:Buffer.from(file.data,'base64').length}]}}];
