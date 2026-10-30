import {Client} from 'pg';
import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {databaseTarget} from './safety.mjs';

export async function connection(env=process.env) {
  const target=databaseTarget(env);const db=new Client({connectionString:target.connectionString});await db.connect();
  try {
    const row=(await db.query('SELECT current_database() db,current_user actor,current_setting(\'server_version_num\')::int version')).rows[0];
    if (row.db!=='signaturegate_e2e' || row.actor!=='signaturegate_e2e' || row.version<160000 || row.version>=170000) throw new Error('Actual E2E database identity/version mismatch');
    return {db,target};
  } catch(error) {await db.end();throw error;}
}
export async function check(env=process.env) {
  const {db,target}=await connection(env);
  try {
    const marker=(await db.query('SELECT marker FROM e2e_control.instance WHERE singleton=true')).rows[0];
    if (marker?.marker!==target.marker) throw new Error('E2E instance marker mismatch');
    return true;
  } finally {await db.end();}
}
export async function reset(env=process.env) {
  if (env.E2E_ALLOW_RESET!=='1') throw new Error('Explicit dedicated E2E reset opt-in required');
  const {db,target}=await connection(env);
  try {
    await db.query('BEGIN');await db.query('SELECT pg_advisory_xact_lock(270027)');
    const exists=(await db.query("SELECT to_regclass('e2e_control.instance') name")).rows[0].name;
    if (exists) {
      const marker=(await db.query('SELECT marker FROM e2e_control.instance WHERE singleton=true FOR UPDATE')).rows[0];
      if (marker?.marker!==target.marker) throw new Error('E2E instance marker mismatch');
    } else {
      const count=(await db.query("SELECT count(*)::int n FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','v','m','p')")).rows[0].n;
      if (count!==0) throw new Error('Unmarked nonempty database cannot be reset');
      await db.query('CREATE SCHEMA e2e_control; CREATE TABLE e2e_control.instance(singleton boolean PRIMARY KEY CHECK(singleton),marker text NOT NULL)');
      await db.query('INSERT INTO e2e_control.instance VALUES(true,$1)',[target.marker]);
    }
    await db.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public');
    const schema=await fs.readFile(new URL('../db/schema.sql',import.meta.url),'utf8');
    // pg_dump restrict/unrestrict are psql controls, not executable SQL.
    if (schema.split('\n').some(line=>line.startsWith('\\') && !/^\\(?:un)?restrict\b/.test(line))) throw new Error('Review unexpected schema meta-command');
    await db.query(schema.split('\n').filter(line=>!line.startsWith('\\') && !['BEGIN;','COMMIT;'].includes(line.trim())).join('\n'));
    await db.query(await fs.readFile(new URL('./seed.sql',import.meta.url),'utf8'));
    await db.query('COMMIT');
  } catch(error) {await db.query('ROLLBACK');throw error;} finally {await db.end();}
}
if (process.argv[1]===fileURLToPath(import.meta.url)) {
  try {
    if (process.argv[2]==='reset') await reset();else if(process.argv[2]==='check')await check();else throw new Error('Use reset or check');
    console.log('Dedicated synthetic E2E database ready');
  } catch(error) {console.error('E2E database command refused/failed; inspect locally without publishing credentials');process.exitCode=1;}
}
