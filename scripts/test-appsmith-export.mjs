#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'signaturegate-export-'));
const output = path.join(root, 'output.json');
const source = path.join(root, 'source');
const script = path.resolve(new URL('./appsmith-export.mjs', import.meta.url).pathname);
function write(file, data) {
  const target = path.join(source, file);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, JSON.stringify(data));
}
function run() {
  return spawnSync(process.execPath, [script, '--source', source, '--output', output], { encoding: 'utf8' });
}
try {
  write('application.json', { pages: [{ id: 'Test', isDefault: true }] });
  write('metadata.json', { artifactJsonType: 'APPLICATION' });
  write('pages/Test/Test.json', { unpublishedPage: { name: 'Test', layouts: [{ dsl: { widgetName: 'MainContainer', widgetId: '0' } }] } });
  write('pages/Test/widgets/form/form.json', {
    widgetName: 'Form', widgetId: 'form', parentId: '0', topRow: 1,
    children: [{ widgetName: 'Canvas', widgetId: 'canvas', parentId: 'form' }]
  });
  write('pages/Test/widgets/form/input.json', { widgetName: 'Input', widgetId: 'input', parentId: 'canvas', label: 'Retain me', topRow: 2 });
  write('datasources/pg.json', { name: 'pg', pluginId: 'postgres-plugin' });
  write('datasources/nested/api.json', { name: 'api', pluginId: 'restapi-plugin' });
  const library = { name: 'jspdf', accessor: ['jspdf'], url: 'https://example.invalid/jspdf.js', uidString: 'jspdf-test' };
  write('jslibs/jspdf.json', library);
  write('pages/Test/queries/q/metadata.json', { id: 'Test_q', pluginType: 'DB', unpublishedAction: { name: 'q', actionConfiguration: { body: 'stale' }, runBehaviour: 'MANUAL' } });
  fs.writeFileSync(path.join(source, 'pages/Test/queries/q/q.txt'), 'SELECT 1;\n');
  let result = run();
  assert.equal(result.status, 0, result.stderr);
  const exported = JSON.parse(fs.readFileSync(output, 'utf8'));
  assert.equal(exported.datasourceList.length, 2);
  assert.deepEqual(exported.customJSLibList, [library]);
  assert.equal(exported.actionList[0].unpublishedAction.actionConfiguration.body, 'SELECT 1;\n');
  const form = exported.pageList[0].unpublishedPage.layouts[0].dsl.children[0];
  assert.equal(form.children[0].widgetName, 'Canvas');
  assert.equal(form.children[0].children[0].label, 'Retain me');
  const validation = spawnSync('python3', [path.join(path.dirname(script), 'validate_appsmith_source_export.py'), '--source', source, '--export', output], { encoding: 'utf8' });
  assert.equal(validation.status, 0, validation.stderr + validation.stdout);
  exported.customJSLibList = [];
  fs.writeFileSync(output, JSON.stringify(exported));
  const droppedLibrary = spawnSync('python3', [path.join(path.dirname(script), 'validate_appsmith_source_export.py'), '--source', source, '--export', output], { encoding: 'utf8' });
  assert.notEqual(droppedLibrary.status, 0);
  assert.match(droppedLibrary.stderr, /library descriptors/);
  write('customJSLibs/jspdf.json', library);
  result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(fs.readFileSync(output, 'utf8')).customJSLibList.length, 1);
  write('customJSLibs/jspdf.json', { ...library, url: 'https://example.invalid/conflict.js' });
  result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Conflicting JS library descriptor/);
  fs.rmSync(path.join(source, 'customJSLibs'), { recursive: true });
  write('pages/Test/widgets/orphan.json', { widgetName: 'Lost', widgetId: 'lost', parentId: 'missing' });
  result = run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Unattached widgets/);
  console.log('Appsmith export preservation and rejection checks passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
