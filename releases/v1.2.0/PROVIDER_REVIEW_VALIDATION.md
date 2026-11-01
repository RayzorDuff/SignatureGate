# Canonical provider review increment

Provider resolution, contributor creation and reassignment now authorize canonical Donations Reviewers without requiring Participant capacity. Legacy reviewer UUID APIs retain their signatures and use the canonical owner; legacy flags cannot grant authority. The nullable legacy `reviewer_id` is populated only when an active Participant record exists, while the atomic audit always records the canonical person/account.

New contributor creation blocks existing or ambiguous contact/provider identities instead of making another party. Automatic matching considers all email/phone candidates together; shared or contradictory contacts stay unresolved. An established active provider binding remains authoritative. Historical bindings require explicit review. Explicit existing-party resolution preserves provider-identity uniqueness and rolls back conflicting contact/binding writes.

New Participant creation is an explicit dual-capacity operation requiring Directory Manager, Document Reviewer and Donations Reviewer permissions, consistent with Intake. It requires two contact methods and uses one shared person for the new Participant and Contributor. Companies receive no Participant capacity. No staff roles/accounts/appointments are granted. Participant mailing consent is explicit and does not subscribe the Contributor list.

Reassignment requires a correction reason and audits actual before/after attribution in the same transaction. It preserves financial amounts, currency, provider reference, review state and provider bindings. Donations in an active deposit batch cannot be reassigned; confirmed accounting history is not silently rewritten. The UI captures the clicked row and preserves cents in its display. Cancel, account changes, revoked roles, repeated clicks and committed-refresh failures have controller coverage. Redundant client audit writes were removed from reviewed mutation paths.

## Confidence and evidence

`verify_provider_donation_administration.sql` passes on the isolated canonical database, including nonmember/legacy-flag authority, existing/new individual/company choices, shared-person enrollment, duplicate/ambiguous/provider conflicts, mailing independence, financial-history preservation, active-batch protection and audit-failure rollback. Migration application twice passes. Authorization, cash revival/lifecycle/correction, mailing and capacity-independence regressions pass. Actual source SQL is executed with prepared bindings, including denied and combined-role enrollment cases. Controller, execution-setting, syntax and source/export preservation checks pass.

Confidence is high for these exercised SQL/controller contracts. Live PostgreSQL 16 application and the changed reassignment dialog still need integration evidence. SQL permission tests assume the supplied canonical account identity and validate the shipped action bindings; Appsmith execution-principal trust and external endpoint authentication remain separate deployment review boundaries. No production migration, master promotion or external workflow publication occurs here.

Provider implementation is now published at Appsmith `8b1208e` / backend `03a6be4`; the preceding observed editor synchronization baseline was `cce43f3`. No later post-pull system commit was observed, so persistence of pinned execution settings is not yet accepted. The agent will inspect the next synchronization commit; no manual audit of every query is requested.

## Test deployment

```bash
cd ~/signaturegate
git pull --ff-only
bash releases/v1.2.0/validate_provider_review_test.sh
```

Expected exit code **0**. Stop on failure and keep detailed logs private. The script targets only `signaturegate_test`, applies the pending cash-revival and provider migrations twice, and runs rollback-only checks. Canonical application authorization must already be installed; the prior successful operator authorization run satisfies that prerequisite. Do not run `db/schema.sql` on an existing database.

After success, preserve unsynchronized editor work, pull Appsmith `chatgpt_development` and reload against test.

## One high-risk UI check

As a Donations Reviewer, use a disposable synthetic donation outside any deposit batch and a synthetic active contributor. Open **Reassign** from that row, including when another row is selected. The dialog must show the clicked record and cents accurately; blank reason disables confirmation and Cancel makes no change. Reopen, choose the target and type a synthetic correction reason. Confirm changes only the intended donation's attribution with one success notification; its amount/currency/date remain unchanged.

No hand-crafted negative SQL or repeated permission/email matrix is requested. Provider matching, duplicate creation, identity preservation, role denial, direct calls, atomic audit, mailing isolation, double clicks and refresh-failure logic are covered automatically. The prior Exclude/Revive dialog check remains pending unless the operator confirms it; it need not be repeated if already passed. Return script exit code and changed-dialog pass/fail/error class without operational records, contacts, amounts or screenshots.

The subsequent DIRECTORY_REVIEW_VALIDATION.md sequence includes these provider prerequisites and the company-contact increment. Use that combined sequence now. The cash backend check has passed live at 50f4650; its UI check is specifically blocked by the reported Cash Deposits denial, rather than an unreported result. Provider reassignment rendering remains deferred to consolidated candidate acceptance.
