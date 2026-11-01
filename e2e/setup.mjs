import {chromium} from '@playwright/test';
import fs from 'node:fs/promises';
import {browserTarget} from './safety.mjs';
import {check} from './database.mjs';
import {selectors,locate,isolate,query} from './helpers.mjs';
export default async function setup() {
  if(process.env.E2E_POST_RELEASE_ACK!=='post-v1.2.0')throw new Error('This harness is opt-in post-v1.2.0 work, not a release gate');
  const target=browserTarget();await check();const s=await selectors();
  if(!process.env.E2E_REVIEWER_PASSWORD)throw new Error('Purpose-built test account password required');
  if((await query("SELECT count(*)::int n FROM donations WHERE notes='SignatureGate E2E cash operation'"))[0].n!==0)
    throw new Error('Reset the dedicated fixture DB before another browser run');
  await fs.mkdir('.auth',{recursive:true,mode:0o700});await fs.mkdir('artifacts',{recursive:true,mode:0o700});
  const browser=await chromium.launch();const context=await browser.newContext();
  try {
    await isolate(context);const page=await context.newPage();await page.goto(target.origin+'/user/login');
    await locate(page,s.loginEmail).fill('reviewer@example.invalid');
    await locate(page,s.loginPassword).fill(process.env.E2E_REVIEWER_PASSWORD);
    await locate(page,s.loginSubmit).click();
    await page.goto(target.origin+target.app);await locate(page,s.applicationReady).waitFor({state:'visible'});
    await context.storageState({path:'.auth/reviewer.json'});
  } finally {await context.close();await browser.close();}
}
