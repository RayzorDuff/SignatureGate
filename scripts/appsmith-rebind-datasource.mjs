#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function usage() {
  console.error(`Usage:\n  node scripts/appsmith-rebind-datasource.mjs --source <dir> --from <datasource> --to <datasource> [--dry-run]\n  node scripts/appsmith-rebind-datasource.mjs --source <dir> --verify --expected-datasource <datasource>`);
  process.exitCode = 2;
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) throw new Error(`Unexpected argument: ${token}`);
    const key = token.slice(2);
    if (key === 'dry-run' || key === 'verify') {
      args[key] = true;
      continue;
    }
    const value = argv[++i];
    if (value == null || value.startsWith('--')) throw new Error(`Missing value for --${key}`);
    args[key] = value;
  }
  return args;
}

function fail(message) {
  throw new Error(message);
}

function walk(dir) {
  const result = [];
  const entries = fs.readdirSync(dir, { withFileTypes: true })
    .sort((a, b) => a.name.localeCompare(b.name));
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) result.push(...walk(full));
    else result.push(full);
  }
  return result;
}

function queryMetadataFiles(source) {
  const pages = path.join(source, 'pages');
  if (!fs.existsSync(pages)) fail(`Appsmith source has no pages directory: ${pages}`);
  return walk(pages).filter(file => {
    const rel = path.relative(source, file).split(path.sep);
    const queryIndex = rel.indexOf('queries');
    return path.basename(file) === 'metadata.json' && queryIndex >= 1;
  });
}

function skipString(text, start) {
  let i = start + 1;
  while (i < text.length) {
    if (text[i] === '\\') {
      i += 2;
      continue;
    }
    if (text[i] === '"') return i + 1;
    i += 1;
  }
  fail(`Unterminated JSON string at offset ${start}`);
}

function skipValue(text, start) {
  let i = start;
  while (/\s/.test(text[i] ?? '')) i += 1;
  const ch = text[i];
  if (ch === '"') return skipString(text, i);
  if (ch === '{' || ch === '[') {
    const open = ch;
    const close = ch === '{' ? '}' : ']';
    let depth = 0;
    for (; i < text.length; i += 1) {
      if (text[i] === '"') {
        i = skipString(text, i) - 1;
        continue;
      }
      if (text[i] === open) depth += 1;
      else if (text[i] === close) {
        depth -= 1;
        if (depth === 0) return i + 1;
      }
    }
    fail(`Unterminated JSON ${open === '{' ? 'object' : 'array'} at offset ${start}`);
  }
  while (i < text.length && !/[\s,}\]]/.test(text[i])) i += 1;
  return i;
}

function objectPropertySpans(text, objectStart) {
  if (text[objectStart] !== '{') fail(`Expected JSON object at offset ${objectStart}`);
  const props = new Map();
  let i = objectStart + 1;
  while (true) {
    while (/\s/.test(text[i] ?? '')) i += 1;
    if (text[i] === '}') return props;
    if (text[i] !== '"') fail(`Malformed JSON object near offset ${i}`);
    const keyStart = i;
    const keyEnd = skipString(text, i);
    const key = JSON.parse(text.slice(keyStart, keyEnd));
    i = keyEnd;
    while (/\s/.test(text[i] ?? '')) i += 1;
    if (text[i] !== ':') fail(`Malformed JSON object after ${key} at offset ${i}`);
    i += 1;
    while (/\s/.test(text[i] ?? '')) i += 1;
    const valueStart = i;
    const valueEnd = skipValue(text, i);
    props.set(key, { keyStart, keyEnd, valueStart, valueEnd });
    i = valueEnd;
    while (/\s/.test(text[i] ?? '')) i += 1;
    if (text[i] === ',') {
      i += 1;
      continue;
    }
    if (text[i] === '}') return props;
    fail(`Malformed JSON object near offset ${i}`);
  }
}

function findDatasourceObjectSpans(text) {
  const spans = [];
  let i = 0;
  while (i < text.length) {
    if (text[i] === '"') {
      const keyStart = i;
      const keyEnd = skipString(text, i);
      let j = keyEnd;
      while (/\s/.test(text[j] ?? '')) j += 1;
      if (text.slice(keyStart, keyEnd) === '"datasource"' && text[j] === ':') {
        j += 1;
        while (/\s/.test(text[j] ?? '')) j += 1;
        if (text[j] === '{') {
          const valueEnd = skipValue(text, j);
          spans.push({ start: j, end: valueEnd });
          i = valueEnd;
          continue;
        }
      }
      i = keyEnd;
      continue;
    }
    i += 1;
  }
  return spans;
}

function quotedPropertyReplacement(text, objectStart, property, expected, replacement) {
  const props = objectPropertySpans(text, objectStart);
  const prop = props.get(property);
  if (!prop) fail(`Datasource object is missing ${property}`);
  const raw = text.slice(prop.valueStart, prop.valueEnd);
  let actual;
  try { actual = JSON.parse(raw); } catch { fail(`Datasource ${property} is not a valid JSON value`); }
  if (typeof actual !== 'string') fail(`Datasource ${property} must be a string`);
  if (actual !== expected) return null;
  return { start: prop.valueStart, end: prop.valueEnd, value: JSON.stringify(replacement) };
}

