# No-email paper agreement: earlier test rollout and validation

**Current sequence:** [Google Drive storage and corrected file transport](GOOGLE_DRIVE_PAPER_VALIDATION.md) supersedes the provider-specific setup below. It uses the same updated test runner, preserves Header Auth, updates the existing paper workflow in place and requests one Drive upload/retrieval/review. The older generic uploader remains available for legacy callers.

October 19, 2026. The operator accepts restored navigation and Agreement Type/template selection at Appsmith 0f8452c. Deferred Intake, its progress and saved-receipt lookup remain accepted. Do not repeat those tests.

The paper implementation is backend **aa21d67** (initial b0be1ba plus pre-storage on-behalf checks) and Appsmith **2b969e7** (application code 8cb2981). It retains every existing native action/collection ID and changes no navigation source or startup metadata. It adds three Manual, actor-bound DB actions and uses the existing paper-upload API action on a new protected workflow route. Existing user-arranged controls remain in place; paper file selection and recovery controls are added.

## 1. Linode: test-only migration and rollback checks

```bash
cd ~/signaturegate &&
git pull --ff-only &&
env -u 'BASH_FUNC__sudo%%' bash releases/v1.2.0/validate_paper_agreement_test.sh
```

Expected: **Paper agreement validation exit code: 0**. The runner verifies signaturegate_test, applies only paper_agreement_upload.sql twice and executes synthetic rollback-only checks. Logs stay private under ~/signaturegate-release-evidence/v1.2.0/paper-agreement-increment. No .env sourcing, admin bootstrap, production query or bulk migration is needed. Stop on a nonzero result.

## 2. Configure the development upload boundary before frontend pull

Import [SignatureGate - Paper Agreement Upload.json](https://github.com/RayzorDuff/SignatureGate/blob/main/n8n/workflows/SignatureGate%20-%20Paper%20Agreement%20Upload.json) as a **new** n8n development workflow. Follow the exact node/credential sequence in [n8n/PAPER_AGREEMENT_UPLOAD.md](../../n8n/PAPER_AGREEMENT_UPLOAD.md): both PG nodes use signaturegate_test; the storage node uses a reviewed test NocoDB destination/credential; NOCODB_BASE_URL is required; the Webhook uses Header Auth and the development Appsmith N8N datasource sends the matching secret header. Keep the secret in server-side credentials/datasource configuration. The old generic workflow is unchanged.

Save and activate this development workflow. It uses /webhook/signaturegate/paper-agreements, not the temporary webhook-test URL. Execution payload retention is disabled in the export; keep it disabled. Do not return credential values, workflow payloads, document bytes or storage paths.

One consequential service-boundary check, after activation:

```bash
read -r -p 'n8n base URL (private input): ' paper_n8n_url
paper_http_status=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --request POST --header 'Content-Type: application/json' --data '{}' \
  "${paper_n8n_url%/}/webhook/signaturegate/paper-agreements")
printf 'Unauthenticated paper upload HTTP status: %s\n' "$paper_http_status"
unset paper_n8n_url
```

Expected **401 or 403**. A 404 means the workflow/route is not active, and 200/202 means the service boundary must be corrected before uploading. This request contains no file, actor, secret or record identifiers. Return only its status code.

## 3. One native upload/review observation

Pull chatgpt_development through **2b969e7** after the backend/workflow configuration succeeds, retain the test datasource and use normal development Deploy.

For the existing no-email synthetic Participant, select the assigned practitioner and applicable template, then **Select signed paper document** and **Upload Paper Agreement**. Use one synthetic PDF/PNG/JPEG up to 5 MiB. Confirm staged feedback and exactly one paper agreement **pending_review**. Open its Evidence link and confirm the intended file is retrievable under the reviewed storage access policy. Digital sending remains unavailable without email. Upload itself must not mark the agreement signed.

Using a Document Reviewer, inspect that same synthetic evidence, enter a review reason and approve once. Confirm signed status. No broad negative-role/file/replay matrix, second enrollment, real agreement/email or production action is requested; those backend/controller cases are automatic.

If the upload response is uncertain, use **Check saved paper upload**, which only reads the owner-scoped receipt. Do not resend the file. If still unresolved, inspect/stop the workflow privately, then **Resolve pending upload** and enter a cancellation reason. Cancellation prevents a late reservation/completion from creating an agreement. Any already stored orphan file needs private cleanup after confirming no agreement references it. Select a new file only after resolution. Do not deliberately manufacture this failure as an additional manual test.

Return the runner exit code, unauthenticated HTTP status and the single upload/review pass/fail in deployed-development mode. Keep operational screenshots and record/file values private.

## Automatic scope and limits

The full source/controller/six disposable-SQL suite and exact-source export checks pass locally. [CI run 39235628457](https://github.com/RayzorDuff/SignatureGate-Appsmith/actions/runs/39235628457) passes both jobs at Appsmith 2b969e7 with backend/schema/runner aa21d67, including the paper contract/reapplication on PostgreSQL 16.13. The actual n8n validation/evidence/binary Code bodies run with synthetic input; checks include file count, size, strict base64, magic/type, safe filenames/relative paths, header-auth configuration, bound SQL, reservation-before-storage and payload-retention settings. Actual backend fixtures cover no-email assigned practitioner and nonmember reviewer, on-behalf authority before storage, self/unassigned/owner/payload denials, pending duplicate claims, exact completion replay, independent reasoned review, missing evidence, audited cancellation and audit rollback. The disposable PostgreSQL 16 runner applies this migration twice and runs these fixtures before the existing Intake lock-contention cases.

Paper-specific simultaneous-session races, installed owners/grants, credentials, live storage/retrieval and native picker/recovery-modal rendering are not established by isolated code tests. The focused successful upload/inspection/review above covers the immediate integration gap. Production restore/rehearsal and external service acceptance remain release gates.
