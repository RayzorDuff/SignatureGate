# Contribution conventions

Name files, directories and make targets after the function they serve. Do not include issue names or numbers in those names. Issue references may appear in code, comments, explanatory documentation and commit messages. Preserve existing SQL/API identifiers when renaming them would break compatibility.

When moving or retiring a file, update active documentation links and commands across the project. Do not invent a replacement filename for a retired migration: fresh databases bootstrap from `db/schema.sql`; existing databases use reviewed forward changes. Keep explicit seed configuration separate from private operational records.

`make validate` and `make release-check` enforce naming in this repository. Check the related split Appsmith source with:

```bash
python3 scripts/check_repository_naming.py --repository ../SignatureGate-Appsmith
```

Appsmith object renames must update collection/action metadata and bindings together, preserve Git synchronization IDs and pass exact-source export validation. Verify pull/reload and routes in the test editor before promotion.

Technical software names, filenames, schema/API identifiers, environment-variable names and acceptance criteria may appear in Git, as may Rooted Psyche and Dank Mushrooms. Keep actual individual first-name/last-name combinations, other company names captured in operational records, contact information, financial values, product information, account identifiers, notes, secrets and live configuration mappings out of Git. Public evidence contains sanitized findings, technical provenance and validation status. Refer to the current release plan and acceptance ledger for phase gates; complete navigation/screen documentation and terminology seeds before final packaging.
