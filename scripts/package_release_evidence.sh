#!/usr/bin/env bash
# Validate capture completeness and package evidence without closing the gate.
set -euo pipefail
release_evidence=${1:-"$HOME/signaturegate-release-evidence/v1.2.0"}
release_archive=${2:-"$HOME/signaturegate-v1.2.0-phase1-evidence.tar.gz"}
python3 - "$release_evidence" <<'PY'
import csv, hashlib, json, sys
from pathlib import Path
root = Path(sys.argv[1])
required = ['database-test.json', 'database-production.json', 'database-canonical.json',
            'database-differences.csv', 'deployed-services.json', 'operator-verification.md',
            'n8n-workflows-draft.json', 'n8n-publication-status.json',
            'configuration-signaturegate_test.jsonl', 'configuration-signaturegate.jsonl',
            'comparison-source-sha.txt', 'canonical-schema.sha256']
for name in required:
    assert (root / name).is_file() and (root / name).stat().st_size, f'Missing or empty: {name}'
for path in sorted(root.glob('*.json')):
    json.loads(path.read_text())
    print('JSON OK:', path.name)
for db in ['signaturegate_test', 'signaturegate']:
    path = root / f'configuration-{db}.jsonl'
    rows = [json.loads(line) for line in path.read_text().splitlines()]
    assert len(rows) == 3 and rows[0]['database'] == db, f'{path.name}: incomplete or wrong target'
    assert rows[1]['section'] == 'agreement_templates' and rows[2]['section'] == 'mailing_column_defaults'
    print('JSONL OK:', path.name)
publication = json.loads((root / 'n8n-publication-status.json').read_text())
if publication['published_export_supported']:
    assert (root / 'n8n-workflows-published.json').is_file(), 'Missing published workflow capture'
with (root / 'database-differences.csv').open(newline='') as stream:
    reader = csv.DictReader(stream)
    assert {'environment', 'object', 'disposition'} <= set(reader.fieldnames or []), 'Invalid comparison CSV'
    pending = sum(row['disposition'] == 'pending_review' for row in reader)
files = sorted(path for path in root.iterdir() if path.is_file() and path.name != 'SHA256SUMS')
(root / 'SHA256SUMS').write_text(''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n' for path in files))
print(f'Capture files valid; {pending} catalog differences pending review. Phase 1 is not closed.')
PY
tar -C "$(dirname -- "$release_evidence")" -czf "$release_archive" "$(basename -- "$release_evidence")"
ls -lh "$release_archive"
