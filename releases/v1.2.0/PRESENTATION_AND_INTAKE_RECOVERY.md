# Presentation and interrupted Intake checkpoint

October 18, 2026. The operator accepts navigation across all pages. The operator subsequently reports all presentation and Intake completion/reload/reset observations below passing in the deployed development view. Form fields clear on reload while the persistent notice/submission guard remains; Reset clears that guard as intended. Do not repeat these accepted checks for unchanged code. No navigation matrix, object recreation, Console repair, prior SQL migration runner or production operation is requested by this increment.

## Published development changes

- Appsmith `4f37de2`: literal Contributor/Participant/Spiritual Practitioner table titles, correct independent Created/Updated dates in Agreement Templates and nine duplicate page-name headings removed.
- Appsmith `688de0b`: persistent account-scoped Intake review checkpoints, blocked ordinary replay after saved/uncertain outcomes, explicit review acknowledgment before resetting an interrupted intake, retained known agreement IDs and the tenth duplicate heading removed from inside Intake.
- Appsmith `bc527d3` adds the locked PGlite dependency and `npm test` runner; see the application `tests/README.md`. Its package version is not an application release/tag.

Column titles are intentionally readable literals in the supported Appsmith 2.4.2 title editor. Deployment defaults are centralized in `navigation/table-headings.json`; other supported UI captions remain configurable. A live terminology edit does not change these table titles. The former Created cell was a URL to the document, with a date expression as unbound display text. It is now a text-formatted timestamp; missing/invalid dates are blank and document URLs remain separate.

## Evidence and confidence

| Scope exercised automatically | Result / limit |
| --- | --- |
| All table-title contracts | 22 tables reject literal binding syntax; ten redundant page headings absent; section/access/identity headings retained |
| Template Created/Updated cells | Real expression evaluation of different timestamps, missing/null/invalid/empty vectors and independence from document URLs |
| Supported Intake | 24 actual-source SQL/controller enrollment/contact/consent cases pass in disposable PostgreSQL fixtures |
| Interrupted Intake | 32 injected failures before/after SQL action commits; lost-response, reload, ordinary replay, account isolation, reset acknowledgment and signing ID cases pass |
| Storage failure and signing failure | No first identity write without a saved checkpoint; failed signing keeps the known agreement ID; another submit does not replay the signing request |
| Navigation/access/profile/source invariants | Identity-preserving generation, on-load declarations, role/account/route and workflow-controller regressions pass; accepted all-page navigation is reused |
| Candidate export | 18 pages, 510 actions, 32 collections, four datasource descriptors and one library preserved exactly; packaged production JSON is not replaced |

The locked runtime is PGlite 0.5.8 (embedded PostgreSQL 18.3), exercised here with Node.js 24.19.0. It is not the installed PostgreSQL 16.13 cluster or its grants, data and upgrade history. HTTP is stubbed in controller checks. Native renderer/storage behavior, erased storage, different tabs/browsers, in-flight account changes, server atomicity/idempotency and external delivery retain independent gates.

## Accepted development validation sequence (historical)

1. Preserve/commit newer editor changes. Pull `SignatureGate-Appsmith/chatgpt_development` through `688de0b` or its later test-tooling descendant in the development editor, retaining the existing test datasource. No database migration is required.
2. Open Agreement Templates, Contributor Functions and Spiritual Practitioner Functions. Confirm headers are readable, Created/Updated show dates where values exist and the shared `Current page:` title has no duplicate standalone page-name heading. This is one cosmetic renderer observation; no permission or navigation matrix is requested.
3. If time permits, use an explicitly synthetic **Contributor-only** Intake on `signaturegate_test`, with mailing consent off. After successful completion, confirm Complete Intake is disabled and the completion/reset notice appears. Reload: the notice should remain and no additional identity, contact, agreement or external request should occur. Reset, then confirm the notice clears and the form is ready for a separate intake. Do not deliberately fail a real signing route. Interrupt/fault logic is already exercised automatically.
4. If the editor observations pass, use the normal development Deploy workflow while `chatgpt_development` remains selected, then make the same narrow observations in its deployed development view. A Git pull alone is not deployed publication. Production/master promotion remains a separate phase.

Return only pass/fail, page/stage and whether the observation was editor or deployed development. Keep screenshots, operational values, contact details, technical record IDs and raw logs private. Nothing from the synthetic record needs to be committed.

## Recovery semantics

The private checkpoint contains controlled stage text, version/owner and known technical IDs; it excludes form values and service responses. It is written before the first creation request because a timeout does not prove that a write failed. Missing replies retain an uncertain outcome. A normal completion also prevents accidental repeat submission until Reset.

For an interrupted intake, use Directory and the existing profile/functions to review contact methods, capacities, practitioner assignment and agreement status. The checkbox acknowledges that review before Reset starts a **separate** intake. Reset performs no record repair, deletion, rollback, signing resend or automatic action replay. A reviewer must finish the existing identity through authorized operations. If the browser checkpoint is unavailable, the database remains the source of truth; do not infer no record was saved.

A single database transaction/server idempotency boundary for creation remains a release design gate. The checkpoint is a mitigation and does not close it. Paper upload remains blocked until destination/principal validation. Legacy Intake remains until parity/retirement acceptance.


## Reproduce automatic checks

From a local development checkout of SignatureGate-Appsmith with SignatureGate beside it:

```bash
npm ci --ignore-scripts
npm test
```

This installs only the locked test dependency and runs disposable fixtures. It does not contact a Linode database or an integration endpoint. Node.js 22+ and Python 3 are prerequisites; this pass used Node.js 24.19.0. Use `npm run test:source` for source/controller checks without dependency installation. These commands are for developer reproducibility, not additional required operator/manual tests.
