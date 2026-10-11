#!/usr/bin/env python3
"""Behavioral checks for catalog comparison and credential-free summaries."""
import json
import unittest
from compare_database_inventories import KEYS, compare, indexed
from capture_release_services import summary, target


class ReleaseEvidenceTests(unittest.TestCase):
    def test_detects_effective_drift_and_ignores_statistics(self):
        canonical = {key: [] for key in KEYS}
        canonical['relations'] = [{'name': 'people', 'kind': 'r', 'estimated_rows': -1}]
        canonical['functions'] = [{'name': 'create_agreement_type', 'arguments': 'p_actor_email text', 'definition_hash': 'new'}]
        actual = {**canonical, 'relations': [{'name': 'people', 'kind': 'r', 'estimated_rows': 123}],
                  'functions': [{'name': 'create_agreement_type', 'arguments': 'p_actor_email text', 'definition_hash': 'old'}],
                  'views': [{'name': 'old_view', 'definition_hash': 'legacy'}]}
        rows = compare(canonical, actual, 'production')
        self.assertEqual(len(rows), 2)
        self.assertEqual({r['difference'] for r in rows}, {'changed', 'extra_in_deployed'})
        self.assertIn('definition_hash', next(r['changed_fields'] for r in rows if r['difference'] == 'changed'))
        self.assertTrue(all(r['disposition'] == 'pending_review' for r in rows))
        actual['functions'] = []
        self.assertIn('missing_in_deployed', {r['difference'] for r in compare(canonical, actual, 'test')})

    def test_duplicate_identities_rejected(self):
        with self.assertRaises(ValueError):
            indexed([{'name': 'duplicate'}, {'name': 'duplicate'}], ('name',))

    def test_workflow_summary_excludes_secrets_and_pinned_records(self):
        private = 'PRIVATE_FIXTURE_SECRET'
        rows = [{'id': 'workflow', 'name': 'Deposit sync', 'active': True, 'versionId': 'draft-v1',
                 'pinData': {'contacts': private}, 'staticData': {'token': private}, 'nodes': [
                     {'name': 'ERP request', 'type': 'n8n-nodes-base.httpRequest', 'parameters': {
                         'url': f'https://user:{private}@erp.example.test:443/api/method/sync?token={private}',
                         'headers': {'authorization': private}, 'body': private},
                      'credentials': {'httpHeaderAuth': {'id': 'credential-id', 'name': 'ERP API', 'data': private}}},
                     {'name': 'SQL', 'type': 'n8n-nodes-base.postgres', 'parameters': {'query': private}},
                     {'name': 'Dynamic URL', 'parameters': {'url': '={{ $env.ERPNEXT_INTERNAL_URL }}'}}]}]
        result = summary(rows, 'draft')
        serialized = json.dumps(result)
        self.assertNotIn(private, serialized)
        self.assertNotIn('pinData', serialized)
        self.assertEqual(result['workflows'][0]['nodes'][0]['target'], 'https://erp.example.test:443/api/method/sync')
        self.assertEqual(result['workflows'][0]['nodes'][0]['credentials']['httpHeaderAuth']['id'], 'credential-id')
        self.assertIn('review', result['workflows'][0]['nodes'][2]['target'])
        self.assertNotEqual(result['workflows'][0]['definition_sha256'], '')

    def test_dynamic_and_invalid_targets_require_review(self):
        self.assertIn('review', target('={{$env.URL}}'))
        self.assertIn('review', target('not a url'))
        self.assertEqual(target('https://example.test/path?secret=abc#fragment'), 'https://example.test/path')


if __name__ == '__main__':
    unittest.main()
