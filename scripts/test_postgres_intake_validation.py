#!/usr/bin/env python3
"""Safety/failure tests for the real-server runner; no Docker or DB is accessed."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from validate_postgres_intake import Validation, owned_database, literal


class DisposableDatabaseChecks(unittest.TestCase):
    def test_rejects_operational_or_user_chosen_targets(self):
        for name in ('signaturegate', 'signaturegate_test', 'postgres',
                     'signaturegate_validation_existing', '', None,
                     'signaturegate_validation_' + 'a' * 32 + '; DROP DATABASE postgres;'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                owned_database(name)
        self.assertEqual(literal("a'b"), "'a''b'")

    def test_maintenance_and_container_input(self):
        with tempfile.TemporaryDirectory() as directory:
            for container, maintenance in [('signaturegate-postgres','signaturegate'),
                                           ('--privileged','postgres'), ('x;echo bad','postgres')]:
                with self.assertRaises(ValueError):
                    Validation(container, 'signaturegate', maintenance, directory)

    def test_cleanup_only_after_successful_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Validation('synthetic-container', 'signaturegate', 'signaturegate_test', directory)
            run.sql = Mock()
            run.close()
            run.sql.assert_not_called()
            with self.assertRaises(ValueError):
                run.command('signaturegate')
            with self.assertRaises(ValueError):
                run.command('signaturegate_validation_' + '0' * 32)
            run.created = True
            run.close()
            self.assertEqual(run.sql.call_count, 2)
            self.assertIn('DROP DATABASE "' + run.database + '"', run.sql.call_args.args[0])
            self.assertFalse(run.created)

    def test_creation_failure_never_drops_an_existing_database(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Validation('synthetic-container', 'signaturegate', 'postgres', directory)
            run.sql = Mock(side_effect=['160013', RuntimeError('synthetic create failure')])
            with self.assertRaises(RuntimeError):
                run.run()
            calls = run.sql.call_count
            run.close()
            self.assertEqual(run.sql.call_count, calls)
            self.assertFalse(run.created)

    def test_wait_barrier_requires_completed_submit_not_just_begin(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Validation('synthetic-container', 'signaturegate', 'postgres', directory)
            run.sql = Mock(side_effect=['[{"state":"idle in transaction","wait":null,"submitted":false}]',
                                       '[{"state":"idle in transaction","wait":null,"submitted":true}]'])
            with patch('validate_postgres_intake.time.sleep'):
                run.wait_state('synthetic', 'ready')
            self.assertEqual(run.sql.call_count, 2)

    def test_wrong_major_version_never_creates_a_database(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Validation('synthetic-container', 'signaturegate', 'postgres', directory)
            run.sql = Mock(return_value='180003')
            with self.assertRaises(RuntimeError):
                run.run()
            self.assertEqual(run.sql.call_count, 1)
            self.assertFalse(run.created)


if __name__ == '__main__':
    unittest.main()
