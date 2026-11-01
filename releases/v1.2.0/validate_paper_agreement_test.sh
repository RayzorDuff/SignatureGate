#!/usr/bin/env bash
# Test database only. Private logs; no production or external service operation.
set -euo pipefail
validation_stage=setup
trap 'validation_result=$?; printf "Paper agreement validation exit code: %s\n" "$validation_result"; if (( validation_result != 0 )); then printf "Failed stage: %s. Keep detailed logs private.\n" "$validation_stage"; fi' EXIT
validation_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$validation_root"
umask 077
validation_evidence="$HOME/signaturegate-release-evidence/v1.2.0/paper-agreement-increment"
mkdir -p "$validation_evidence"
chmod 700 "$validation_evidence"
git rev-parse HEAD > "$validation_evidence/source-sha.txt"
validation_stage=database_identity
sudo docker exec -i signaturegate-postgres \
 psql -X -qAt -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
 -c 'SELECT current_database();' > "$validation_evidence/database-name.txt" 2> "$validation_evidence/database-check.log"
read -r validation_database < "$validation_evidence/database-name.txt"
[[ "$validation_database" == signaturegate_test ]]
for validation_pass in first repeat; do
 validation_stage="migration-$validation_pass"
 sudo docker exec -i signaturegate-postgres \
  psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  < db/migrations/paper_agreement_upload.sql > "$validation_evidence/migration-$validation_pass.log" 2>&1
done
for validation_pass in first repeat; do
 validation_stage="storage-migration-$validation_pass"
 sudo docker exec -i signaturegate-postgres \
  psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  < db/migrations/paper_evidence_storage.sql > "$validation_evidence/storage-migration-$validation_pass.log" 2>&1
done
validation_stage=paper_behavior
sudo docker exec -i signaturegate-postgres \
 psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
 < db/tests/verify_paper_agreement_upload.sql > "$validation_evidence/verify-paper-agreement.log" 2>&1
validation_stage=storage_behavior
sudo docker exec -i signaturegate-postgres \
 psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
 < db/tests/verify_paper_evidence_storage.sql > "$validation_evidence/verify-paper-storage.log" 2>&1
validation_stage=complete
