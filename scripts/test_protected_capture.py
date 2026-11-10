#!/usr/bin/env python3
"""Exercise only the new read-only evidence collectors on a synthetic CI database."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('comparison', Path(__file__).with_name('compare-protected-upgrade-evidence.py'))
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True, help='Disposable GitHub Actions PostgreSQL service only')
    args = parser.parse_args()
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise SystemExit('Run only against the disposable GitHub Actions service')
    database = 'signaturegate_evidence_fixture_' + uuid.uuid4().hex[:12]
    def sql(text, db=database, flags=()):
        result = subprocess.run(['docker', 'exec', '-i', args.container, 'psql', '-X', '-qAt',
            '-v', 'ON_ERROR_STOP=1', '-U', 'signaturegate', '-d', db, *flags],
            input=text, text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError('Synthetic collector SQL failed: ' + result.stderr)
        return result.stdout
    sql('CREATE DATABASE ' + database, 'postgres')
    try:
        sql('''CREATE TABLE people(person_id integer PRIMARY KEY, updated_at timestamptz);
CREATE TABLE organizations(organization_id integer PRIMARY KEY);
CREATE TABLE members(member_id integer PRIMARY KEY,person_id integer REFERENCES people,notes text);
INSERT INTO people VALUES(1,'2026-01-01'); INSERT INTO organizations VALUES(1);
INSERT INTO members VALUES(1,1,'synthetic historical note');
CREATE FUNCTION evidence_fixture() RETURNS integer LANGUAGE sql AS 'SELECT 1';''')
        capture = (ROOT/'releases/v1.2.0/capture_protected_upgrade_evidence.sql').read_text()
        before = [json.loads(line) for line in sql(capture).splitlines()]
        sql('''ALTER TABLE people ADD COLUMN notes text;
ALTER TABLE organizations ADD COLUMN notes text;
CREATE TABLE member_identity_note_backfill(member_id integer PRIMARY KEY,
 person_id integer,outcome text);
INSERT INTO member_identity_note_backfill VALUES(1,1,'imported');
UPDATE people SET notes='Member 1: synthetic historical note',updated_at=now();''')
        after = [json.loads(line) for line in sql(capture).splitlines()]
        result = comparison.compare(before, after)
        if not result['pass']:
            raise RuntimeError(json.dumps(result))
        permissions = (ROOT/'releases/v1.2.0/check_upgrade_invoker_permissions.sql').read_text()
        rows = [json.loads(line) for line in sql(permissions, flags=(
            '-v','app_role=signaturegate','-v','workflow_role=signaturegate')).splitlines()]
        if len(rows) < 2 or not all(r['exists'] for r in rows if 'exists' in r):
            raise RuntimeError('Principal evidence missing')
        sql("UPDATE members SET notes='unintended history mutation'")
        changed = [json.loads(line) for line in sql(capture).splitlines()]
        if comparison.compare(before, changed)['pass']:
            raise RuntimeError('Historical mutation was not detected')
        print('PASS PostgreSQL protected collectors: owner/catalog/history preservation, permitted note projection, principal matrix and real row mutation detection')
    finally:
        sql('DROP DATABASE ' + database, 'postgres')


if __name__ == '__main__':
    main()
