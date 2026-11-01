import crypto from 'node:crypto';

export function databaseTarget(env=process.env) {
  const url=new URL(env.E2E_DATABASE_URL || 'invalid:');
  if (!['postgres:','postgresql:'].includes(url.protocol) || !['127.0.0.1','localhost','postgres-e2e'].includes(url.hostname)
      || decodeURIComponent(url.pathname)!=='/signaturegate_e2e' || decodeURIComponent(url.username)!=='signaturegate_e2e'
      || url.search || url.hash) throw new Error('Refusing non-dedicated E2E database target');
  if (!env.E2E_INSTANCE_TOKEN || env.E2E_INSTANCE_TOKEN.length<32) throw new Error('Private E2E instance token required');
  return {connectionString:url.href,marker:crypto.createHash('sha256').update(env.E2E_INSTANCE_TOKEN).digest('hex')};
}
export function browserTarget(env=process.env) {
  const url=new URL(env.E2E_APPSMITH_URL || 'invalid:');
  const local=['127.0.0.1','localhost','appsmith-e2e'].includes(url.hostname);
  if ((!local && !(url.protocol==='https:' && url.hostname==='appsmith-test.danks.store'))
      || !['http:','https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash
      || url.pathname!=='/') throw new Error('Refusing non-test Appsmith origin');
  const app=env.E2E_APP_PATH || '';
  if (!app.startsWith('/app/signaturegate-e2e/') || app.includes('..') || app.includes('?') || app.includes('#'))
    throw new Error('A dedicated SignatureGate E2E application path is required');
  return {origin:url.origin,app};
}
