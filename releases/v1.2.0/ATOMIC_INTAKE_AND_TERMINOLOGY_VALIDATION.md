# Atomic Intake and terminology validation

October 18, 2026. Prior deployed presentation, staged feedback, completion/reload/reset and all-page navigation results are accepted. Do not repeat those matrices. This increment changes the database write boundary and adds terminology controls; it introduces one test migration and a narrow runtime observation.

## Published checkpoints and behavior

- SignatureGate `ad6cf01`: `atomic_intake.sql`, rollback-only tests and a test-only migration runner. The draft upgrade manifest now has 21 undecided entries (20 migrations plus Participant configuration) and nine unverified proofs; it is not executable.
- Appsmith `e0eb001`: the active Intake page uses the atomic API, persists its UUID request key and can inspect a committed receipt without replaying enrollment or signing.
- Appsmith `1a73856`: Select captions/placeholders, Directory per-row Participant/Contributor buttons, profile contact copy, manager-only terminology structure table and label-query refresh after saving.
- SignatureGate `3ed59e4`: obsolete standalone `appsmith/Terminology Administration.json` removed. Split Appsmith source is authoritative until final coordinated export packaging.

Identity, capacities, contacts, notes, practitioner assignment, the pending digital agreement, completion audit and mailing queue entries commit together. Owner/key/payload replay returns the same technical receipt. Invalid or failed database transactions leave no partial enrollment. Progress describes committed database stages after that call. Signing runs afterward with the saved agreement ID; a failed/uncertain HTTP response still requires delivery reconciliation. No automatic signing retry occurs. Legacy Intake remains a separate parity/retirement gate.

## 1. Apply and exercise the new API on test first

On the Linode:

```bash
cd ~/signaturegate
git pull --ff-only
env -u 'BASH_FUNC__sudo%%' bash releases/v1.2.0/validate_atomic_intake_test.sh
```

Expected: `Atomic Intake validation exit code: 0`. The runner verifies `signaturegate_test`, applies only `atomic_intake.sql` twice and runs synthetic rollback-only behavior checks. Logs and source provenance stay private under `~/signaturegate-release-evidence/v1.2.0/atomic-intake-increment`. Stop on failure before pulling/publishing the frontend. Do not run bootstrap or the migration inventory over either existing database.

Automatic coverage: 24 enrollment/replay combinations; independent mailing consent and shared contacts; optional individual DOB/identity notes; 14 complete rollback/retry boundaries including late agreement, contributor-queue and final-audit failures; malformed input, role/account/owner/payload conflicts and read-only receipt recovery. These are actual SQL semantics in isolated PostgreSQL and become PostgreSQL 16.13 execution evidence when this runner succeeds on the Linode. Multi-session lock scheduling and restored-production owner/grant/data/upgrade behavior remain separate rehearsal checks.

## 2. Adopt the requested Participant wording if the installed label is still Member

The shared UI formatter honors installed configuration. The operational Participant enrollment key is **member**. The separate **participant** key is a reserved event-participation concept. Reapplying a seed does not overwrite old installed labels.

For this test installation, the existing audited adoption runner performs the requested Participant change:

```bash
env -u 'BASH_FUNC__sudo%%' bash releases/v1.2.0/validate_navigation_terminology_test.sh
```

Enter the intended Appsmith Directory Manager sign-in at the hidden prompt, without SQL quotes. Expected: `Navigation terminology validation exit code: 0`. This seeds missing defaults without changing installed practitioner/Contributor overrides, explicitly sets only `member` to Participant/Participants/Participant through the Directory Manager API and runs rollback-only presentation checks. It grants no roles and changes no operational people or executed agreements. It targets only `signaturegate_test`.

Alternatively, once the new administration table is available, inspect the `member` row and use the existing form to save Participant/Participants with a reason. Do not edit/activate the reserved `participant` row to rename enrollment. A deliberately chosen alternate member or Contributor label remains valid and should be honored.

## 3. Pull and observe the development candidate

Only after step 1 passes, preserve newer editor work and pull Appsmith **chatgpt_development through `1a73856`**. Keep the confirmed `signaturegate_test` datasource. The new API has no fallback to the old multi-action writes. Development Deploy remains separate from production/master promotion.

The remaining high-risk runtime check is one explicitly synthetic **Contributor-only Intake**, mailing consent off. Confirm progress/completion, then use **Check saved Intake**: it should confirm the committed enrollment without another identity or signing request. Reload/reset behavior should retain the already-accepted semantics. Do not deliberately fail a real signing endpoint; response-loss/no-replay cases are exercised automatically.

During ordinary navigation, inspect Terminology Administration's new table and the reported captions/buttons: practitioner and Participant selectors, Directory Participant/Contributor buttons, Individual contact capacity/note and Company contact note. The table shows every active/reserved concept, kind, singular/plural/short label, state and description as read-only text. Directory Manager authority is required to show the administration view. Save refreshes the table and the current-page navigation label query. No role, contact, permission or donation matrix is requested.

If editor observations pass, use the normal Deploy flow while **chatgpt_development** remains selected and confirm the same narrow observations there. Return only exit codes and pass/fail with editor/deployed mode. Keep identities, contacts, technical record IDs, raw logs and screenshots private. The agent will inspect the subsequent native Git synchronization for preserved identities/modes/bindings; do not manually inspect every action.

## Confidence and remaining limits

The complete `npm test` source/controller/four disposable-SQL suites pass. Controller cases exercise 24 supported intakes and eight atomic-request/lost-response cases, owner-scoped lookup, absent/in-flight receipt handling, legacy browser checkpoints, signing failure and no automatic replay. Generation and rendering-expression tests exercise native `labelText`, table button vectors, profile labels and alternate Participant/practitioner/Contributor terminology. Internal capacity values and executed records are unchanged. Table column titles remain literal deployment defaults because of the Appsmith 2.4.2 title-editor contract; configurable cell buttons and supported captions remain dynamic.

A missing receipt is not proof that an in-flight transaction failed. Keep the browser guard and review before a separate intake. Clearing browser storage or using another request key does not establish delivery outcome. Production remains gated by deployed principals/destinations, protected paper upload, external delivery/ERP/RootedOps acceptance, legacy parity/retirement, a selected ordered upgrade manifest, protected restore/rehearsal, environment review and final published export/version/tag provenance. No production change is performed by these commands.
