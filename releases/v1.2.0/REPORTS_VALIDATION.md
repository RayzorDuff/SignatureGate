# Reports and configured page-name validation

Current successor: [UNIFIED_INTAKE_VALIDATION.md](UNIFIED_INTAKE_VALIDATION.md). The operator reports Participant adoption exit 0; do not repeat that configuration command. Apply the updated atomic API before pulling the unified development candidate. Earlier checkpoint instructions below are retained as provenance.

October 19, 2026. Supersedes the earlier broad manual role/category checklist. The operator's accepted navigation and permissions are reused. This increment changes the saved report query/controller/presentation; it introduces no migration and grants no access.

## Definitions

| Metric | Definition |
| --- | --- |
| Participants created | Participant capacity created-at within the bucket, independent of person creation. Ending enrollment does not erase this creation event. Document Reviewers see all; practitioners retain current assigned-Participant scope. |
| Contributors created | Individual/company Contributor capacity created-at, independent of person/company creation or donations. Archived/merged capacities retain creation history. Donations Reviewer required. |
| Contributor-linked donations | Explicit Contributor attribution, combining individual and company Contributors without requiring Participant capacity. These count/value metrics are in the default authorized selection. |
| Participant-linked donations (subset) | An optional overlapping subset: an individual Contributor's person currently has active Participant capacity. It is a present relationship filter, not a historical status snapshot. Do not add it to Contributor/overall totals. |
| Anonymous / unresolved donations | Separate unattributed categories retained alongside Contributor attribution. |

Existing verified/imported/pending-review donation status inclusion and rejected exclusion remain. Dates use donated-at with created-at fallback; capacity counts use their own created-at. Contributor-linked plus anonymous plus unresolved reconciles to overall donations in valid canonical attribution; individual plus company reconciles to Contributor-linked. A dual-capacity person contributes once to each applicable capacity metric. Dollars and counts are different measures.

Metric choices, chart names and table row labels use configured terminology. Technical compatibility keys are hidden in the visible table; old retained selections normalize to Participant keys. Menu entries/current-page titles for stable Member Functions and Contributor Functions routes likewise use configured singular labels. These route identifiers are not display labels.

## Automatic confidence

The application regression suite exercises actual saved SQL and source controller/widget expressions using synthetic data. New assertions cover Contributor reconciliation, both creation metrics/date buckets, dual capacities, ended/archived history, rejected exclusions, old selections, direct unauthorized requests, assignment scope, removed/disabled access, alternate terminology and account-switch table isolation. Saved navigation labels are evaluated on every page and destination titles are tested with alternate Participant/Contributor configuration.

The development-checks workflow runs the full source/controller/four disposable-SQL suites with a pinned SignatureGate schema SHA. The current run and result are recorded in STATUS.md. Fresh embedded PostgreSQL tests do not certify the real PostgreSQL 16 owners/grants, restored upgrade or native Appsmith renderer. No operational evidence is committed.

## Only the remaining manual observation

1. After automated checks pass, preserve newer editor work and pull the accepted Appsmith `chatgpt_development` candidate, retaining `signaturegate_test`. The preceding atomic Intake prerequisite still applies if it has not been activated; see [the backend-first sequence](ATOMIC_INTAKE_AND_TERMINOLOGY_VALIDATION.md).
2. If Terminology Administration's operational **member** row still says Member, adopt Participant explicitly through its reasoned save or the existing Linode command:

   ```bash
   cd ~/signaturegate
   git pull --ff-only
   env -u 'BASH_FUNC__sudo%%' bash releases/v1.2.0/validate_navigation_terminology_test.sh
   ```

   Enter the intended Directory Manager sign-in at the hidden prompt without SQL quotes. Expected: `Navigation terminology validation exit code: 0`. The runner targets only test, preserves practitioner/Contributor overrides and changes no roles or executed agreements. Do not rename the reserved event `participant` row.
3. During one normal development navigation, confirm **Participant Functions** in the menu/current-page title and the configured Contributor equivalent. With the existing multi-role reviewer, open Reports and run a range containing known test enrollments. Confirm readable **Participants Created**, **Contributors Created** and **Contributor-linked donations** choices/results. Participant-linked should be available as a separate, unselected subset. Keep counts/record data private; return pass/fail and editor/deployed-development mode.

No real enrollment needs to be ended/archived, no new donation or endpoint failure is requested, and no repeated broad role/navigation matrix is needed. If editor rendering passes, the normal development Deploy check uses the same narrow observation; this is not production/master promotion.
