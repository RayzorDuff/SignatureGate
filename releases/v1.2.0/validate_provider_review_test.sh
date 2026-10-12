#!/usr/bin/env bash
# Test-only migration and rollback checks; logs stay outside the repository.
set -euo pipefail
validation_stage=setup
trap 'validation_result=$?; printf "Provider review validation exit code: %s\n" "$validation_result"; if (( validation_result != 0 )); then printf "Failed stage: %s. Retain detailed logs privately.\n" "$validation_stage"; fi' EXIT
validation_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$validation_root"
umask 077
validation_evidence="$HOME/signaturegate-release-evidence/v1.2.0/provider-review-increment"
mkdir -p "$validation_evidence"
chmod 700 "$validation_evidence"
git rev-parse HEAD > "$validation_evidence/source-sha.txt"
validation_stage=database_identity
sudo docker exec -i signaturegate-postgres \
  psql -X -qAt -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  -c 'SELECT current_database();' \
  > "$validation_evidence/database-name.txt" 2> "$validation_evidence/database-check.log"
read -r validation_database < "$validation_evidence/database-name.txt"
[[ "$validation_database" == signaturegate_test ]]
# Include the preceding cash increment so an unreported earlier run is not assumed.
for validation_migration in cash_donation_reconciliation_revive provider_donation_administration; do
  for validation_pass in first repeat; do
    validation_stage="$validation_migration-$validation_pass"
    sudo docker exec -i signaturegate-postgres \
      psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
      < "db/migrations/$validation_migration.sql" \
      > "$validation_evidence/$validation_migration-$validation_pass.log" 2>&1
  done
done
for validation_check in verify_provider_donation_administration verify_application_authorization \
  verify_cash_donation_reconciliation_revive verify_cash_deposit_confirmation_correction \
  verify_listmonk_contributor_email_support verify_membership_contributor_independence; do
  validation_stage="$validation_check"
  sudo docker exec -i signaturegate-postgres \
    psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
    < "db/tests/$validation_check.sql" \
    > "$validation_evidence/$validation_check.log" 2>&1
done
validation_stage=complete
