#!/usr/bin/env python3
"""Exercise the read-only CLI in normal and optimized Python; no database needed."""
import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = json.loads((ROOT / 'releases/v1.2.0/UPGRADE_MANIFEST_DRAFT.json').read_text())


class ManifestChecks(unittest.TestCase):
    def run_case(self, manifest, accepted, message=None):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'manifest.json'
            path.write_text(json.dumps(manifest))
            for flags in ([], ['-O']):
                with self.subTest(optimized=bool(flags), message=message):
                    result = subprocess.run(
                        [sys.executable, *flags, str(ROOT / 'scripts/validate_upgrade_manifest.py'), str(path)],
                        capture_output=True, text=True,
                    )
                    if accepted:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(json.loads(result.stdout), {
                            'steps': 21, 'undisposed_steps': 21,
                            'unverified_environment_gates': 9, 'executable': False,
                        })
                    else:
                        self.assertNotEqual(result.returncode, 0)
                        self.assertEqual(result.stdout, '')
                        self.assertIn(message, result.stderr)
                        self.assertNotIn('Traceback', result.stderr)

    def test_current_draft(self):
        self.run_case(BASE, True)

    def test_invalid_drafts(self):
        cases = [
            ('state', 'executable', 'planning drafts only'),
            ('canonical_schema_sha256', '0' * 64, 'Canonical schema checksum changed'),
            ('steps', [], 'nonempty list'),
            ('steps', None, 'nonempty list'),
            ('required_environment_proofs', {}, 'proof inventory changed'),
        ]
        for field, value, message in cases:
            draft = copy.deepcopy(BASE)
            draft[field] = value
            self.run_case(draft, False, message)
        self.run_case([], False, 'Manifest must be an object')
        for field, value, message in [
            ('sha256', '0' * 64, 'Source checksum changed'),
            ('after', ['application_authorization'], 'out-of-order prerequisite'),
            ('after', None, 'Invalid prerequisites'),
            ('path', '../outside.sql', 'Path escapes repository'),
            ('path', 'db/not_present.sql', 'Missing source'),
            ('preconditions', 'reviewed', 'Incomplete review entry'),
            ('verification', [''], 'Incomplete review entry'),
            ('transaction', '', 'Incomplete review entry'),
            ('recovery', True, 'Incomplete review entry'),
            ('selected', 0, 'Invalid selection disposition'),
            ('selected', 1, 'Invalid selection disposition'),
            ('selected', True, 'lacks reviewed evidence'),
            ('selected', False, 'lacks reviewed evidence'),
        ]:
            draft = copy.deepcopy(BASE)
            draft['steps'][0][field] = value
            self.run_case(draft, False, message)
        draft = copy.deepcopy(BASE)
        draft['steps'].append(draft['steps'][0])
        self.run_case(draft, False, 'Duplicate upgrade step')
        draft = copy.deepcopy(BASE)
        del draft['steps'][0]['selected']
        self.run_case(draft, False, 'Missing selection disposition')
        draft = copy.deepcopy(BASE)
        draft['steps'][0].update(selected=True, disposition_evidence=True)
        self.run_case(draft, False, 'lacks reviewed evidence')
        draft = copy.deepcopy(BASE)
        draft['steps'] = [step for step in draft['steps'] if step['id'] != 'application_authorization']
        for step in draft['steps']:
            step['after'] = []
        self.run_case(draft, False, 'Missing canonical authorization step')
        draft = copy.deepcopy(BASE)
        del draft['required_environment_proofs']['backup_restore_verified']
        self.run_case(draft, False, 'proof inventory changed')
        draft = copy.deepcopy(BASE)
        draft['required_environment_proofs']['backup_restore_verified'] = 1
        self.run_case(draft, False, 'must be booleans')
        # Even clearing prerequisites cannot place a legacy overwrite after auth.
        draft = copy.deepcopy(BASE)
        for step in draft['steps']:
            step['after'] = []
        draft['steps'].append(draft['steps'].pop(0))
        self.run_case(draft, False, 'would overwrite canonical authorization')


if __name__ == '__main__':
    unittest.main()
