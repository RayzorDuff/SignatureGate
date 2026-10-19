# Current v1.2.0 migration candidates

**Pending effective-definition review and restored-production rehearsal; not a production execution manifest.** The original `evidence/migrations.csv` is the initial source-audit snapshot. This document records changed/new candidates without rewriting that baseline. Only technical objects and source checksums are recorded here.

| Candidate | Current SHA-256 | Evidence / prerequisites | Verification / recovery |
| --- | --- | --- | --- |
| `agreement_type_administration.sql` | `574a862369297919a3d0b062acd9341ce6aaecc95edd01e139808939c6524abd` | Operator-reported test application/behavior pass; production API absent at capture. Requires canonical person roles/accounts, agreement types and audit log | `verify_agreement_type_administration.sql`; one transaction; restored-copy rehearsal before production |
| `party_identity_notes.sql` | `7c1737c58829913d34233ee0688000eff08ec3a0096579bd983b6ceac17fa6f3` | Test APIs present at capture; production missing both note columns/APIs. Provenance/helper now applied and behavior/reapplication verified on test; production still requires them. Requires canonical people/organizations/participants, directory/role helpers and audit log | `verify_party_identity_notes.sql`; explicit transaction, second-run check, Profile/`Intake` acceptance. Restore rehearsed backup for committed upgrade recovery; retain original source notes/provenance, do not delete/replay markers to force import |
| `organization_contact_reassignment.sql` | `305d14749513812f791fd6c69f1ce4725cd7f5f056ba0905e1fe78f26f3b54d9` | Production API absent; effective contact views match intended relational expressions; preserve existing definitions/grants | `verify_organization_contact_reassignment.sql` plus ownership cases; explicit transaction and restored-copy upgrade/recovery rehearsal |

| `member_agreement_reviewer_on_behalf.sql` | `5fe7bd6bdbb0f118d340a92351af384368ac6b4dfa63712174f410579f8651d9` | Production effective body is practitioner-only; test matches reviewer-on-behalf source. Requires canonical current actor, assignments, agreement tables and audit | `verify_member_agreement_reviewer_on_behalf.sql`; execute as a selected transaction; protected restored-copy rehearsal |

No order among these independent candidates is approved yet. Each must follow its canonical identity/contact/role prerequisites; do not replay overlapping cash or role migrations without effective-definition review. Reason-aware cash revival is now implemented and tested in isolation; live test application and restored-copy rehearsal remain required. Changed functions/views are dispositioned in LIVE_EVIDENCE_REVIEW.md. Exclusion/role bodies and contact expressions need no replacement; preserve the deployed date-correction trigger. Production agreement reviewer-on-behalf remains a candidate. Column-position-only differences require no column reordering.

Targeted definitions have been captured privately. Next: preserve reviewed owner/grant configuration, reconstruct the remaining forward changes, record a dependency-ordered production manifest with exact checksums and recovery, then rehearse it against a protected restored production copy. Raw records, definitions with operational literals and configuration mappings remain outside Git.

## Canonical authorization follow-up

`application_authorization.sql` SHA-256: `d3d417f45a4daf1e84ae76dee04ceb0b0c907c4a165ec36a6490d2a7238c7e5d`. Requires the reviewed canonical people/accounts/roles, Participant/contact/assignment models and cash lifecycle/ERP objects already present in test. Installs canonical role/resource helpers and audited application APIs; preserves cash actor UUIDs through a reference relation and retargets only cash actor foreign keys. No roles are copied from legacy flags. Fresh bootstrap, repeat application, role matrix and cash lifecycle/print/ERP/correction regressions pass in isolation. Operator reports successful test application twice and authorization/correction verification at 26531cf (exit 0), with permission/email/navigation UI acceptance. Preserve this evidence; production ordering/locks/grants and restored-copy recovery remain pending. Later canonical helpers must not be replaced by replaying older cash/financial migration definitions.

## Reason-aware reconciliation candidate

`cash_donation_reconciliation_revive.sql` SHA-256: `bebbeed63af2df38f90be5951a73536187575d98ecf9278e304285243ee7bfa2`. Requires `application_authorization.sql`, existing cash exclusion/lifecycle objects and audit log. Installs the reason-aware overload and fail-closed legacy signature in one transaction. Repeat application, required-reason/permission/state/conflict/history and atomic audit rollback tests pass in isolation. `validate_cash_reconciliation_test.sh` applies it only to test; protected production upgrade/grant/lock/recovery review remains pending.

## Canonical provider review candidate

`provider_donation_administration.sql` SHA-256: `ba0023c9323dbdbe40b4a133e9cde2bc864474201327e852d25108f41ae7592c`. Requires canonical application authorization, contributor/Participant/contact/provider models, mailing support, audit and cash batch-item state. Keeps legacy UUID signatures with canonical authorization, adds authenticated-account wrappers and atomic correction, and conservatively matches all contact candidates. No fake staff membership, role grants or identity merges are introduced. Fresh bootstrap, repeat application and targeted SQL/source/controller regressions pass; test application, live dialog and protected restored-copy owner/grant/locking/recovery review remain pending. Use `validate_provider_review_test.sh` only for test.

## Explicit company-contact relationship candidate

`company_contact_people.sql` SHA-256: `c92a846c4b73d9001786c9bd5e6a0779f98d6f75250400915d41c8030f74d05f`. Requires canonical people/organizations/contributors, account/role access, Directory visibility and audit. Adds a relationship table and guarded APIs without identity/capacity/consent backfill. Atomic migration/reapplication and relationship/source/controller checks pass in isolation. Test deployment uses `validate_directory_review_test.sh`; final production owner/grant/lock review and protected restore rehearsal remain pending.

Cash revival has operator-reported PostgreSQL 16.13 test evidence at `50f4650` (exit 0); its UI check is blocked by the cash-page access report. See DIRECTORY_REVIEW_VALIDATION.md.


Operator directory-review validation at `8a08e74` reports exit 0, accepting test provider/company application twice and the runner's rollback checks. Final Exclude/Revive UI is accepted; earlier pending-review display/state observation remains open. The workflow-feedback/access increment adds no migration. New Intake requires existing contact-role assignment and contributor-with-mailing APIs; the read-only inspection checks their availability. Production manifest/recovery gates remain unchanged.

## Atomic new-party Intake candidate

`atomic_intake.sql` SHA-256: `ff9f470b1562e67e58ae007e79e9e843b8ebcf3ad92ab8fe8d7f2de8b030b879`. Requires canonical authorization, notes, mailing, contact-purpose, practitioner and agreement helpers. Adds a private technical receipt and one transaction for new identities/capacities/contacts/assignment/pending digital agreement/audit/queue entries. Owner/key/payload replay returns the same receipt with no new writes; current role/account authority is rechecked. No HTTP or automatic signing retry. Fresh bootstrap, repeat application, 24 enrollment/replay cases, 14 fault/rollback/retry boundaries and validation/denial cases pass in isolated PostgreSQL. Runtime/grants/locking on PostgreSQL 16.13 and protected restored-production rehearsal remain open. Preserve existing receipts on reapplication; never load bootstrap over an existing database.

The unreleased atomic Intake API also accepts explicit `Later` agreement timing. It preserves two-contact and practitioner assignment requirements, returns a deferred receipt without an agreement, and never performs HTTP. Reapply the test-only runner before the corresponding frontend; the draft source/schema checksums are refreshed. The 18 added deferred SQL cases supplement the 24 existing cases and 14 rollback boundaries.
