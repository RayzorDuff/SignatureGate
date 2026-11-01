#!/usr/bin/env python3
"""Verify that a generated application preserves the split Appsmith source.

This supplements Appsmith runtime validation. It does not infer credentials,
connection targets or published-app state from Git datasource descriptors.
"""
import argparse
import json
from pathlib import Path


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def assets(root):
    return [read(p) for p in sorted(root.rglob('*.json'))] if root.exists() else []


def tree_widgets(node):
    if isinstance(node, dict):
        if node.get('widgetName'):
            yield node
        for child in node.get('children', []):
            yield from tree_widgets(child)


def validate(source, exported):
    failures = []
    if exported.get('exportedApplication') != read(source / 'application.json'):
        failures.append('Application configuration differs from source')
    expected_ds = {x['name']: x for x in assets(source / 'datasources')}
    actual_ds = {x['name']: x for x in exported.get('datasourceList', [])}
    if expected_ds != actual_ds or len(actual_ds) != len(exported.get('datasourceList', [])):
        failures.append('Datasource descriptors are missing, duplicated or changed')
    libraries = assets(source / 'jslibs') + assets(source / 'customJSLibs')
    expected_libs = {x.get('uidString', x['name']): x for x in libraries}
    actual_libs = {x.get('uidString', x['name']): x for x in exported.get('customJSLibList', [])}
    if expected_libs != actual_libs or len(actual_libs) != len(exported.get('customJSLibList', [])):
        failures.append('JS library descriptors are missing, duplicated or changed')
    expected_pages = {p.name for p in (source / 'pages').iterdir() if p.is_dir()}
    exported_pages = {p.get('unpublishedPage', {}).get('name'): p for p in exported.get('pageList', [])}
    if expected_pages != exported_pages.keys() or len(exported_pages) != len(exported.get('pageList', [])):
        failures.append('Page registry is missing, duplicated or changed')
    for name in expected_pages & exported_pages.keys():
        source_page = read(source / 'pages' / name / f'{name}.json')
        page = exported_pages[name]
        if page.get('publishedPage') != page.get('unpublishedPage'):
            failures.append(f'{name}: generated published/unpublished page drift')
        expected = source_page.get('unpublishedPage', source_page.get('publishedPage'))
        actual = page.get('unpublishedPage', {})
        for key, value in expected.items():
            if key != 'layouts' and actual.get(key) != value:
                failures.append(f'{name}: page field changed: {key}')
        actual_widgets = {}
        for layout in actual.get('layouts', []):
            for widget in tree_widgets(layout.get('dsl', {})):
                key = widget.get('widgetId')
                if key in actual_widgets:
                    failures.append(f'{name}: duplicate exported widget ID {key}')
                actual_widgets[key] = widget
        for path in (source / 'pages' / name / 'widgets').rglob('*.json'):
            source_widget = read(path)
            if not source_widget.get('widgetName'):
                continue
            # Includes embedded canvases without their own widget files.
            for widget in tree_widgets(source_widget):
                actual_widget = actual_widgets.get(widget['widgetId'], {})
                if not actual_widget:
                    failures.append(f'{name}: missing widget {widget["widgetName"]}')
                    continue
                for key, value in widget.items():
                    if key != 'children' and actual_widget.get(key) != value:
                        failures.append(f'{name}/{widget["widgetName"]}: property changed: {key}')
    for folder, variant, export_key in [
        ('queries', 'Action', 'actionList'),
        ('jsobjects', 'Collection', 'actionCollectionList')
    ]:
        actual = {x.get('id'): x for x in exported.get(export_key, [])}
        files = list((source / 'pages').glob(f'*/{folder}/*/metadata.json'))
        if len(actual) != len(files) or len(actual) != len(exported.get(export_key, [])):
            failures.append(f'{export_key}: missing or duplicate registrations')
        for path in files:
            metadata = read(path)
            expected = metadata.get('unpublished' + variant, metadata.get('published' + variant))
            expected = json.loads(json.dumps(expected))
            name = expected.get('name', path.parent.name)
            body_file = next((path.parent / file for file in [name+'.txt', 'body.txt', name+'.js']
                              if (path.parent / file).exists()), None)
            if body_file:
                body = body_file.read_text(encoding='utf-8')
                if variant == 'Action':
                    expected.setdefault('actionConfiguration', {})['body'] = body
                else:
                    expected['body'] = body
            entry = actual.get(metadata.get('id'), {})
            for field in ['gitSyncId', 'id', 'pluginId', 'pluginType']:
                if field in metadata and entry.get(field) != metadata[field]:
                    failures.append(f'{path.parent.name}: {field} changed')
            for prefix in ['published', 'unpublished']:
                if entry.get(prefix + variant) != expected:
                    failures.append(f'{path.parent.name}: {prefix}{variant} differs from source')
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--export', required=True, dest='export_path', type=Path)
    args = parser.parse_args()
    failures = validate(args.source, read(args.export_path))
    if failures:
        raise SystemExit('Source/export validation failed:\n- ' + '\n- '.join(failures))
    print('Appsmith source/export preservation checks passed')


if __name__ == '__main__':
    main()
