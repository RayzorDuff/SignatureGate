#!/usr/bin/env python3
"""Read-only source inventory for the v1.2.0 release; not a runtime linter.

Run from SignatureGate: python3 releases/v1.2.0/audit_source.py \
  --appsmith ../SignatureGate-Appsmith --output releases/v1.2.0/evidence
Inventory output excludes credential values, query bodies, and donor data.
"""
import argparse
import collections
import csv
import hashlib
import json
import pathlib
import re
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def strings(value, prefix=''):
    if isinstance(value, dict):
        for key, item in value.items():
            yield from strings(item, f'{prefix}.{key}' if prefix else key)
    elif isinstance(value, list):
        for i, item in enumerate(value):
            yield from strings(item, f'{prefix}[{i}]')
    elif isinstance(value, str):
        yield prefix, value


def write_csv(output, name, rows, fields):
    with (output / name).open('w', newline='', encoding='utf-8') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--appsmith', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[2]
    app = args.appsmith.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    parsed = {p: json.loads(p.read_text()) for p in app.rglob('*.json') if '.git' not in p.parts}
    pages, actions, links, findings = [], [], [], []
    js_results = []
    for directory in sorted((app / 'pages').iterdir()):
        if not directory.is_dir():
            continue
        name = directory.name
        page_meta = parsed[directory / f'{name}.json']
        page = page_meta.get('unpublishedPage', page_meta.get('publishedPage', {}))
        widgets = {x.get('widgetName') for p, x in parsed.items()
                   if p.is_relative_to(directory / 'widgets') and x.get('widgetName')}
        page_actions = []
        for meta in sorted((directory / 'queries').glob('*/metadata.json')):
            x = parsed[meta]
            a = x.get('unpublishedAction', x.get('publishedAction', {}))
            action_name = a.get('name', meta.parent.name)
            config = a.get('actionConfiguration', {})
            body_file = next((meta.parent / f for f in [action_name + '.txt', 'body.txt', action_name + '.js']
                              if (meta.parent / f).exists()), None)
            body = body_file.read_text() if body_file else config.get('body', '')
            if body_file and body != config.get('body', ''):
                findings.append({'kind': 'body_metadata_drift', 'page': name,
                                 'path': str(meta.relative_to(app)), 'property': 'actionConfiguration.body',
                                 'detail': action_name})
            ds = a.get('datasource', {})
            funcs = sorted(set(re.findall(r'\bpublic\.([A-Za-z_][\w]*)\s*\(', body)))
            row = dict(page=name, action=action_name, plugin_type=x.get('pluginType', a.get('pluginType', '')),
                       datasource=ds.get('name', ds.get('id', '')), execution=a.get('runBehaviour', ''),
                       user_set_on_load=a.get('userSetOnLoad', ''),
                       explicit_params=';'.join(sorted(set(re.findall(r'\bthis\.params\.([\w]+)', body)))),
                       functions=';'.join(funcs),
                       api_path=config.get('path', '') if x.get('pluginType') == 'API' else '',
                       path=str(meta.relative_to(app)))
            actions.append(row)
            page_actions.append(row)
        text_sources = []
        for p in sorted(directory.rglob('*')):
            if not p.is_file() or p.suffix not in {'.json', '.js', '.txt'}:
                continue
            # JSON metadata and separate action bodies often duplicate strings.
            text_sources.append((p, p.read_text()))
        outgoing = set()
        store_keys, url_params = set(), set()
        roles = set()
        for p, text in text_sources:
            outgoing.update(re.findall(r'\bnavigateTo\(\s*[\'\"]([^\'\"]+)[\'\"]', text))
            store_keys.update(re.findall(r'\bappsmith\.store\.([\w]+)', text))
            store_keys.update(re.findall(r'\bstoreValue\(\s*[\'\"]([^\'\"]+)', text))
            url_params.update(re.findall(r'\bqueryParams\??\.([\w]+)', text))
            roles.update(re.findall(r'\b(?:is_document_reviewer|is_donations_reviewer|is_facilitator|directory_manager|document_reviewer|donations_reviewer)\b', text))
        for p, value in parsed.items():
            if not p.is_relative_to(directory):
                continue
            for prop, text in strings(value):
                # Bare empty-table fallback observed in Appsmith errors.
                match = re.search(r':\s*([A-Za-z_$][\w$]*)\s*\}\)\(\)\s*\}\}', text)
                if 'primaryColumns.' in prop and match and match[1] not in {'null', 'undefined', 'true', 'false'}:
                    findings.append(dict(kind='bare_table_fallback', page=name, path=str(p.relative_to(app)),
                                         property=prop, detail=match[1]))
                if 'FilePickerIndividualAgreement.files' in text and 'FilePickerIndividualAgreement' not in widgets:
                    findings.append(dict(kind='missing_widget_reference', page=name,
                                         path=str(p.relative_to(app)), property=prop,
                                         detail='FilePickerIndividualAgreement'))
        for target in sorted(outgoing):
            links.append(dict(page=name, target=target, exists=(app / 'pages' / target).is_dir(),
                              note='Literal route only; conditional/dynamic targets require review'))
        pages.append(dict(page=name, hidden=page.get('isHidden', False), widget_count=len(widgets),
                          sql_actions=sum(a['plugin_type'] == 'DB' for a in page_actions),
                          api_actions=sum(a['plugin_type'] == 'API' for a in page_actions),
                          js_actions=sum(a['plugin_type'] == 'JS' for a in page_actions),
                          on_load_actions=';'.join(a['action'] for a in page_actions if a['execution'] == 'ON_PAGE_LOAD'),
                          outgoing_literal_routes=';'.join(sorted(outgoing)),
                          url_params=';'.join(sorted(url_params)), store_keys=';'.join(sorted(store_keys)),
                          role_terms=';'.join(sorted(roles))))
        for p in sorted((directory / 'jsobjects').glob('*/*.js')):
            code = re.sub(r'^\s*export\s+default\s+', 'const object = ', p.read_text(), count=1)
            result = subprocess.run(['node', '--check', '-'], input=code, text=True, capture_output=True)
            js_results.append(dict(path=str(p.relative_to(app)), syntax_ok=result.returncode == 0))
    migrations = []
    objects = collections.defaultdict(list)
    for p in sorted((root / 'db/migrations').glob('*.sql')):
        text = p.read_text()
        defined = re.findall(r'\bCREATE\s+(?:OR\s+REPLACE\s+)?(?:FUNCTION|VIEW|TABLE)\s+(?:IF\s+NOT\s+EXISTS\s+)?public\.([\w]+)', text, re.I)
        for obj in defined:
            objects[obj].append(p.name)
        migrations.append(dict(path=str(p.relative_to(root)), sha256=sha(p),
                               explicit_transaction=bool(re.search(r'^BEGIN;', text, re.M) and re.search(r'^COMMIT;', text, re.M)),
                               defines=';'.join(defined), production_applied='unknown', test_applied='unknown'))
    summary = dict(appsmith_revision=git(app, 'rev-parse', 'HEAD'),
                   signaturegate_source_revision=git(root, 'rev-parse', '9fb5aa5'),
                   baseline_v1_1_0=git(root, 'rev-parse', 'v1.1.0'),
                   commits_since_v1_1_0=int(git(root, 'rev-list', '--count', 'v1.1.0..9fb5aa5')),
                   json_files=len(parsed), pages=len(pages), actions=len(actions), js_objects=len(js_results),
                   js_syntax_all_pass=all(r['syntax_ok'] for r in js_results),
                   datasource_descriptors=len(list((app / 'datasources').glob('*.json'))),
                   jslib_descriptors=len(list((app / 'jslibs').glob('*.json'))),
                   findings_by_kind=dict(collections.Counter(f['kind'] for f in findings)),
                   action_datasources=dict(collections.Counter(a['datasource'] for a in actions if a['plugin_type'] != 'JS')),
                   multiply_defined_migration_objects={k: v for k, v in objects.items() if len(v) > 1},
                   live_environment_verified=False)
    (output / 'source_summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    for name, rows, fields in [
        ('pages.csv', pages, list(pages[0])), ('actions.csv', actions, list(actions[0])),
        ('routes.csv', links, ['page', 'target', 'exists', 'note']),
        ('source_findings.csv', findings, ['kind', 'page', 'path', 'property', 'detail']),
        ('migrations.csv', migrations, list(migrations[0])),
        ('js_syntax.csv', js_results, ['path', 'syntax_ok'])]:
        write_csv(output, name, rows, fields)
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
