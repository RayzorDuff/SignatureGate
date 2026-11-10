import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('comparison', Path(__file__).with_name('compare-protected-upgrade-evidence.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.before = [{'kind': k, 'name': k, 'digest': 'original'} for k in
                       ('capture', 'role', 'schema', 'relation', 'routine', 'history', 'constraint')]
        self.before[-1]['validated'] = True
        self.after = copy.deepcopy(self.before) + [{'kind': 'backfill', 'name': 'member_identity_note_backfill',
            'missing_members': 0, 'bad_relationships': 0, 'missing_imported_chunks': 0}]

    def test_preservation_and_new_objects(self):
        self.after.append({'kind': 'relation', 'name': 'new_receipt'})
        result = module.compare(self.before, self.after)
        self.assertTrue(result['pass'])
        self.assertEqual(result['new_catalog_entries_require_permission_review'], 1)

    def test_changed_history_owner_acl_and_missing_object_fail(self):
        for kind in ('history', 'relation', 'routine', 'role', 'constraint'):
            after = copy.deepcopy(self.after)
            next(r for r in after if r['kind'] == kind)['digest'] = 'modified'
            self.assertFalse(module.compare(self.before, after)['pass'])
        self.assertFalse(module.compare(self.before, self.after[1:])['pass'])

    def test_incomplete_or_duplicate_evidence_fails(self):
        self.assertFalse(module.compare([], [])['pass'])
        with self.assertRaises(ValueError):
            module.compare(self.before + [self.before[1]], self.after)
        self.after[-1]['missing_imported_chunks'] = 1
        self.assertFalse(module.compare(self.before, self.after)['pass'])

    def test_unvalidated_new_constraint_fails(self):
        self.after.append({'kind': 'constraint', 'name': 'new_fk', 'validated': False})
        self.assertFalse(module.compare(self.before, self.after)['pass'])


if __name__ == '__main__':
    unittest.main()
