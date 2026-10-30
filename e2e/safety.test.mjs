import test from 'node:test';import assert from 'node:assert/strict';
import {databaseTarget,browserTarget} from './safety.mjs';
const env={E2E_DATABASE_URL:'postgresql://signaturegate_e2e:synthetic@127.0.0.1:55432/signaturegate_e2e',E2E_INSTANCE_TOKEN:'synthetic-private-test-token-xxxxxxxx'};
test('refuse production, generic test, remote host and connection overrides',()=>{
  databaseTarget(env);
  for(const url of ['postgresql://signaturegate_e2e@localhost/signaturegate','postgresql://signaturegate_e2e@localhost/signaturegate_test',
    'postgresql://postgres@localhost/signaturegate_e2e','postgresql://signaturegate_e2e@45.33.107.185/signaturegate_e2e',
    env.E2E_DATABASE_URL+'?hostaddr=45.33.107.185'])assert.throws(()=>databaseTarget({...env,E2E_DATABASE_URL:url}));
});
test('browser requires dedicated clone and test origin',()=>{
  browserTarget({E2E_APPSMITH_URL:'http://127.0.0.1:8081/',E2E_APP_PATH:'/app/signaturegate-e2e/donations-test'});
  for(const origin of ['https://appsmith.danks.store/','https://user:secret@appsmith-test.danks.store/','https://45.33.107.185/'])
    assert.throws(()=>browserTarget({E2E_APPSMITH_URL:origin,E2E_APP_PATH:'/app/signaturegate-e2e/test'}));
  assert.throws(()=>browserTarget({E2E_APPSMITH_URL:'https://appsmith-test.danks.store/',E2E_APP_PATH:'/app/production/test'}));
});

import {schemaSQL} from './schema_sql.mjs';
test('bootstrap strips only reviewed psql and transaction controls',()=>{
 assert.equal(schemaSQL('\\set ON_ERROR_STOP on\nBEGIN;\nSELECT 1;\nCOMMIT;'), 'SELECT 1;');
 assert.throws(()=>schemaSQL('\\connect signaturegate'));
});
