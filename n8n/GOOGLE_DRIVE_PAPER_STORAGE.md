# Google Drive option for paper agreements

Paper uploads can use either Google Drive or the existing NocoDB storage branch. The current Participant Functions selector defaults to Google Drive; older API callers that omit storage_provider retain the workflow's configured default, initially NocoDB. The accepted provider values are google_drive and nocodb. No upload falls back to another provider after failure.

The earlier March 20 document-storage discussion proposed Google Drive through n8n and a PostgreSQL metadata registry. This release implements the paper-agreement part. The designated organization Google account, exact folder IDs, OAuth credentials and sharing membership are private deployment configuration and are not committed here. A dedicated earlier GitHub issue was not located.

## Which workflow is used

| Workflow | Route | Purpose and compatibility |
| --- | --- | --- |
| SignatureGate - Paper Agreement Upload | POST /webhook/signaturegate/paper-agreements | Current Participant Functions path. Authenticated/scoped reservation, selected storage provider, agreement/evidence/audit completion, durable receipt and cancellation recovery. Update this existing development workflow in place. |
| SignatureGate - Upload Evidence via n8n (Base64 -> NocoDB) | POST /webhook/signaturegate/upload | Existing generic uploader. Returns file objects to older callers; it does not own the new paper request/Participant/practitioner contract. Retained unchanged, including the operator's Header Auth. |

The paper-specific workflow supersedes the old uploader only for current Participant Functions. It is not a drop-in replacement for every legacy caller, and this increment does not delete or repoint those callers. Existing NocoDB evidence is not copied or moved. All previously synchronized workflow node IDs and credential references are retained; only the Drive branch adds nodes. Other workflows' Header Auth changes are untouched. Payload-retention flags are explicitly restored because native export omitted them; binaryMode and the other synchronized settings are retained.

## Setup: existing development workflow

1. Pull the current SignatureGate source and run releases/v1.2.0/validate_paper_agreement_test.sh against signaturegate_test. It applies the base paper migration followed by paper_evidence_storage.sql, each twice, and runs both synthetic rollback suites. Stop on a nonzero result. Do not replay this sequence over production.
2. In the designated organization Google account's My Drive, choose a private paper-agreement test folder within the intended Agreements structure. A shared folder is sufficient; an organizational Shared Drive is not required by this workflow. Keep templates and completed uploads distinguishable. Review inherited folder access and grant only the intended reviewers. Do not enable Anyone with the link.
3. In n8n create/select a Google Drive OAuth2 credential named SIGNATUREGATE_GOOGLE_DRIVE, authorize the designated organization Google account, and attach it to Google Drive - Store Paper Evidence. Use the callback URL shown by n8n for the Google OAuth client. Keep token/client secret values out of files and Git. The node uses Resource File, Operation Upload, binary property data, Parent Drive My Drive and the configured Parent Folder.
4. Configure SIGNATUREGATE_PAPER_DRIVE_FOLDER_ID privately in the n8n environment with that folder ID. Restart/recreate the n8n service only through the existing deployment procedure if required for changed environment variables. The workflow must be allowed to read the referenced environment variables. No folder ID, URL, account or sharing option is accepted from an Appsmith caller.
5. Update the existing development SignatureGate - Paper Agreement Upload workflow from its new export. Preserve its Header Auth credential, both signaturegate_test Postgres credentials, and NocoDB credential/base URL if retaining that option. Select the new Google Drive credential, save and publish the workflow through the normal n8n UI. Do not create a second active workflow at the same webhook path. Keep successful/failed/manual execution payload retention disabled.
6. Pull the companion chatgpt_development frontend and use normal development Deploy. Its Paper document storage selector sends google_drive or nocodb explicitly. API callers without a selection can use the private SIGNATUREGATE_PAPER_STORAGE_PROVIDER environment default; if unset, it remains nocodb for compatibility. Only the selected provider's configuration is required: Drive uploads do not require NOCODB_BASE_URL.

The existing matching Appsmith/n8n Header Auth stays in place. Uploading does not create a sharing permission or make a file public. Authorized Appsmith users also need appropriate Google access to open private Drive files; Appsmith roles do not automatically modify Google ACLs.

## File payload repair

The API action now uses a single JSON.stringify expression for the entire request. files is an array of objects containing name, type and Base64 data. It is never a quoted JSON string or null. actor_email still comes from appsmith.user.email. The upload controller snapshots the file and provider and passes both in .run(parameters); it checks authority and selection changes before dispatch.

Use Upload Paper Agreement to exercise this path. Clicking Run directly in the API editor does not supply the controller's request/resource/file parameters; its preview therefore contains empty identifiers and files: [], and the workflow rejects it before storage. Do not insert live file bytes into a static action body or return them in debug output. Actual action-body tests round-trip the parameterized JSON and verify the array and bytes survive, including quoted names, missing parameters and forged actor input.

## Storage references and recovery

Drive returns a file ID, confirmed parent folder, MIME type and byte size. The workflow verifies those fields and stores storage_provider=google_drive, drive_file_id and the canonical controlled Drive link on the pending-review agreement. Arbitrary returned URLs are not trusted. Participant Functions and Audit Log construct links from validated file IDs; existing relative NocoDB references continue to work. Google login and folder permissions govern the Drive link.

The provider is part of the reserved request's identity. A pending request cannot be replayed/completed against another provider. Ordinary retry remains read-only. Resolve an old failed/null-file request with Check saved paper upload and, if unresolved, the existing reasoned cancellation flow before selecting a new file. Never change the provider and resend the same uncertain request. Cancellation does not remove an orphan file from either provider; inspect and reconcile it privately.

## Focused validation

After the test-only SQL runner and workflow configuration, use one synthetic PDF for the existing no-email test Participant. Select Google Drive, upload through the button, confirm one pending_review agreement, then open Evidence and verify the file is readable in the intended private test folder. A Document Reviewer can inspect and approve it with a reason. Return only runner exit code and upload/retrieval/review pass or fail. No broad file/role/replay matrix or repeat Intake is requested; those cases are automatic.

The operator reports Header Auth on all SignatureGate workflows; preserve those choices. The existing unauthenticated route check remains available in PAPER_AGREEMENT_VALIDATION.md if the credential/route changes. Installed OAuth/folder access and native Appsmith execution still require the focused Drive check. Source tests do not establish a live Google grant or perform an operational upload.

Official implementation references: [n8n Drive upload](https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.googledrive/file-operations/#upload-a-file), [n8n 2.16.1 upload implementation](https://github.com/n8n-io/n8n/blob/n8n%402.16.1/packages/nodes-base/nodes/Google/Drive/v2/actions/file/upload.operation.ts), and [Google Drive parent folders](https://developers.google.com/workspace/drive/api/guides/folder).
