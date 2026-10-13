# Access initialization and workflow feedback validation

This development increment changes Appsmith source only. It installs no migration, grants no permission and does not enable paper upload or production ERP requests. Preserve editor work before pulling `chatgpt_development`; use the `signaturegate_test` datasource. Do not repeat the first-manager bootstrap to repair page access.

## Accepted results

Operator reports `validate_directory_review_test.sh` exit 0 at backend `8a08e74`. This accepts test application/reapplication and the runner's provider, company-contact, authorization, revival, contributor-mailing and capacity-independence checks. The Bash `_sudo` completion-import warning did not fail that run. Invoke scripts with `env -u 'BASH_FUNC__sudo%%' bash` to avoid importing that completion function.

Cash access succeeded after Retry. The final Exclude/hidden-row/reveal/required-reason/Revive scenario returned the donation to `cash_on_hand`; it need not be repeated. The earlier observation of `pending_review` after exclusion is still unresolved. Actual prepared-SQL tests check that exclusion preserves verified status; automatic row selection is removed after refresh to prevent a different row appearing selected. This is a possible display explanation, not an established diagnosis.

## Automated confidence

- High for 24 synthetic Intake controller/prepared-SQL cases covering Participant, dual capacity, individual Contributor and company Contributor enrollment; supported contact combinations, optional DOB, independent mailing consent and shared contact-role reuse. Signing HTTP is stubbed.
- High for Terminology page-load registration, account-bound authority, denied/unlinked/error states, one read-only startup retry, save preflight and committed-refresh warnings. Cash access uses the same bounded read retry without retrying writes or a denied role.
- High for signing stage order, delivery claims only with service confirmation, busy guards and partial-save warnings; mailing feedback distinguishes queued requests from external completion. ERP feedback announces local confirmation before requesting synchronization and the development default remains `test`.
- Existing role, cash dialog, company/provider, action-mode and prepared-SQL regression evidence is reused. Source/export checks do not establish live SDK behavior or external delivery.

Paper Intake is now blocked before creating a record or sending a file. Restoring paper capability and safe recovery/atomicity across independently committed Intake actions remain release gates.

## Sequence: one read-only command, two page openings

On Linode:

```bash
cd ~/signaturegate
git pull --ff-only
env -u 'BASH_FUNC__sudo%%' bash releases/v1.2.0/inspect_cash_reconciliation_test.sh
```

Expected exit 0 and database `signaturegate_test`. Both API-availability fields must be true before using the new Intake source. If either is false, stop and return the summary; do not replay migrations or bootstrap. The nine output fields contain no operational identities, amounts, contacts or reasons. Comparison concerns the globally latest two exclusions; intervening activity may prevent it from describing the earlier report. Null means insufficient matching history, not a failure.

After Appsmith development pull and reload:

1. Open **Terminology Administration** with Directory Manager permission: the form should appear after access loading, with navigation retained. No terminology change is needed.
2. Open **Cash Deposits** with Donations Reviewer permission: a single transient startup failure should recover automatically. Persistent lookup failures must say access could not be checked, rather than claiming a missing role.

During the next ordinary authorized test Intake or digital agreement request, observe stage messages and one final outcome. There is no need to create extra records, send extra messages or post accounting documents just for this check. Listmonk stages say queued; signing only says email sent when the service explicitly confirms it; ERP completion requires a successful response. Return the sanitized summary, page pass/fail and any stage/error class. Keep screenshots, raw logs and record details private.

The retained legacy Members–Intake page also blocks paper selection before any identity write. Its upload execution code is removed and paper controls are disabled. Its digital stage messages remain available; no external upload request is made. The pre-write boundary and disabled controls are exercised automatically.


## Operator checkpoint at 93b2082

Read-only cash observation exit 0 on `signaturegate_test`: both Intake APIs exist, the latest exclusion concerns a verified donation and is still active, and the two most recent exclusions are for different donations. No intervening verification was found for the earlier of those two records. This does not establish which row was selected in the earlier UI report and does not prove a same-donation status regression. Preserve the unresolved display/history observation for consolidated acceptance; no repeat exclusion is requested.

Cash Deposits opens without Retry. Terminology Administration opens with the authorized form after Retry Access; permission is correct, but first-load reliability is not yet accepted. The controller now retries one failed terminology-data read separately from the access read, keeps the form closed until labels load, and distinguishes data failure from denied access. Source tests cover cold/persistent label failure and account change during loading; the live root cause remains unproven.

The operator will navigate interfaces independently. This walkthrough does not block independent development. Reuse passing backend and dialog evidence; no migration or new service request is introduced by this checkpoint.
