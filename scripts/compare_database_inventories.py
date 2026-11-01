#!/usr/bin/env python3
"""Compare read-only release catalog captures; differences require review."""
import argparse
import csv
import json
from pathlib import Path

KEYS = {
    'extensions': ('name',), 'relations': ('name',),
    'columns': ('table', 'name'), 'functions': ('name', 'arguments'),
    'views': ('name',), 'constraints': ('table', 'name'),
    'triggers': ('table', 'name'), 'indexes': ('table', 'name'),
    'row_policies': ('table', 'name'),
}


def read(path):
    value = json.loads(path.read_text())
    for key in ('database', 'server_version', 'captured_at', *KEYS):
        if key not in value:
            raise ValueError(f'{path}: missing {key}; capture may be incomplete')
    return value


def indexed(rows, fields):
    result = {}
    for row in rows:
        key = tuple(str(row[field]) for field in fields)
        if key in result:
            raise ValueError(f'Duplicate catalog identity: {key}')
        # Statistics change without schema changes and aren't acceptance evidence.
        result[key] = {k: v for k, v in row.items() if k != 'estimated_rows'}
    return result


def compare(reference, actual, environment):
    result = []
    for section, fields in KEYS.items():
        expected = indexed(reference[section], fields)
        deployed = indexed(actual[section], fields)
        for key in sorted(expected.keys() | deployed.keys()):
            a, b = expected.get(key), deployed.get(key)
            if a == b:
                continue
            state = 'extra_in_deployed' if a is None else 'missing_in_deployed' if b is None else 'changed'
            changed = sorted(k for k in a.keys() | b.keys() if a.get(k) != b.get(k)) if a is not None and b is not None else []
            result.append({
                'environment': environment, 'section': section, 'object': ' / '.join(key),
                'difference': state, 'changed_fields': '; '.join(changed),
                'canonical': json.dumps(a, sort_keys=True), 'deployed': json.dumps(b, sort_keys=True),
                'disposition': 'pending_review', 'migration_or_backfill': '',
                'prerequisites': '', 'verification': '', 'recovery': '',
            })
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    reference = read(args.evidence / 'database-canonical.json')
    rows = []
    totals = {}
    for environment, database in [('test', 'signaturegate_test'), ('production', 'signaturegate')]:
        actual = read(args.evidence / f'database-{environment}.json')
        if actual['database'] != database:
            raise ValueError(f'{environment}: expected {database}, got {actual["database"]}')
        if actual['server_version'].split('.')[0] != reference['server_version'].split('.')[0]:
            raise ValueError('Capture canonical schema on the same PostgreSQL major version')
        differences = compare(reference, actual, environment)
        rows.extend(differences)
        totals[environment] = len(differences)
    output = args.evidence / 'database-differences.csv'
    fields = ['environment', 'section', 'object', 'difference', 'changed_fields', 'canonical', 'deployed',
              'disposition', 'migration_or_backfill', 'prerequisites', 'verification', 'recovery']
    # Preserve an operator's reviewed dispositions; regeneration is always separate.
    if output.exists():
        raise ValueError(f'{output} exists; preserve the reviewed file before regenerating')
    with output.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)
    print(json.dumps({'differences': totals, 'output': str(output), 'phase_1': 'pending_live_review'}, indent=2))


if __name__ == '__main__':
    main()
