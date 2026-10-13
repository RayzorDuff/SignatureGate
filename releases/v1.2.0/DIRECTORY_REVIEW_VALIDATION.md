# Company contacts and Cash Deposits access follow-up

## Accepted operator evidence

The operator reports `Cash reconciliation validation exit code: 0` at SignatureGate `50f4650` on `signaturegate_test`. Migration reapplication and rollback-only cash checks are accepted; no repeat manual negative-case matrix is requested. Exclude/Revive UI acceptance remains blocked by the reported Cash Deposits denial. The operator also reports inserting fourteen terminology concepts/defaults on test. Neither account values nor screenshots are copied into Git.

The selected Individual Profile shows assigned roles but no linked Appsmith account. That is not proof of the current signed-in account's canonical role ownership: the selected person can differ from the actor. No permission is inferred from a contact email, legacy flags or another individual's roles.

## Cash access repair and confidence

The page previously treated empty/loading/failed access results as a missing permission and combined two actor queries for visibility. All Cash Deposits database/API actions are explicitly Manual with Appsmith's deliberate-choice flag. The canonical lookup is invoked after sign-in readiness; cash tables and the bank lookup run only after the controller accepts its returned authority. Write and ERP actions remain explicitly invoked by their existing workflows. Display authority comes from the returned canonical result bound to the current account, with stale refresh results ignored. Unlinked, denied, loading and lookup-error states are distinct. Retry access remains available without exposing financial data. The read-only diagnostic returns only database identity and account/role booleans. It does not return names, contacts, account identifiers or financial records. Writes remain protected by their database APIs; no role is granted by this UI repair.

`tests/cash-deposit-access.mjs` covers empty cached query data, canonical staff without Participant capacity, unlinked/denied/mismatched accounts, errors/retry, out-of-order refresh, account changes and independent bank-lookup failure. Existing reconciliation/controller tests and actual prepared source SQL pass. Confidence is high for those contracts; the specific live account-link/role state and Appsmith SDK initialization still need observation.

## Company contact people

`company_contact_people.sql` adds explicit links from a company to existing individual identities. A company can have multiple contacts, and an individual can represent multiple companies. Directory Managers or Donations Reviewers may manage an accessible active company. Link/relink requires that the individual be in that actor's accessible Directory; a manager can select an identity without either capacity. Company-authorized reads expose linked names and relationship state, not private personal contacts, notes or date of birth. An existing relationship may be archived with company authority even if the individual's own profile is no longer accessible.

Each state change requires a reason and is audited atomically. Archive/reactivate retains the relationship ID. Full-precision text versions prevent stale changes without losing PostgreSQL microseconds in a JavaScript date conversion. These links grant no roles, Participant/Contributor capacity, individual-profile access, consent or ownership of the company's donations; they neither merge people nor copy contact methods.

Fresh schema bootstrap, migration application twice and `verify_company_contact_people.sql` pass in isolation. Covered cases include multiple/shared/standalone contacts, directory and archived-company boundaries, canonical nonmember managers/reviewers, disabled and legacy-flag denial, required reasons, duplicate/stale changes, exact audit count/actor and create/update rollback on audit failure. Actual prepared action tests prove one write/audit per composite-returning query. Controller tests cover route/profile/account changes, stale selection/version, blank reason, double click and singular write/refresh outcomes. Rendering and concurrent-session locking still need candidate acceptance; isolated sequential fixtures do not certify a concurrent PostgreSQL workload.

## Backend-first test sequence

```bash
cd ~/signaturegate
git pull --ff-only
bash releases/v1.2.0/validate_directory_review_test.sh
```

Expected `Directory review validation exit code: 0`. It hardcodes `signaturegate_test`, applies only the new provider and company migrations twice and runs rollback-only checks. Canonical authorization and the already-accepted cash revival migration are prerequisites. Stop on failure; keep raw logs private. This sequence replaces the provider-only command for this increment. Never bootstrap an existing database from `db/schema.sql`.

After success, preserve unsynchronized Appsmith editor work, pull `chatgpt_development`, then reload against the test datasource.

## Immediate high-risk manual check

Open **Cash Deposits** using the intended Donations Reviewer sign-in. If it opens, complete the previously requested synthetic Exclude → cancelled blank-reason Revive → reasoned Revive scenario. Return only pass/fail and the script exit code.

If it remains restricted, click **Retry access** and return the displayed **Access check (safe to return)** object. It contains only technical database identity and booleans. Do not rerun the Directory Manager bootstrap, infer ownership from an email contact or reassign a sign-in account merely to satisfy this check. An authorized manager should first verify the intended individual's account ownership and canonical role through the existing Individual Profile controls.

Company contact rendering and provider reassignment dialogs remain recorded candidate UI gaps. They are deferred to one consolidated later smoke check; no additional manual company/role/contact matrix is requested now. Production upgrade, external authorization and release promotion remain separately gated.


## Operator acceptance and successor sequence

At `8a08e74`, the operator reports this runner exit 0. Its backend checks are accepted; the completion-import warning is avoided by launching with `env -u 'BASH_FUNC__sudo%%' bash`. The final cash dialog scenario passes after access Retry. Do not repeat this runner or that scenario. Follow [INTAKE_PROGRESS_AND_ACCESS_VALIDATION.md](INTAKE_PROGRESS_AND_ACCESS_VALIDATION.md) for the remaining access/stage checks. Company-link/provider-dialog rendering remains a consolidated candidate gap.
