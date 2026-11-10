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


## Resolved native acceptance — November 9 Denver evening

This later checkpoint supersedes the storage/authentication and active-route blockers above. Read-only inspection of the retained production generic uploader identified `Header Auth account 2` with `xc-token`; the test paper node incorrectly used `Header Auth account 4` with `Authorization`. Only the test paper workflow binding was changed and published. No credential secret/value or production workflow change, no new grants and no storage redesign. The saved source descriptor now matches the established generic uploader.

One new synthetic PDF was submitted through the development editor preview using the original active `/webhook/signaturegate/paper-agreements` route, after the UI confirmed no unresolved checkpoint. The upload returned success and created a pending_review agreement without an email. The evidence link opened the expected synthetic one-page PDF. A browser download was byte-identical to the source: 1,607 bytes, SHA-256 `ade2242173257b2dcbc40880888c26bb474407b3fc3e95a8e684a1f0fc2698c5`.

The existing authorized reviewer supplied an explicit synthetic-only review reason and approved the document. This is a test document explicitly marked NOT AN AGREEMENT. The reviewer is distinct from the test Participant; the same operator uploaded and reviewed it, so no separate reviewer-account login is claimed.

Read-only native SQL on the test datasource returned:

| Field | Verified result |
| --- | --- |
| Database | `signaturegate_test` |
| Request | `3d0616b5-1df9-4b29-80fa-3b92b6ee2421` |
| Receipt | `committed` |
| Agreement | `a42804d1-0d04-43f1-bf91-2634ad34b3aa` |
| Agreement status / method | `signed` / `paper` |
| Reviewed at | `2026-11-10T02:32:35.746991Z` (November 9, 7:32 PM Denver) |
| Reviewer recorded / distinct from Participant | true / true |
| Stored evidence count | 1 |
| `member_agreement.paper_uploaded` audit count | 1 |
| `member_agreement.signed` audit count | 1 |

A fresh development runtime navigation retained the signed row. Check saved paper upload confirmed the saved request without resending a file. The temporary diagnostic query was removed after verification. Native NocoDB functional acceptance has passed; PR #38/source review and the normal production upgrade/promotion gates remain. Do not close this as production acceptance or claim Drive testing.
