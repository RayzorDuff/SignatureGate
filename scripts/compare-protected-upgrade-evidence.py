#!/usr/bin/env python3
"""Compare private JSONL captures. Does not connect, grant, migrate or expose rows."""
import argparse
import json
from pathlib import Path


def compare(before, after):
    def index(rows):
        result = {}
        for row in rows:
            kind = row['kind']
            if kind in {'capture', 'backfill'}:
                continue
            key = (kind, row.get('name', row.get('role')), row.get('member'))
            if key in result:
                raise ValueError('Duplicate evidence identity')
            result[key] = row
        return result
    old, new = index(before), index(after)
    failures = []
    for key, row in old.items():
        if new.get(key) != row:
            # Only catalog identity, never record contents or role values.
            failures.append({'kind': key[0], 'object': key[1], 'reason': 'changed_or_missing'})
    checks = [r for r in after if r['kind'] == 'backfill']
    if len(checks) != 1 or checks[0].get('name') != 'member_identity_note_backfill':
        failures.append({'kind': 'backfill', 'reason': 'missing_evidence'})
    elif any(checks[0].get(k) != 0 for k in ('missing_members', 'bad_relationships', 'missing_imported_chunks')):
        failures.append({'kind': 'backfill', 'reason': 'historical_invariant_failed'})
    for required in ('capture', 'role', 'schema', 'relation', 'routine', 'history', 'constraint'):
        if not any(r['kind'] == required for r in before) or not any(r['kind'] == required for r in after):
            failures.append({'kind': required, 'reason': 'incomplete_capture'})
    if any(r['kind'] == 'constraint' and r.get('validated') is not True for r in after):
        failures.append({'kind': 'constraint', 'reason': 'unvalidated_constraint_requires_review'})
    return {'pass': not failures, 'historical_tables_compared': sum(k[0] == 'history' for k in old),
            'existing_catalog_entries_compared': sum(k[0] != 'history' for k in old),
            'new_catalog_entries_require_permission_review': sum(k not in old and k[0] != 'history' for k in new),
            'failures': failures,
            'limits': ['Does not prove invoker privileges or worker isolation.',
                       'people.notes/updated_at and newly added organizations.notes excluded from history digest; private note review required.',
                       'MD5 digests detect accidental changes, not hostile tampering. Keep capture files protected.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    args = parser.parse_args()
    rows = lambda p: [json.loads(line) for line in p.read_text().splitlines() if line.strip()]
    try:
        result = compare(rows(args.before), rows(args.after))
        print(json.dumps(result, indent=2))
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit('Invalid protected evidence: ' + str(error))
    raise SystemExit(0 if result['pass'] else 1)


if __name__ == '__main__':
    main()
