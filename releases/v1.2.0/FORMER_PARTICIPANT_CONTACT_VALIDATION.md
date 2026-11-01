# Former Participant contact correction

Issue [#14](https://github.com/RayzorDuff/SignatureGate/issues/14) includes correcting contact ownership after a Participant enrollment has ended. The prior person-reassignment test verified only function/trigger existence. The new behavioral fixture fails against the previous canonical function with `Active membership not found for source individual`.

The forward change `db/migrations/person_contact_reassignment.sql` permits an inactive source Participant enrollment. The target must be active, the contact must be active and belong to the stated source, the actor must have an active canonical Document Reviewer account, and a reason is required. It does not reactivate enrollment, grant roles or privileges, alter Contributor authority or move a separate Contributor-purpose contact. Missing capacity/contact-kind values are rejected explicitly.

The Appsmith change modifies existing widget bindings only. It enables contact selection/reassignment for an authorized reviewer viewing a former Participant, retains active-target filtering and leaves add/archive/primary/verification/subscription writes disabled for ended enrollment. Navigation JS objects, datasource IDs and action IDs are preserved. This completes the reassignment part of #14; broader collision messaging, shared household/contact policy and historical archive behavior are separate acceptance items.

## Merged checkpoint — November 1, 2026

Backend PR [#32](https://github.com/RayzorDuff/SignatureGate/pull/32) is merged on SignatureGate main at `4cc849d5f759b623aff14d6f52b7b2c1c742bd60`. Appsmith PR [#7](https://github.com/RayzorDuff/SignatureGate-Appsmith/pull/7) is merged on `chatgpt_development` at `ceb26ff02166d69ed0c64b0c77811f8b22164a67`.

The [backend native PostgreSQL 16.15 run](https://github.com/RayzorDuff/SignatureGate/actions/runs/41323473168) passed both migration applications and all 47 checks twice. Both [Appsmith CI jobs](https://github.com/RayzorDuff/SignatureGate-Appsmith/actions/runs/41345829361) passed, including native PostgreSQL concurrency. Local application checks, manifest checks and exact-source temporary export preservation passed. All five changed widgets retain their native identities and other properties; only disabled-state bindings differ.

No shared Test2 or production database migration, saved datasource change, application publication or shared service operation has been performed for this increment. The single native check below remains pending coordinated test deployment. Issue #14 remains open for broader collision messaging, historical archive behavior and policy acceptance.

## Automated confidence

- `verify_person_contact_reassignment.sql` moves email, phone and address with stable domain contact IDs, canonical target ownership and cleared primary flags; preserves the source Contributor-purpose email/canonical owner and inactive enrollment; rejects wrong-role/disabled actors, blank reason, missing capacity, inactive targets and stale-source retries; checks exactly three audits and forces deferred constraints before rollback.
- The canonical PostgreSQL 16 workflow reapplies the forward change twice, then runs all 47 SQL checks twice with persistent-data comparison after every check. Check the PR's actual native result before claiming that gate passed.
- `former-participant-contacts.mjs` evaluates saved widget expressions for active/inactive/read-only/cross-capacity cases, required selection/reason/busy guards, allowed active targets and unchanged restrictions on other maintenance actions. Full source/controller/isolated SQL checks remain required.
- `validate_upgrade_manifest.py` continues to reject executable manifests; this is a new undecided forward step. Production definition, owner/grant and protected restore/rehearsal proofs remain open.

## Focused shared Test2 sequence

No host migration or UI acceptance is claimed by source CI. Wait for the shared console to be available, acquire `~/bin/test2-console-lock signaturegate` and use the separate SignatureGate Screen session. Coordinate Appsmith/datasource changes independently of the console lock.

1. Verify the actual test-only PostgreSQL container and dedicated `signaturegate_test` database. Verify Appsmith uses the restricted `signaturegate_test_app` principal on that destination. Do not change production or use a restored production-origin API.
2. Pull the merged backend and Appsmith development revisions. In the dedicated test database only, use owner maintenance access to apply `db/migrations/person_contact_reassignment.sql` twice, then run `db/tests/verify_person_contact_reassignment.sql` with `psql -X -v ON_ERROR_STOP=1`. Preserve logs privately; return only pass/fail and technical error details. Never grant owner/DDL access to the Appsmith principal.
3. One high-risk native check: with synthetic individuals only, view a former Participant as Document Reviewer and move one retained contact to a different active Participant with a reason. Confirm the target owns it, the former enrollment stays inactive, and the audit identifies the correction. Other contact-maintenance buttons should remain disabled. No repeat manual email/phone/address matrix is requested after automatic checks pass.
4. Release the console by exiting the locking shell. Keep production rollout on its reviewed migration/recovery schedule after testing.
