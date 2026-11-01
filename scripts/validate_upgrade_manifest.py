#!/usr/bin/env python3
"""Read-only validation of pinned source/order/dispositions; never executes SQL."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENVIRONMENT_PROOFS = {
    'canonical_base_and_missing_forward_changes_reviewed',
    'current_production_effective_definitions_reviewed',
    'staff_account_ownership_and_roles_reviewed',
    'owners_grants_and_data_invariants_reviewed',
    'backup_restore_verified',
    'worker_and_external_destination_isolation_verified',
    'restored_copy_rehearsal_passed',
    'released_deployed_rootedops_and_workflows_pinned',
    'production_datasource_and_published_revision_verified',
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def text(value):
    return isinstance(value, str) and bool(value.strip())


def text_list(value):
    return isinstance(value, list) and bool(value) and all(text(item) for item in value)


def validate(manifest, root=ROOT):
    root = Path(root).resolve()
    require(isinstance(manifest, dict), 'Manifest must be an object')
    require(manifest.get('state') == 'draft_non_executable',
            'This validator supports planning drafts only')
    schema = root / 'db/schema.sql'
    require(schema.is_file(), 'Missing canonical schema')
    require(hashlib.sha256(schema.read_bytes()).hexdigest() == manifest.get('canonical_schema_sha256'),
            'Canonical schema checksum changed')
    steps = manifest.get('steps')
    require(isinstance(steps, list) and bool(steps), 'Steps must be a nonempty list')
    seen = set()
    for step in steps:
        require(isinstance(step, dict) and text(step.get('id')), 'Invalid upgrade step')
        step_id = step['id']
        require(step_id not in seen, 'Duplicate upgrade step: ' + step_id)
        after = step.get('after')
        require(isinstance(after, list) and all(text(item) for item in after),
                'Invalid prerequisites: ' + step_id)
        require(set(after) <= seen, 'Unresolved or out-of-order prerequisite: ' + step_id)
        require('selected' in step, 'Missing selection disposition: ' + step_id)
        selected = step['selected']
        require(selected is None or type(selected) is bool, 'Invalid selection disposition: ' + step_id)
        if selected is not None:
            require(text(step.get('disposition_evidence')),
                    'Selected/skipped step lacks reviewed evidence: ' + step_id)
        require(text(step.get('path')), 'Invalid source path: ' + step_id)
        path = (root / step['path']).resolve()
        require(path.is_relative_to(root), 'Path escapes repository: ' + step_id)
        require(path.is_file(), 'Missing source: ' + step['path'])
        require(hashlib.sha256(path.read_bytes()).hexdigest() == step.get('sha256'),
                'Source checksum changed: ' + step['path'])
        require(text_list(step.get('preconditions')) and text_list(step.get('verification'))
                and text(step.get('recovery')) and text(step.get('transaction')),
                'Incomplete review entry: ' + step_id)
        seen.add(step_id)
    # Older files define overlapping helpers; authorization must follow them.
    require('application_authorization' in seen, 'Missing canonical authorization step')
    auth = next(i for i, step in enumerate(steps) if step['id'] == 'application_authorization')
    for i, step in enumerate(steps):
        if step['id'].startswith('legacy_cash_') or step['id'] == 'legacy_financial_scope':
            require(i < auth, 'Legacy helper would overwrite canonical authorization')
    gates = manifest.get('required_environment_proofs')
    require(isinstance(gates, dict) and gates.keys() == ENVIRONMENT_PROOFS,
            'Required environment proof inventory changed')
    require(all(type(value) is bool for value in gates.values()),
            'Environment proofs must be booleans')
    return {
        'steps': len(steps),
        'undisposed_steps': sum(step['selected'] is None for step in steps),
        'unverified_environment_gates': sum(not value for value in gates.values()),
        'executable': False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(validate(json.loads(args.manifest.read_text())), indent=2))
    except (ValueError, OSError) as error:
        raise SystemExit(str(error))


if __name__ == '__main__':
    main()
