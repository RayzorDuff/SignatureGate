#!/usr/bin/env python3
"""Exercise real PostgreSQL 16 transaction contention in an owned disposable DB.

Never reads operational tables or applies SQL to signaturegate/signaturegate_test.
Uses the existing Docker PostgreSQL server; no Python database dependency needed.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
DB_PATTERN = re.compile(r'signaturegate_validation_[0-9a-f]{32}\Z')


def owned_database(name):
    if not isinstance(name, str) or not DB_PATTERN.fullmatch(name):
        raise ValueError('Only a generated disposable validation database is permitted')
    return name


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


class Validation:
    def __init__(self, container, user, maintenance, evidence):
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}', container):
            raise ValueError('Invalid container identifier')
        if maintenance not in ('signaturegate_test', 'postgres'):
            raise ValueError('Maintenance connection must be signaturegate_test or postgres')
        self.container, self.user, self.maintenance = container, user, maintenance
        self.evidence = Path(evidence).resolve()
        self.evidence.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.evidence.chmod(0o700)
        self.database = 'signaturegate_validation_' + uuid.uuid4().hex
        (self.evidence / 'invocation.json').write_text(json.dumps({'database': self.database,
                                                                 'created_by_this_run': False}))
        self.created = False
        self.processes = []

    def command(self, database):
        if database != self.maintenance:
            owned_database(database)
            if database != self.database:
                raise ValueError('Database is not owned by this invocation')
        return ['sudo', 'docker', 'exec', '-i', self.container, 'psql', '-X', '-qAt',
                '-v', 'ON_ERROR_STOP=1', '-U', self.user, '-d', database]

    def sql(self, source, *, maintenance=False, label='query'):
        result = subprocess.run(self.command(self.maintenance if maintenance else self.database),
                                input=source, text=True, capture_output=True, timeout=40)
        (self.evidence / (label + '.log')).write_text(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError('PostgreSQL validation failed at ' + label)
        return result.stdout.strip()

    def start(self, source):
        process = subprocess.Popen(self.command(self.database), stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.processes.append(process)
        process.stdin.write(source + '\n')
        process.stdin.flush()
        return process

    def finish(self, process, source=''):
        if process.stdin is not None:
            if source:
                process.stdin.write(source + '\n')
            process.stdin.close()
            process.stdin = None
        return process.communicate(timeout=30)

    def wait_state(self, name, state):
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            current = self.sql("SELECT COALESCE(json_agg(json_build_object('state',state,"
                               "'wait',wait_event_type,'submitted',query LIKE 'SELECT public.application_submit_intake%')),'[]') FROM pg_stat_activity WHERE datname="
                               + literal(self.database) + ' AND application_name=' + literal(name) + ';',
                               maintenance=True, label='session-state')
            rows = json.loads(current)
            ready = any(row['state'] == 'idle in transaction' and row['submitted'] for row in rows)
            blocked = any(row['wait'] == 'Lock' and row['submitted'] for row in rows)
            if ready if state == 'ready' else blocked:
                return
            if any(p.poll() not in (None, 0) for p in self.processes):
                raise RuntimeError('A validation session exited before its transaction barrier')
            time.sleep(0.05)
        raise RuntimeError('Transaction barrier timed out: ' + state)

    def counts(self):
        return json.loads(self.sql("SELECT json_build_array((SELECT count(*) FROM members),"
                                  "(SELECT count(*) FROM application_intake_requests),"
                                  "(SELECT count(*) FROM audit_log WHERE action='intake.completed'));",
                                  label='counts'))

    def close(self):
        for process in self.processes:
            if process.poll() is None:
                process.terminate()
                try:
                    process.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.communicate(timeout=5)
        if self.created:
            owned_database(self.database)
            self.sql('SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='
                     + literal(self.database) + ' AND pid<>pg_backend_pid();',
                     maintenance=True, label='cleanup-sessions')
            self.sql('DROP DATABASE "' + self.database + '";', maintenance=True, label='cleanup-database')
            self.created = False

    def run(self):
        version = int(self.sql('SHOW server_version_num;', maintenance=True, label='server-version'))
        if not 160000 <= version < 170000:
            raise RuntimeError('This release check requires PostgreSQL major version 16')
        owned_database(self.database)
        self.sql('CREATE DATABASE "' + self.database + '";', maintenance=True, label='create-database')
        self.created = True
        (self.evidence / 'invocation.json').write_text(json.dumps({'database': self.database,
                                                                 'created_by_this_run': True}))
        schema = (ROOT / 'db/schema.sql').read_text()
        self.sql(schema, label='bootstrap')
        migration = (ROOT / 'db/migrations/atomic_intake.sql').read_text()
        for attempt in range(2):
            self.sql(migration, label='migration-' + str(attempt))
        self.sql((ROOT / 'db/tests/verify_atomic_intake.sql').read_text(), label='atomic-contract')
        # Artificial principals only, inside the generated disposable database.
        self.sql("""INSERT INTO people(person_id,display_name) VALUES
 ('10000000-0000-4000-8000-000000000001','Synthetic Concurrency Reviewer'),
 ('10000000-0000-4000-8000-000000000002','Synthetic Concurrency Other'),
 ('10000000-0000-4000-8000-000000000003','Synthetic Concurrency Practitioner');
