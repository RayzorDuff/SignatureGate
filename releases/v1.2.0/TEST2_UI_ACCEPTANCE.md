# Test2 UI acceptance checkpoint

Updated November 2, 2026. Production promotion remains on hold. This report contains sanitized release results only.

## Scope and preserved evidence

The existing development application was exercised through its installed Appsmith browser preview using synthetic records and an authorized linked staff account. Results below describe actual interface interactions, not a production deployment or complete integration certification.

The accepted development baseline is `ceb26ff02166d69ed0c64b0c77811f8b22164a67`, including merged Appsmith PR #7. Prior successful 47-check PostgreSQL suites, Appsmith CI, and focused former-Participant migration/rollback checks remain accepted historical evidence. They were not repeated. Prior source synchronization and backup checkpoints remain preserved; no synchronization recovery was repeated.

## Configuration results

| Check | Result | Evidence or limit |
| --- | --- | --- |
| Browser navigation and authenticated editor | PASS | Existing development application opens and responds to navigation, selection, form entry and writes. |
| Restricted development datasource | PASS | Saved development connection uses the existing restricted application role; Appsmith queries and synthetic writes authenticate successfully. No new credentials were generated. |
| Development n8n routing | PASS | Development workflow actions use the isolated test destination. The shared production destination was preserved. |
| Integration readiness | BLOCKED | Workflow activation and downstream signing, mailing, ERP and storage credentials/destinations are not certified. Workflows remain inactive. No production workflow was invoked. |
| Complete database isolation certification | BLOCKED | Successful restricted-role authentication is not proof of complete cross-database or routine isolation; the previously documented boundary limitation remains unresolved. |

## Actual browser acceptance

| Workflow | Result | Observed outcome |
| --- | --- | --- |
| Directory | PASS | Listed synthetic staff and both Intake records; search, contextual actions and View Profile worked. |
| Individual Profiles | PASS | Explicit selected identity, Participant/Contributor capacities, contacts and staff controls loaded. |
| Company Profile | PASS after focused fix | Opened a separately prepared synthetic organization from Directory; saved identity, linked an existing synthetic contact person and confirmed persistence after reload. A second rename verified the saved name remains in the input. Organization fixture creation itself is not claimed as a UI pass. |
| Reports | PASS after focused fix | Authorized staff without Participant enrollment could see report controls and execute a report returning metric rows. |
| Two consecutive Participant Intakes | PASS | Two separate synthetic enrollments committed, with an explicit reset between them. The second also enabled Contributor capacity. Both used enrollment-only agreement handling and disabled mailing subscriptions. |
| Intake recovery check | PASS | Check saved Intake confirmed the committed result without replaying enrollment or signing. |
| Former-Participant contact correction | PASS after focused fixes | Reviewer selected a retained email, an active target and a reason; reassignment succeeded. Source lost the transferred email and the target profile showed it, preserving its existing primary email. Other ended-enrollment contact writes stayed disabled. The former fixture was prepared separately through the existing audited lifecycle routine; lifecycle UI acceptance is not claimed. |
| Contributor identity | PASS | Contextual Contributor Functions selected the intended synthetic individual and showed the correct Contributor identity. |
| Cash entry and review | PASS | A synthetic contribution stored 1,234 cents and was verified through Cash Deposits, moving to Cash on Hand. |
| Draft deposit batching | PASS | Created one draft batch and added the verified contribution. The batch showed one item and 1,234 cents. |
| Contribution amount display | PASS after focused fix | Contribution history displayed 12.34 for 1,234 stored cents. |
| Pending Contribution list refresh and review | PASS after focused fix | A separate 56-cent contribution appeared in the pending queue, verified successfully and left that queue without a refresh failure. The original contribution was not replayed. |
| Final deposit preparation/confirmation and ERP | BLOCKED | Isolated bank-account selection returned no results. No final confirmation or ERP synchronization was attempted. |
| Agreement creation and review | BLOCKED | Selected Participant loaded, but agreement-type selection returned no results. Signing integration is not certified. No signing request was triggered. |
| Paper agreement upload and review | BLOCKED | Isolated storage credentials/destinations remain unverified. No file was uploaded. |

## Demonstrated defects and focused repairs

[Appsmith PR #8](https://github.com/RayzorDuff/SignatureGate-Appsmith/pull/8) contains the release fixes installed in development for acceptance:

- Canonical staff authorization for Reports visibility.
- Required reason/target inputs and target loading for former-Participant contact correction.
- Two-decimal contribution amounts preserving cents.
- Pending donation JSON lookup compatible with prepared SQL parameters.
- Company identity input retaining its newly saved name.

Targeted contact authorization/selection regression checks and a focused profile-loader check passed. Full automated suites were not repeated. PR #8 remains pending review and merge.

## Release blockers

1. Review/merge the focused UI repairs and confirm the accepted development source contains them.
2. Provide and verify isolated agreement templates, signing/mailing integrations, ERP bank-account data and paper-storage credentials; then complete the blocked browser workflows.
3. Resolve the previously recorded database access-boundary limitation before claiming complete isolation.
4. Remaining role-denial cases still require focused browser acceptance. Production promotion is not approved by this checkpoint.