function inspectMetadata(file, text) {
  let parsed;
  try { parsed = JSON.parse(text); }
  catch (error) { fail(`${file}: malformed JSON: ${error.message}`); }
  if (!parsed || typeof parsed !== 'object') fail(`${file}: metadata root must be an object`);

  const spans = findDatasourceObjectSpans(text);
  const refs = [];
  for (const span of spans) {
    const props = objectPropertySpans(text, span.start);
    const pluginId = props.get('pluginId');
    if (!pluginId) fail(`${file}: datasource object is missing pluginId`);
    let pluginValue;
    try {
      pluginValue = JSON.parse(text.slice(pluginId.valueStart, pluginId.valueEnd));
    } catch {
      fail(`${file}: datasource pluginId contains invalid JSON`);
    }
    if (pluginValue !== 'postgres-plugin') continue;

    const id = props.get('id');
    const name = props.get('name');
    if (!id || !name) fail(`${file}: PostgreSQL datasource object must contain both id and name`);
    let idValue, nameValue;
    try {
      idValue = JSON.parse(text.slice(id.valueStart, id.valueEnd));
      nameValue = JSON.parse(text.slice(name.valueStart, name.valueEnd));
    } catch {
      fail(`${file}: PostgreSQL datasource id/name contains invalid JSON`);
    }
    if (typeof idValue !== 'string' || typeof nameValue !== 'string') fail(`${file}: PostgreSQL datasource id/name must be strings`);
    if (idValue !== nameValue) fail(`${file}: PostgreSQL datasource id (${idValue}) does not match name (${nameValue})`);
    refs.push({ span, datasource: idValue, pluginId: pluginValue });
  }
  return { parsed, refs };
}

function processFile(file, from, to) {
  const before = fs.readFileSync(file, 'utf8');
  const { refs } = inspectMetadata(file, before);
  const changes = [];
  const replacements = [];
  for (const ref of refs) {
    if (ref.datasource !== from) continue;
    const idChange = quotedPropertyReplacement(before, ref.span.start, 'id', from, to);
    const nameChange = quotedPropertyReplacement(before, ref.span.start, 'name', from, to);
    if (!idChange || !nameChange) fail(`${file}: datasource reference is inconsistent with expected source ${from}`);
    replacements.push(idChange, nameChange);
    changes.push({ from, to });
  }
  if (!changes.length) return { changed: false, refs: refs.map(r => r.datasource), changes: 0 };
  replacements.sort((a, b) => b.start - a.start);
  let after = before;
  for (const replacement of replacements) {
    after = after.slice(0, replacement.start) + replacement.value + after.slice(replacement.end);
  }
  const recheck = inspectMetadata(file, after);
  if (recheck.refs.some(r => r.datasource === from)) fail(`${file}: replacement left a ${from} datasource reference`);
  return { changed: true, after, refs: refs.map(r => r.datasource), changes: changes.length };
}

function ensureDatasourceDefinition(source, name) {
  const file = path.join(source, 'datasources', `${name}.json`);
  if (!fs.existsSync(file)) fail(`Datasource definition not found in source: ${file}`);
  let parsed;
  try { parsed = JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (error) { fail(`Malformed datasource definition ${file}: ${error.message}`); }
  if (parsed.name !== name || parsed.pluginId !== 'postgres-plugin') {
    fail(`Datasource definition ${file} does not match expected PostgreSQL datasource ${name}`);
  }
}

function main() {
  let args;
  try {
    args = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(`error: ${error.message}`);
    usage();
    return;
  }

  if (!args.source) {
    console.error('error: --source is required');
    usage();
    return;
  }

  const source = path.resolve(args.source);
  if (!fs.existsSync(source)) fail(`Source directory not found: ${source}`);

  const isVerify = args.verify === true;
  if (isVerify) {
    if (!args['expected-datasource'] || args.from || args.to) {
      fail('--verify requires --expected-datasource and cannot be combined with --from/--to');
    }
    ensureDatasourceDefinition(source, args['expected-datasource']);
  } else {
    if (!args.from || !args.to || args.from === args.to) {
      fail('--from and --to are required and must differ');
    }
    ensureDatasourceDefinition(source, args.from);
    ensureDatasourceDefinition(source, args.to);
  }

  const files = queryMetadataFiles(source);
  const failures = [];
  const changedFiles = [];
  const pendingWrites = [];
  let referencesSeen = 0;
  let referencesChanged = 0;
  const unexpected = [];

  for (const file of files) {
    try {
      if (isVerify) {
        const text = fs.readFileSync(file, 'utf8');
        const { refs } = inspectMetadata(file, text);
        referencesSeen += refs.length;
        for (const ref of refs) {
          if (ref.datasource !== args['expected-datasource']) {
            unexpected.push({ file: path.relative(source, file), datasource: ref.datasource });
          }
        }
      } else {
        const result = processFile(file, args.from, args.to);
        referencesSeen += result.refs.length;
        referencesChanged += result.changes;
        if (result.changed) {
          changedFiles.push({
            file: path.relative(source, file),
            referencesChanged: result.changes
          });
          if (!args['dry-run']) pendingWrites.push({ file, content: result.after });
        }
      }
    } catch (error) {
      failures.push(error.message);
    }
  }

  if (failures.length) {
    console.error(JSON.stringify({ ok: false, errors: failures }, null, 2));
    process.exitCode = 1;
    return;
  }

  for (const write of pendingWrites) fs.writeFileSync(write.file, write.content);

  const summary = isVerify
    ? {
        ok: unexpected.length === 0,
        mode: 'verify',
        source,
        filesScanned: files.length,
        datasourceReferences: referencesSeen,
        expectedDatasource: args['expected-datasource'],
        unexpected
      }
    : {
        ok: true,
        mode: 'rebind',
        source,
        filesScanned: files.length,
        datasourceReferences: referencesSeen,
        from: args.from,
        to: args.to,
        referencesChanged,
        filesChanged: changedFiles.length,
        dryRun: Boolean(args['dry-run']),
        changedFiles
      };

  console.log(JSON.stringify(summary, null, 2));
  if (isVerify && unexpected.length) process.exitCode = 1;
}

try {
  main();
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exitCode = 1;
}
