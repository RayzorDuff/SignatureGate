import assert from 'node:assert/strict';
import {reset,connection,check} from './database.mjs';
await reset();await check();
let {db}=await connection();
try {
  const permissions=(await db.query("SELECT application_member_access('practitioner@example.invalid',$1::uuid,false) assigned,application_member_access('practitioner@example.invalid',$2::uuid,false) unrelated",['27000000-0000-4000-8000-000000000003','27000000-0000-4000-8000-000000000004'])).rows[0];
  assert.deepEqual(permissions,{assigned:true,unrelated:false});
  await assert.rejects(db.query("SELECT application_record_cash('practitioner@example.invalid','__anonymous__',true,137,now(),'forbidden')"),/Anonymous cash requires reviewer/);
  const donation=(await db.query("SELECT (application_record_cash('reviewer@example.invalid','__anonymous__',true,137,now(),'Synthetic backend proof')).donation_id id")).rows[0];
  assert.equal((await db.query('SELECT count(*)::int n FROM donations')).rows[0].n,1);
  assert.equal((await db.query("SELECT count(*)::int n FROM audit_log WHERE action='donation.cash.created' AND entity_id=$1",[donation.id])).rows[0].n,1);
} finally {await db.end();}
await assert.rejects(reset({...process.env,E2E_INSTANCE_TOKEN:'different-marker-token-xxxxxxxxxxxxxxxx'}),/marker mismatch/);
await reset();({db}=await connection());
try {assert.equal((await db.query('SELECT count(*)::int n FROM donations')).rows[0].n,0);}finally{await db.end();}
console.log('Native PostgreSQL fixture reset, role denial, durable cash/audit and marker fencing passed');
