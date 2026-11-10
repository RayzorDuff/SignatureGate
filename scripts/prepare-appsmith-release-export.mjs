#!/usr/bin/env node
// Build the production-bound Appsmith export from a disposable copy of the
// reviewed Appsmith source. Never mutate the development checkout/datasource.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';

const root = path.resolve(import.meta.dirname, '..');
const args = process.argv.slice(2);
function flag(name) {
  const index = args.indexOf('--' + name);
  if (index < 0 || index + 1 >= args.length || args[index + 1].startsWith('--')) {
    throw new Error(`Missing required --${name}`);
  }
  return path.resolve(args[index + 1]);
}
function revision(name, source) {
  const index = args.indexOf('--' + name);
  const expected = index < 0 ? '' : args[index + 1];
  if (!/^[a-f0-9]{40}$/.test(expected || '')) throw new Error(`--${name} requires a full commit SHA`);
  const result = spawnSync('git', ['-C', source, 'rev-parse', 'HEAD'], {encoding: 'utf8'});
  if (result.status !== 0 || result.stdout.trim() !== expected) throw new Error(`--${name} does not match checkout HEAD`);
  const status = spawnSync('git', ['-C', source, 'status', '--porcelain', '--untracked-files=all'], {encoding: 'utf8'});
  if (status.status !== 0 || status.stdout.trim()) throw new Error(`--${name} checkout must be clean, including untracked files`);
  return expected;
}
const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');
function run(command, values) {
  const result = spawnSync(command, values, { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited ${result.status}`);
}
function descriptor(file) {
  const value = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (value.name !== 'signaturegate-postgres' || value.pluginId !== 'postgres-plugin') {
    throw new Error(`Expected native production PostgreSQL descriptor in ${file}`);
  }
  return value;
}

let workspace;
try {
  const source = flag('source');
  const productionSource = flag('production-source');
  const output = flag('output');
  const provenance = flag('provenance');
  if (output === provenance) throw new Error('Export and provenance paths must differ');
  const sourceCommit = revision('source-sha', source);
  const descriptorCommit = revision('production-source-sha', productionSource);
  for (const destination of [output, provenance]) {
    if ([source, productionSource].some(dir => destination === dir || destination.startsWith(dir + path.sep))) {
      throw new Error('Export/provenance must be outside the pinned input checkouts');
    }
  }
  if (!fs.statSync(path.join(source, 'pages')).isDirectory()) {
    throw new Error('Expected Appsmith split source with pages/');
  }
  const productionFile = path.join(productionSource, 'datasources', 'signaturegate-postgres.json');
  const productionDescriptor = descriptor(productionFile);
  const sourceProductionFile = path.join(source, 'datasources', 'signaturegate-postgres.json');
  if (fs.existsSync(sourceProductionFile)) {
    const existing = descriptor(sourceProductionFile);
    if (JSON.stringify(existing) !== JSON.stringify(productionDescriptor)) {
      throw new Error('Source production descriptor differs from approved master descriptor');
    }
  }
  workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'signaturegate-appsmith-release-'));
  const staged = path.join(workspace, 'candidate');
  fs.cpSync(source, staged, { recursive: true, filter: name =>
    !['.git', 'node_modules'].includes(path.relative(source, name).split(path.sep)[0]) });
  fs.copyFileSync(productionFile, path.join(staged, 'datasources', 'signaturegate-postgres.json'));

  const testFile = path.join(staged, 'datasources', 'signaturegate-postgres-test.json');
  if (fs.existsSync(testFile)) {
    run('node', [
      'scripts/appsmith-rebind-datasource.mjs', '--source', staged,
      '--from', 'signaturegate-postgres-test', '--to', 'signaturegate-postgres',
      '--dry-run'
    ]);
    run('node', [
      'scripts/appsmith-rebind-datasource.mjs', '--source', staged,
      '--from', 'signaturegate-postgres-test', '--to', 'signaturegate-postgres'
    ]);
    fs.rmSync(testFile);
  }

  run('node', [
    'scripts/appsmith-rebind-datasource.mjs', '--source', staged,
    '--verify', '--expected-datasource', 'signaturegate-postgres'
  ]);
  run('node', ['scripts/appsmith-export.mjs', '--source', staged, '--output', output]);
  run('python3', [
    'scripts/validate_appsmith_source_export.py', '--source', staged, '--export', output
  ]);
  const exported = JSON.parse(fs.readFileSync(output, 'utf8'));
  const names = exported.datasourceList.map(ds => ds.name);
  if (names.includes('signaturegate-postgres-test') || !names.includes('signaturegate-postgres')) {
    throw new Error('Generated export does not exclusively contain the production PostgreSQL descriptor');
  }
  const used = exported.actionList
    .filter(action => action.unpublishedAction?.datasource?.pluginId === 'postgres-plugin')
    .map(action => action.unpublishedAction.datasource.name);
  if (used.some(name => name !== 'signaturegate-postgres')) {
    throw new Error('Generated action uses an unexpected PostgreSQL datasource');
  }
  const record = {
    schemaVersion: 1,
    sourceRepository: 'RayzorDuff/SignatureGate-Appsmith',
    sourceCommit,
    productionDescriptorCommit: descriptorCommit,
    productionDescriptorSHA256: sha256(fs.readFileSync(productionFile)),
    exportSHA256: sha256(fs.readFileSync(output)),
    pages: exported.pageList.length,
    actions: exported.actionList.length,
    collections: exported.actionCollectionList.length,
    postgresActionCount: used.length,
    productionDatasource: 'signaturegate-postgres',
    runtimeVerified: false
  };
  fs.writeFileSync(provenance, JSON.stringify(record, null, 2) + '\n');
  console.log(JSON.stringify({
    productionBoundExport: output,
    source,
    productionDescriptorSource: productionSource,
    postgresActionCount: used.length,
    productionDatasource: 'signaturegate-postgres',
    note: 'Source is unchanged. Confirm live credentials, ERP mode, workflows, master-only changes and publication separately.'
  }, null, 2));
} catch (error) {
  console.error('Appsmith release export FAILED:', error.message);
  process.exitCode = 1;
} finally {
  if (workspace) fs.rmSync(workspace, { recursive: true, force: true });
}
