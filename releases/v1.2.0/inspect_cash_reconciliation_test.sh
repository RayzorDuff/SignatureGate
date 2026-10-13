#!/usr/bin/env bash
# No writes; only technical names and whitelisted booleans/count leave the database.
set -euo pipefail
inspection_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$inspection_root"
umask 077
inspection_evidence="$HOME/signaturegate-release-evidence/v1.2.0/cash-state-observation"
mkdir -p "$inspection_evidence"
chmod 700 "$inspection_evidence"
trap 'inspection_result=$?; printf "Cash state inspection exit code: %s\n" "$inspection_result"' EXIT
git rev-parse HEAD > "$inspection_evidence/source-sha.txt"
sudo docker exec -i signaturegate-postgres \
  psql -X -qAt -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  < releases/v1.2.0/inspect_cash_reconciliation_test.sql \
  > "$inspection_evidence/summary.json" 2> "$inspection_evidence/inspection.log"
python3 - "$inspection_evidence/summary.json" <<'PY'
import json,sys
with open(sys.argv[1]) as stream: summary=json.load(stream)
expected={'database_name','comparison_scope','intake_contact_reuse_api_available','contributor_mailing_intake_api_available','available_exclusion_events','latest_two_exclusions_same_donation','verification_between_for_prior_donation','latest_exclusion_donation_is_verified','latest_exclusion_is_currently_active'}
assert set(summary)==expected
assert summary['database_name']=='signaturegate_test'
assert summary['comparison_scope']=='latest_two_cash_exclusions'
assert type(summary['available_exclusion_events']) is int and 0<=summary['available_exclusion_events']<=2
for key in expected-{'database_name','comparison_scope','available_exclusion_events'}:
    assert summary[key] is None or type(summary[key]) is bool
print(json.dumps(summary,indent=2,sort_keys=True))
PY
