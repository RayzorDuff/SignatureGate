# Unified Intake rollout and focused validation

October 19, 2026. The operator's Participant terminology adoption exits 0 on signaturegate_test at SignatureGate 4b697c9. Do not repeat that configuration command. Earlier deployed navigation, email validation, readable headers/dates, cash revival and completion/reset observations remain accepted.

## What changed

- Atomic Intake accepts an explicit **Create agreement later** choice, retaining two contacts and a practitioner assignment. Phone plus mailing address works without email. It creates no agreement or signing request and grants no release eligibility.
- The duplicate legacy Intake page, native application/menu entry and seventeen unused active-Intake write/helper/upload actions are retired after unified parity checks. Replace old Intake bookmarks with Directory or Intake.
- Duplicate feedback uses canonical reviewer authority without requiring Participant enrollment. The signing action is explicitly Manual; completion audit belongs only to the database transaction.
- The current development candidate contains 17 pages, 469 actions and 30 JS collections. Four datasource descriptors and the PDF library are retained. The production/master application and shipped JSON remain separate release artifacts.

## Automatic evidence and confidence

[CI run 39194685976](https://github.com/RayzorDuff/SignatureGate-Appsmith/actions/runs/39194685976) passes at Appsmith aca3d48 with backend/schema/runner d85fecb. The full source/controller/four disposable-SQL suites cover 24 existing and 18 deferred enrollments, independent consent/shared contacts, canonical duplicate access, 14 full rollback/retry boundaries, eight atomic request/lost-response cases, owner/payload/account isolation, receipt recovery, signing no-replay and reporting/permission/presentation contracts. Candidate export preservation also passes.

A second CI job executes the atomic contract/reapplication and four genuinely concurrent cases on **PostgreSQL 16.13**. It observes lock waits, then verifies commit/replay, rollback/retry, changed payload and changed owner: exactly one enrollment, receipt and completion audit survives each case. Its owned disposable database is removed. Seven lifecycle/barrier guard tests pass. These are high-confidence automatic checks; do not re-exercise their negative matrices manually. Installed ownership/grants, restored-production history/recovery and external delivery remain distinct gates.

## 1. Apply the current API to test before frontend pull

The operator has not yet returned this runner's result. On the Linode:

```bash
cd ~/signaturegate &&
git pull --ff-only &&
env -u 'BASH_FUNC__sudo%%' bash releases/v1.2.0/validate_atomic_intake_test.sh
```

Expected: **Atomic Intake validation exit code: 0**. The runner verifies signaturegate_test, applies only the current atomic migration twice and runs synthetic rollback-only contract checks. Logs remain private under ~/signaturegate-release-evidence/v1.2.0/atomic-intake-increment. Stop on failure before pulling the frontend. Do not run bootstrap over an existing database or initialize another Directory Manager. No .env loading or secret input is needed.

This repeats only the changed API contract. No new migration filename is added; the unreleased atomic source and draft manifest checksums are updated together. Test application/reapplication is not an instruction to replay it in production.

## 2. One high-risk native observation

After step 1 passes, preserve newer editor work and pull **chatgpt_development through aca3d48**, retaining the confirmed signaturegate_test datasource.

Use the existing authorized reviewer account for one explicitly synthetic **Participant-only** Intake with phone plus mailing address, no email, mailing consent off and **Create agreement later**. Select the intended test practitioner. Confirm progress/completion and **Check saved Intake** succeeds without another enrollment or signing request. SQL already verifies that this mode creates no agreement and grants no release eligibility; no separate manual release attempt or deliberate signing failure is requested.

During that same navigation, confirm there is only one Intake menu entry and the retired legacy page does not return. Existing page captions should now honor the already-adopted Participant setting. If the editor passes, use normal development Deploy on the same branch and confirm this narrow behavior there. Keep production/master unchanged.

Return only the runner exit code and pass/fail with editor/deployed-development mode. Keep names, contacts, addresses, record IDs, raw logs and screenshots private. The agent checks the subsequent native Git synchronization; no per-action inspection is requested. Previously pending Reports/new terminology-table observations can be supplied during ordinary use; no extra synthetic donation or broad role/navigation matrix is requested.

## Other release gates

The fresh PostgreSQL contention check is automatic in CI. [POSTGRES_INTAKE_VALIDATION.md](POSTGRES_INTAKE_VALIDATION.md) provides the optional same-server command if environment differences later require it; it is not an additional current manual request.

Protected paper upload, reviewed external principals/destinations and delivery, compatible released/deployed RootedOps/workflows, final production catalog/ownership/ordered upgrade/restore rehearsal, environment promotion and final export/version/tag provenance remain open. All 21 upgrade-draft dispositions and nine environment proofs remain undecided/false. No production SQL, datasource switch, master promotion or release tag is performed by this increment.
