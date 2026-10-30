import fs from 'node:fs/promises';
import {browserTarget} from './safety.mjs';
import {connection,check} from './database.mjs';
export async function selectors() {
  if(process.env.E2E_SELECTORS_REVIEWED!=='1')throw new Error('Review semantic locators against the real isolated Appsmith first');
  return JSON.parse(await fs.readFile(process.env.E2E_SELECTORS_FILE,'utf8'));
}
export function locate(page,descriptor) {
  if(descriptor.label)return page.getByLabel(descriptor.label,{exact:true});
  if(descriptor.role && descriptor.name)return page.getByRole(descriptor.role,{name:descriptor.name,exact:true});
  throw new Error('Only reviewed semantic role/name or label locators accepted');
}
export async function isolate(context) {
  const {origin}=browserTarget();
  await context.route('**/*',route=>{
    const url=new URL(route.request().url());
    return url.origin===origin ? route.continue() : route.abort('blockedbyclient');
  });
  await context.routeWebSocket('**/*',ws=>{
    const url=new URL(ws.url());
    const same=url.hostname===new URL(origin).hostname && ['ws:','wss:'].includes(url.protocol);
    if(same)ws.connectToServer();else ws.close({code:1008,reason:'External integration blocked'});
  });
}
export async function query(sql,params=[]) {
  await check();const {db}=await connection();try{return (await db.query(sql,params)).rows;}finally{await db.end();}
}
