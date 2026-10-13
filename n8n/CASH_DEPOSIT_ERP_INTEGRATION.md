# Cash-deposit ERP integration: RootedOps dependency

SignatureGate v1.2.0 depends on a compatible released RootedOps integration. The ERP workflow exports and ERP application are maintained in **RootedOps**, rather than duplicated here. Release RootedOps and pin the accepted tag, resolved commit SHA, application version and published workflow revisions before SignatureGate production acceptance/packaging.

## Authoritative source locations

Reviewed source baseline: RootedOps `c40bce97f60164e93d7b6d4cdf16c7658e62dae6` (repository version 1.5.25 at inspection). This is source provenance, not a selected release dependency or proof of deployment. The final release tag/version remains pending.

- [Cash Deposit to ERPNext workflow](https://github.com/RayzorDuff/RootedOps/blob/c40bce97f60164e93d7b6d4cdf16c7658e62dae6/n8n/SignatureGate%20-%20Cash%20Deposit%20to%20ERPNext.json)
- [ERP Bank Accounts workflow](https://github.com/RayzorDuff/RootedOps/blob/c40bce97f60164e93d7b6d4cdf16c7658e62dae6/n8n/SignatureGate%20-%20ERP%20Bank%20Accounts.json)
- [ERP deposit service](https://github.com/RayzorDuff/RootedOps/blob/c40bce97f60164e93d7b6d4cdf16c7658e62dae6/erpnext/apps/rootedops_payroll/rootedops_payroll/services/signaturegate_deposits.py)
- [RootedOps integration API](https://github.com/RayzorDuff/RootedOps/blob/c40bce97f60164e93d7b6d4cdf16c7658e62dae6/erpnext/apps/rootedops_payroll/rootedops_payroll/api/integration.py)

Replace the dependency manifest's provisional source reference with the accepted release tag/SHA after its release. Do not import an older workflow just because its filename matches.

## Contracts and ownership

| Boundary | Contract |
| --- | --- |
| Appsmith → n8n synchronization | `POST /webhook/signaturegate/cash-deposit/erp-sync`; body includes `deposit_batch_id` and explicit `mode` |
| Appsmith → n8n bank lookup | `GET /webhook/signaturegate/erp/bank-accounts` |
| n8n → SignatureGate | `begin_cash_deposit_erp_sync(uuid)` and `complete_cash_deposit_erp_sync(...)`; confirmed batch source key `signaturegate:deposit_batch:<uuid>` |
| n8n → RootedOps ERP API | `rootedops_payroll.api.integration.sync_signaturegate_cash_deposit` |
| Bank lookup ERP API | `rootedops_payroll.api.integration.list_signaturegate_cash_deposit_bank_accounts_api` |

SignatureGate owns reviewed donation composition, cash custody, confirmed deposit snapshots and synchronization status. RootedOps/ERPNext owns accounting, bank-transaction matching/reconciliation and durable `RootedOps Integration Event` idempotency. Confirming an operational batch and completing its ERP synchronization are distinct states.

RootedOps validates a confirmed event and seeks a unique eligible bank-match subset under its date/amount rules. If no unique match exists, it does not create accounting. Successful synchronization creates/replays the ERP document and uses ERPNext's native reconciliation. Review eligible bank/account/company configuration privately; do not put real account names, identifiers, amounts or transaction examples into this guide.

An identical retry reuses the durable source event. A conflicting fingerprint or a previously successful event whose ERP document is missing requires manual review. Source-key stability is required across transient HTTP failure/retry. Confirmed deposit composition is not silently rewritten to reconcile accounting.

## Environment and publication

RootedOps workflows use `ERPNEXT_INTERNAL_URL` or `ERPNEXT_PUBLIC_URL` and the configured ERP API authentication (`ERPNEXT_API_KEY`, `ERPNEXT_API_SECRET`). Attach the reviewed SignatureGate PostgreSQL credential to production workflow nodes. Keep actual endpoint/site, account mappings and credential values private.

The current synchronization workflow defaults omitted mode to production. **Development must send `mode: "test"` explicitly.** That branch returns `test_skipped`/`dry_run` before production database/ERP access. It is a non-writing UI route check, not an accounting preview. The accepted production-bound application must deliberately use its reviewed production route/mode.

Import/publish the workflow pair from the released RootedOps revision, review active credentials/routes and verify that the actual deployed ERP application matches the selected dependency. Draft Git JSON and container version labels alone do not establish published workflow or service behavior.

## Validation order

1. Confirm released RootedOps tag/SHA and deployed application revision; resolve the private source-fingerprint difference already found in Phase 1 evidence.
2. Review published workflow revisions, credential destinations, ERP site/company/bank mappings and mode selection privately.
3. In development, exercise a synthetic `mode: "test"` request and verify no production SignatureGate/ERP changes. Keep request/response and any identifiers private; public records contain pass/fail only.
4. On a protected rehearsal copy, verify eligible bank lookup, unique/no/ambiguous matches, successful accounting/reconciliation, same-source retry, HTTP-response loss recovery, conflicting fingerprint, missing ERP document and failure reporting back to SignatureGate.
5. Complete approved production acceptance against the selected dependency, then record sanitized versions/SHAs/workflow revision proof and final release dependency in the v1.2.0 manifest.

Do not run production synchronization or an ERP preview with operational amounts merely to produce a public transcript. Specific rehearsal/production commands follow only after the dependency and environment review; the current commands supplied privately remain limited to private catalog capture and test-database notes validation.


## Source compatibility follow-up

RootedOps main at `750ebc8a8506c20c3df53f6f1b314189ab8cb879` still declares version 1.5.25. The two linked workflow files, SignatureGate deposit service and integration API are byte-identical to reviewed baseline `c40bce97f60164e93d7b6d4cdf16c7658e62dae6` (Git blob comparison). The earlier source review therefore still applies to those four components; this does not certify other RootedOps changes, a release tag, active workflow configuration, authentication or deployment. Pin a released/deployed compatible revision before SignatureGate packaging.

The standalone deposit unit test attempt in this workspace is blocked by missing Frappe (`ModuleNotFoundError: frappe`). No ERP behavior is newly accepted from that attempt; validate in the prepared ERP/Frappe test environment as part of dependency acceptance.
