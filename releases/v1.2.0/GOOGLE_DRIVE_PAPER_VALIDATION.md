# Private Drive paper storage and file transport validation

October 19–20, 2026 increment. Appsmith **6bee614** fixes the complete JSON request and adds the Google Drive/NocoDB choice. SignatureGate backend/workflow **575d4c4** adds provider-specific references and preserves existing receipts. RootedOps **58d2021**, incremental version **1.5.26**, passes the optional private folder/default-provider environment into n8n. No workflow is deployed, OAuth grant created or real document uploaded by these source commits.

The earlier March 20 Drive-through-n8n storage discussion was recovered; a dedicated prior GitHub issue was not found. The operator's latest Appsmith null-default body edit and all synchronized Header Auth changes were pulled first. All existing native Appsmith resource IDs and paper-workflow node IDs/credentials remain intact. The accepted navigation implementation is unchanged.

## 1. Test-only database upgrade

Pause the development paper workflow while applying its API changes. The generic uploader and production workflows do not need to change.

```bash
cd ~/signaturegate &&
git pull --ff-only &&
env -u 'BASH_FUNC__sudo%%' bash releases/v1.2.0/validate_paper_agreement_test.sh
```

Expected: **Paper agreement validation exit code: 0**. The runner verifies signaturegate_test, applies base paper then paper_evidence_storage.sql, each twice, and runs both rollback-only fixture files. Detailed logs stay private. No production SQL, bootstrap, new Directory Manager or bulk migration is requested.

## 2. Pass the private folder into n8n

Pull RootedOps and edit its existing private .env:

```bash
cd ~/RootedOps && git pull --ff-only
nano .env
```

Add/update these keys with the actual private test folder ID:

```dotenv
SIGNATUREGATE_PAPER_DRIVE_FOLDER_ID=replace_with_private_test_folder_id
SIGNATUREGATE_PAPER_STORAGE_PROVIDER=nocodb
```

The current Appsmith selector defaults to Google Drive and sends the choice explicitly. nocodb here preserves the fallback for older callers without a selection; it does not override the selected Google Drive option.

Apply only the n8n environment:

```bash
cd ~/RootedOps &&
sudo docker compose --env-file ./.env -f docker/docker-compose.yml config --quiet &&
sudo docker compose --env-file ./.env -f docker/docker-compose.yml up -d --no-deps n8n
```

This briefly recreates n8n with its persistent volume and credentials retained. It does not deploy ERPNext or restart unrelated services. Do not print or return .env or rendered Compose configuration.

## 3. Update the existing paper workflow

Follow [the exact OAuth/folder and node setup](../../n8n/GOOGLE_DRIVE_PAPER_STORAGE.md). In n8n, authorize the designated organization Google account using its Google Drive OAuth2 credential and select that credential on **Google Drive - Store Paper Evidence**. Use a private folder in that account's **My Drive**, with access explicitly granted to intended reviewers. The workflow performs no sharing/permission operation. Folder IDs, account addresses, tokens and sharing membership remain private.

Update the existing **SignatureGate - Paper Agreement Upload** development workflow in place from the new JSON. Retain its Header Auth and signaturegate_test Postgres credentials; retain the existing NocoDB credential/base URL for that option. Configure the new Drive node, save and publish normally. Do not add a second active workflow with the same webhook path. Successful/failed/manual execution payload retention is explicitly disabled.

**The older SignatureGate - Upload Evidence via n8n (Base64 -> NocoDB) remains available and unchanged for legacy callers.** It is a generic files-only uploader. Current Participant Functions uses the protected paper workflow, which also owns reservation, agreement/evidence/receipt/audit completion and recovery. They are not interchangeable payload contracts. No historical files are moved by this change.

## 4. One native Drive observation

Pull chatgpt_development through **6bee614**, keep the test datasource and use normal development Deploy. For the existing no-email synthetic Participant, choose its assigned practitioner/applicable template and **Google Drive** storage, select one synthetic PDF/PNG/JPEG up to 5 MiB and click **Upload Paper Agreement**.

Confirm one pending_review agreement, readable evidence from the intended private Drive folder, and independent Document Reviewer approval with a reason. No repeat Intake/navigation/role matrix or deliberate failure is requested. The API-editor Run button does not supply the controller's .run parameters; its empty-parameter preview has files: [] and is rejected before storage. Exercise the actual Upload button. If a previous attempt remains uncertain, use its existing read-only receipt lookup and reasoned cancellation before starting a new file/request; never resend the same uncertain key to another provider.

Return only the SQL runner exit code and Drive upload/retrieval/review pass or fail in deployed-development mode. Do not return document bytes, names, contacts, file/folder IDs, URLs or credential values. The operator reports Header Auth on all SignatureGate workflows; those choices are preserved. Existing unauthenticated-denial commands remain in the prior paper validation record if the Header Auth or route changes.

## Automatic evidence and remaining gates

The full source/controller/six disposable-SQL suite, actual n8n Code-body/provider routing tests and exact-source export preservation pass locally. [CI run 39366285224](https://github.com/RayzorDuff/SignatureGate-Appsmith/actions/runs/39366285224) passes both jobs with Appsmith 6bee614/backend 575d4c4. Its PostgreSQL 16.13 output confirms paper_storage_contract passed, paper contract/reapplication and successful disposable database cleanup. The existing four genuine contention cases concern Intake; no paper-specific simultaneous-session race is newly claimed.

New tests cover the actual API-body JSON round trip, non-null file arrays/bytes, quotes/missing parameters/forged actor, selected-provider validation, per-provider prerequisites, private Drive parent/type/size confirmation, controlled file-ID links, legacy NocoDB evidence, owner/provider conflicts, cancellation, review/audit invariants and preserved legacy receipt/hash across migration reapplication. RootedOps release metadata and parsed environment checks pass. Installed OAuth/Drive access, native transport and protected production restore/grants, other integrations, coordinated dependency promotion and final packaging remain distinct release gates. The upgrade draft now has 23 undecided entries and nine unverified environment proofs.