INSERT INTO person_app_accounts(person_id,email) VALUES
 ('10000000-0000-4000-8000-000000000001','concurrency-reviewer@example.invalid'),
 ('10000000-0000-4000-8000-000000000002','concurrency-other@example.invalid');
INSERT INTO person_roles(person_id,role_key,assigned_by) VALUES
 ('10000000-0000-4000-8000-000000000001','document_reviewer','synthetic_validation'),
 ('10000000-0000-4000-8000-000000000002','document_reviewer','synthetic_validation'),
 ('10000000-0000-4000-8000-000000000003','practitioner','synthetic_validation');
""", label='synthetic-principals')
        cases = ['commit_replay', 'rollback_retry', 'payload_conflict', 'owner_conflict']
        for index, case in enumerate(cases):
            key = str(uuid.uuid4())
            payload = dict(kind='individual', participant=True, contributor=False,
                           first_name='Synthetic', last_name='Concurrent' + str(index),
                           email='concurrent-' + str(index) + '@example.invalid',
                           phone='555070' + str(index).zfill(4), agreement_delivery='Later',
                           practitioner_person_id='10000000-0000-4000-8000-000000000003')
            actor = 'concurrency-reviewer@example.invalid'
            def submit(email, data):
                return ('SELECT public.application_submit_intake(' + literal(email) + ','
                        + literal(key) + '::uuid,' + literal(json.dumps(data)) + '::jsonb);')
            prefix = "SET statement_timeout='25s'; SET lock_timeout='20s'; SET application_name="
            baseline = self.counts()
            winner = self.start(prefix + literal('validation_winner_' + case) + ';\nBEGIN;\n' + submit(actor, payload))
            self.wait_state('validation_winner_' + case, 'ready')
            other = dict(payload)
            if case == 'payload_conflict':
                other['notes'] = 'Synthetic changed payload'
            second_actor = 'concurrency-other@example.invalid' if case == 'owner_conflict' else actor
            waiter = self.start(prefix + literal('validation_waiter_' + case) + ';\nBEGIN;\n'
                                + submit(second_actor, other) + '\nCOMMIT;')
            self.wait_state('validation_waiter_' + case, 'blocked')
            first_out, first_err = self.finish(winner, 'ROLLBACK;' if case == 'rollback_retry' else 'COMMIT;')
            second_out, second_err = self.finish(waiter)
            (self.evidence / (case + '.log')).write_text(first_out + first_err + second_out + second_err)
            if winner.returncode != 0:
                raise RuntimeError('Winner transaction failed: ' + case)
            conflict = case.endswith('conflict')
            if conflict:
                if waiter.returncode == 0 or 'Request key unavailable for this owner or payload' not in second_err:
                    raise RuntimeError('Concurrent owner/payload conflict was not rejected')
            elif waiter.returncode != 0:
                raise RuntimeError('Waiting transaction failed: ' + case)
            else:
                first, second = json.loads(first_out.strip()), json.loads(second_out.strip())
                if (first == second) != (case == 'commit_replay'):
                    raise RuntimeError('Concurrent receipt replay/rollback semantics differ')
            if self.counts() != [n + 1 for n in baseline]:
                raise RuntimeError('Concurrent request duplicated or lost enrollment/audit/receipt')
        return dict(postgres_version_num=version, concurrency_cases=cases,
                    atomic_contract='passed', migration_reapplication='passed',
                    operational_tables_accessed=False, external_services_called=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', required=True)
    parser.add_argument('--user', default='signaturegate')
    parser.add_argument('--maintenance-database', default='signaturegate_test', choices=['signaturegate_test', 'postgres'])
    parser.add_argument('--evidence', type=Path, default=Path.home() / 'signaturegate-release-evidence/v1.2.0/postgres-intake')
    args = parser.parse_args()
    os.umask(0o077)
    validation = Validation(args.container, args.user, args.maintenance_database, args.evidence)
    try:
        result = validation.run()
    finally:
        validation.close()
    result['disposable_database_removed'] = True
    (validation.evidence / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError):
        raise SystemExit('PostgreSQL Intake validation failed. Keep detailed evidence private; production was not targeted.')
