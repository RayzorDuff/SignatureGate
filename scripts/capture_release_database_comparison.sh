#!/usr/bin/env bash
# Creates only a new disposable canonical database; never migrates live/test.
set -euo pipefail
release_repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
release_evidence=${1:-"$HOME/signaturegate-release-evidence/v1.2.0"}
release_database=${SG_VALIDATION_DB:-signaturegate_release_v1_2_0}
if [[ ! "$release_database" =~ ^signaturegate_release_v1_2_0(_[a-z0-9]+)*$ || ${#release_database} -gt 63 ]]; then
  echo 'Use a disposable database name beginning signaturegate_release_v1_2_0.' >&2
  exit 1
fi
mkdir -p "$release_evidence"
python3 - "$release_evidence" <<'PY'
import json, sys
from pathlib import Path
for env, name in [('test', 'signaturegate_test'), ('production', 'signaturegate')]:
    path = Path(sys.argv[1]) / f'database-{env}.json'
    value = json.loads(path.read_text())
    assert value['database'] == name, f'{path}: wrong database'
    assert value.get('functions') and value.get('columns'), f'{path}: incomplete capture'
    print(f'{env}: {name}, PostgreSQL {value["server_version"]}, captured {value["captured_at"]}')
PY
if [[ -e "$release_evidence/database-differences.csv" ]]; then
  echo 'Preserve database-differences.csv before regenerating a comparison.' >&2
  exit 1
fi
sudo docker exec signaturegate-postgres \
  createdb -U signaturegate --owner=signaturegate --template=template0 "$release_database"
# createdb fails if the name exists; no drop, overwrite or reuse is attempted.
if ! sudo docker exec -i signaturegate-postgres \
  psql -X -v ON_ERROR_STOP=1 -U signaturegate -d "$release_database" \
  < "$release_repo/db/schema.sql" > "$release_evidence/canonical-bootstrap.log" 2>&1; then
  tail -n 35 "$release_evidence/canonical-bootstrap.log" >&2
  echo "Bootstrap failed; $release_database is incomplete and must not be accepted." >&2
  exit 1
fi
# This separate connection proves the appended definitions survived disconnect.
sudo docker exec -i signaturegate-postgres \
  psql -X -v ON_ERROR_STOP=1 -U signaturegate -d "$release_database" <<'SQL'
DO $verify$
BEGIN
  IF to_regprocedure('public.create_agreement_type(text,text,text,integer,boolean,text)') IS NULL
     OR to_regprocedure('public.begin_cash_deposit_erp_sync(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Canonical bootstrap did not retain the release APIs';
  END IF;
END;
$verify$;
SQL
sudo docker exec -i signaturegate-postgres \
  psql -X -qAt -v ON_ERROR_STOP=1 -U signaturegate -d "$release_database" \
  < "$release_repo/releases/v1.2.0/capture_database_inventory.sql" \
  > "$release_evidence/database-canonical.json"
git -C "$release_repo" rev-parse HEAD > "$release_evidence/comparison-source-sha.txt"
sha256sum "$release_repo/db/schema.sql" > "$release_evidence/canonical-schema.sha256"
printf '%s\n' "$release_database" > "$release_evidence/canonical-database-name.txt"
python3 "$release_repo/scripts/compare_database_inventories.py" --evidence "$release_evidence"
