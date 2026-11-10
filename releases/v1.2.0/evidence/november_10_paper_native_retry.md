# Native paper upload retry — November 10, 2026 UTC

Scope: authenticated Appsmith `chatgpt_development` and its verified `signaturegate_test` datasource, plus the existing test-bound n8n paper workflow. Both n8n database nodes were inspected as using `signaturegate_test`. No master, production database, published production app or shared credential changes.

| Observation | Result / limit |
| --- | --- |
| Native Appsmith serialized JSON envelope | n8n received a JSON string. Parsing that root once before existing request/file guards passed native validation and focused regression CI (PR #38). No file-array string or nested-envelope compatibility was added. |
| Existing owner uncertain request | Read-only receipt lookup returned NULL. Canonical cancellation returned `cancelled`, retaining an audited tombstone before separate synthetic testing. |
| Deployed development runtime | Returned an empty/unconfirmed response; no execution appeared for the inspected workflow. The active-route/deployed-version boundary is not yet proven resolved. |
| Isolated editor draft preview and test webhook | One-page synthetic PDF passed request validation, database reservation, new-request guard and binary preparation. This was a separate request after confirmed cancellation, not a replay. |
| First failing downstream step | `HTTP - Store Paper Evidence`: NocoDB `/api/v2/storage/upload` returned HTTP 401, `ERR_AUTHENTICATION_REQUIRED`, “Authentication required - Unauthorized”. No successful storage response or completion node ran. |
| Credential inspection | Selected existing `Header Auth account 4` uses `Authorization`. Its secret was not changed or copied. The evidence does not establish whether the header/configuration or credential validity is responsible. Do not trial unrelated credentials or alter a shared credential blindly. |
| Final recovery | Receipt lookup remained unresolved; the failed reserved synthetic request was cancelled through the reasoned recovery UI, which confirmed cancellation. Audit records retained; no blind resend. |
| Cleanup | Temporary diagnostic query removed. Appsmith original API body retained and original `/webhook/signaturegate/paper-agreements` route restored after isolated diagnosis. No pin retained and no execution-retention settings changed. |

Workflow settings displayed default **Save** for failed/successful/manual executions. The empty execution list is not evidence that retention was explicitly disabled.

Outstanding acceptance: correct NocoDB authentication binding, verify the intended published/development route, then one new synthetic upload with committed receipt, private storage retrieval verification and authorized independent review. Issue #36 remains a v1.2.0 blocker. Google Drive has not been tested or selected as a replacement. Existing ERP capabilities and accepted cash/authorization evidence remain intact.

References: [SignatureGate PR #38](https://github.com/RayzorDuff/SignatureGate/pull/38), [focused CI](https://github.com/RayzorDuff/SignatureGate/actions/runs/42739227251), [issue #36](https://github.com/RayzorDuff/SignatureGate/issues/36). Appsmith empty-table linter correction remains separate in [Appsmith PR #11](https://github.com/RayzorDuff/SignatureGate-Appsmith/pull/11).
