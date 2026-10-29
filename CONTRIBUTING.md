# Contribution conventions

Name files, directories and make targets after the function they serve. Do not include issue names or numbers in those names. Issue references may appear in code, comments, explanatory documentation and commit messages. Preserve existing SQL/API identifiers when renaming them would break compatibility.

When moving or retiring a file, update active documentation links and commands across the project. Do not invent a replacement filename for a retired migration: fresh databases bootstrap from `db/schema.sql`; existing databases use reviewed forward changes. Keep explicit seed configuration separate from private operational records.

`make validate` and `make release-check` enforce naming in this repository. Check the related split Appsmith source with:

```bash
python3 scripts/check_repository_naming.py --repository ../SignatureGate-Appsmith
```

Appsmith object renames must update collection/action metadata and bindings together, preserve Git synchronization IDs and pass exact-source export validation. Verify pull/reload and routes in the test editor before promotion.

Technical software names, filenames, schema/API identifiers, environment-variable names and acceptance criteria may appear in Git, as may Rooted Psyche and Dank Mushrooms. Keep actual individual first-name/last-name combinations, other company names captured in operational records, contact information, financial values, product information, account identifiers, notes, secrets and live configuration mappings out of Git. Public evidence contains sanitized findings, technical provenance and validation status. Refer to the current release plan and acceptance ledger for phase gates; complete navigation/screen documentation and terminology seeds before final packaging.

## Change size, risk, and review policy

Decide whether a change needs a pull request (PR) by **risk and scope**, not by a fixed line-count threshold.

- **Trivial:** spelling, comments, README/CONTRIBUTING clarifications, formatting — a direct commit to `main` is allowed after checking the diff.
- **Small, localized:** a focused syntax correction or narrow bug fix, even across a few scripts — a direct commit to `main` is allowed after relevant validation.
- **Substantial:** features, multiple subsystems, or changes whose side effects are hard to review — use a topic branch and PR, then notify the repository owner and leave the final merge to them.
- **High risk, regardless of lines changed:** significant file deletion/renaming, Docker/infrastructure, deployment, bootstrap/restore or backup workflows, database schema/data migration, authentication/permissions, payroll/financial processing, or production security — use a topic branch and PR. Do not push such changes straight to `main`.

For any substantial/high-risk PR:

1. Branch from current `main`, keep unrelated changes out, and document the scope and risk.
2. Inspect `git diff --stat`, `git diff --check`, and the complete changed/deleted/renamed file list. Specifically verify that all deletions are intended. For broad cleanup, compare against the pre-change tree before committing.
3. Run applicable lint, tests, validation, and build checks; record what passed and what could not be run.
4. Open the PR, make it ready for review (not a draft), include issue references and a concise validation/rollback summary, and notify the owner with its link.
5. **Do not self-merge:** the repository owner reviews and performs the final merge. Respond to PR review comments and revalidate as needed.

## Branch protection and review limitations

The `main` ruleset is intended to block branch deletion and force pushes, with active enforcement and no bypass. The baseline ruleset does **not** itself mandate PRs for substantial changes, CI checks, or conversation resolution. Those requirements above are contributor workflow conventions; do not represent them as GitHub-enforced. If CI status checks are subsequently required, configure actual reliable checks for this repository and verify the effect on direct commits. Do not rewrite protected branch history to repair a mistake.

## SignatureGate validation focus

Preserve the existing naming, privacy, Appsmith synchronization, and release-check instructions above. Changes to signature/evidence storage, agreement handling, authorization, or external integrations count as substantial or high-risk and must use a PR. Keep private participant and operational data out of commits and test evidence.
