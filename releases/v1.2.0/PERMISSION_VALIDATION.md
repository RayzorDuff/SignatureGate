# Test deployment and permission validation

Apply the backend increment to `signaturegate_test` before pulling the matching Appsmith development source. Existing `signaturegate` production remains unchanged. Do not run `db/schema.sql` on either existing database.

## Linode sequence

```bash
cd ~/signaturegate
git pull --ff-only
permission_evidence="$HOME/signaturegate-release-evidence/v1.2.0/permissions-increment"
mkdir -p "$permission_evidence"
chmod 700 "$permission_evidence"
umask 077
git rev-parse HEAD > "$permission_evidence/source-sha.txt"
(
  set -e
  for permission_pass in first repeat; do
    sudo docker exec -i signaturegate-postgres \
      psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
      < db/migrations/application_authorization.sql \
      > "$permission_evidence/migration-$permission_pass.log" 2>&1
  done
  for permission_check in verify_application_authorization verify_cash_deposit_confirmation_correction; do
    sudo docker exec -i signaturegate-postgres \
      psql -X -v ON_ERROR_STOP=1 -U signaturegate -d signaturegate_test \
      < "db/tests/$permission_check.sql" \
      > "$permission_evidence/$permission_check.log" 2>&1
  done
)
permission_result=$?
printf 'Permission validation exit code: %s\n' "$permission_result"
```

Stop on a nonzero result. Successful migration runs finish with COMMIT; both verification scripts finish with ROLLBACK. The migration makes no role grants, copies no configuration and creates no staff Participant capacities. It does create transitional actor references and change cash actor foreign-key targets; production requires the protected restore rehearsal.

## Appsmith sequence

1. Preserve unsynchronized editor work, pull `chatgpt_development`, then reload. Confirm the actual datasource is still `signaturegate_test`. Use separate viewer accounts and synthetic records. Do not change a production connection.
2. For each account, run this diagnostic through the same datasource. It returns booleans, rather than names, contacts or identity IDs:

```sql
SELECT is_document_reviewer, is_donations_reviewer,
       is_practitioner, is_directory_manager,
       member_id IS NOT NULL AS has_participant_capacity,
       can_intake, can_cash_deposits, can_contributor_functions,
       can_member_functions, can_practitioner_admin, can_release
FROM public.application_access({{ appsmith.user.email }})
```

3. Participant only: all staff flags are false. Intake, Cash Deposits, Contributor Functions and practitioner/release administration display denial with navigation still available. Member Functions selects only the owned active Participant and exposes read-only agreements/releases. Changing a route or selected UUID to another Participant yields no data. Direct Intake/cash/review actions are denied without writes.
4. Document Reviewer only, including one without Participant capacity: Member Functions and Facilitator Functions load. Anonymous pending cash records successfully. Eligible Participant-linked choices are shown and clearly labeled when Contributor capacity will be created. No organization-wide financial queue/deposits or cash verification is available. Sacrament Release remains denied without a practitioner appointment.
5. Donations Reviewer only, including one without Participant capacity: Contributor/anonymous cash entry, review and deposit creation/preparation/confirmation work. Check tally/print actor labels. Other document/practitioner permissions are not implied.
6. Practitioner only, without Participant capacity: assigned Participant workflows and cash entry are scoped; unassigned Participants and anonymous cash are denied. Select an assigned Participant whose selected practitioner has no storage grant: no products are loaded or displayed. With one synthetic explicit grant, only products from that location appear. Participant capacity itself does not own storage grants.
7. Validate a synthetic legitimate email containing `s`, plus-addressing or a subdomain. Check invalid formats and the optional blank-email phone/address path. Save/reload notes on the canonical identity. No partial write should occur from deterministic email validation.
8. Record one synthetic cash donation: exactly one success notification and one database record. A deliberately failed list refresh must yield a recorded-but-refresh-failed warning, not a write-failed message. Do not submit the same donation again to test recovery. Check cached flags and page data when switching accounts, role removal and disabled accounts.
9. Check denied-page navigation, narrow layouts, startup without automatic unauthorized API calls, action registration and Git pull/reload. Keep screenshots and detailed query outputs private; return pass/fail by step and error classes.

The isolated inventory [Code-node helper](../../n8n/INVENTORY_LOCATION_SCOPE.md) is a source candidate; the workflow export is unchanged. Do not overwrite the shared production workflow during these checks. The frontend now refuses empty scope and filters displayed products even with the currently published workflow. Integrate the helper only in an independently reviewed test route/environment, then include its empty/malformed-filter checks in Phase 5 deployment acceptance before final production promotion.

Paper evidence upload is temporarily disabled in this development increment. Confirm that the upload button is disabled and that no file request occurs. Destination ownership, authenticated caller permissions and private evidence handling must be validated before this feature is re-enabled and before release; see the review follow-up in [PERMISSION_REVIEW.md](PERMISSION_REVIEW.md).
