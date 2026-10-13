#!/usr/bin/env bash
# Test-only: initialize missing defaults and explicitly adopt audited Participant presentation.
set -euo pipefail
navigation_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$navigation_root"
umask 077
navigation_evidence="$HOME/signaturegate-release-evidence/v1.2.0/navigation-terminology"
mkdir -p "$navigation_evidence"
chmod 700 "$navigation_evidence"
navigation_stage=database_identity
trap 'navigation_result=$?; printf "Navigation terminology validation exit code: %s\n" "$navigation_result"; if (( navigation_result != 0 )); then printf "Failed stage: %s. Keep detailed logs private.\n" "$navigation_stage"; fi' EXIT
git rev-parse HEAD > "$navigation_evidence/source-sha.txt"
sudo docker exec -i signaturegate-postgres \
 psql -X -qAt -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
 -c 'SELECT current_database();' > "$navigation_evidence/database-name.txt" 2> "$navigation_evidence/database-check.log"
read -r navigation_database < "$navigation_evidence/database-name.txt"
[[ "$navigation_database" == signaturegate_test ]]
printf '%s\n' 'This test-only step adopts Participant presentation through the audited Directory Manager API.'
read -r -s -p 'Appsmith Directory Manager sign-in email (private input): ' navigation_actor_email
printf '\n'
[[ -n "$navigation_actor_email" ]]
for navigation_pass in first repeat; do
 navigation_stage="seed-$navigation_pass"
 sudo docker exec -i signaturegate-postgres \
  psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
  < db/seeds/organization_terminology.sql > "$navigation_evidence/seed-$navigation_pass.log" 2>&1
done
navigation_stage=audited_participant_label
sudo docker exec -i signaturegate-postgres \
 psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test -v admin_email="$navigation_actor_email" \
 < db/administration/adopt_participant_terminology.sql > "$navigation_evidence/adopt-participant.log" 2>&1
unset navigation_actor_email
navigation_stage=rollback_verification
sudo docker exec -i signaturegate-postgres \
 psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
 < db/tests/verify_participant_presentation.sql > "$navigation_evidence/verify-presentation.log" 2>&1
navigation_stage=complete
